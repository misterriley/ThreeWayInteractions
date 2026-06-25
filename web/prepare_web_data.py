import os
import re
import shutil
import json
import csv

def prepare_web_data():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(base_dir)
    outputs_dir = os.path.join(project_dir, 'outputs')
    
    web_assets_dir = os.path.join(base_dir, 'assets')
    web_images_dir = os.path.join(web_assets_dir, 'images')
    web_data_dir = os.path.join(web_assets_dir, 'data')
    
    # Create directories
    os.makedirs(web_images_dir, exist_ok=True)
    os.makedirs(web_data_dir, exist_ok=True)
    
    cohorts = {
        'hcp': ['emotion', 'gambling', 'language', 'motor', 'relational', 'rest', 'rest2', 'social', 'wm'],
        'imagen': ['MID', 'SST']
    }
    
    results_data = {
        'hcp': {},
        'imagen': {}
    }
    
    for cohort, tasks in cohorts.items():
        for task in tasks:
            task_output_dir = os.path.join(outputs_dir, cohort, task)
            report_path = os.path.join(task_output_dir, f'{cohort}_{task}_normative_report.txt')
            
            if not os.path.exists(report_path):
                print(f"Report for {cohort} task {task} not found at {report_path}. Skipping...")
                continue
                
            print(f"Processing {cohort} task {task}...")
            
            # Create destination image directory
            dest_image_dir = os.path.join(web_images_dir, task)
            os.makedirs(dest_image_dir, exist_ok=True)
            
            # Copy all images
            images_to_copy = [
                f'{cohort}_{task}_barycenter_carpet_plot.png',
                f'{cohort}_{task}_barycenter_lollipop_plot.png',
                f'{cohort}_{task}_pga_scree_plot.png',
                f'{cohort}_{task}_pga_pc1_geodesic.png',
                f'{cohort}_{task}_pga_pc2_geodesic.png',
                f'{cohort}_{task}_pga_pc1_direction_carpet_plot.png',
                f'{cohort}_{task}_pga_pc2_direction_carpet_plot.png',
                f'{cohort}_{task}_coskewness_triads_lollipop_plot.png',
                f'{cohort}_{task}_coskewness_triads_distinct_lollipop_plot.png'
            ]
            
            for img_name in images_to_copy:
                src_img = os.path.join(task_output_dir, img_name)
                if os.path.exists(src_img):
                    shutil.copy(src_img, os.path.join(dest_image_dir, img_name))
                else:
                    print(f"  Warning: Image {img_name} not found.")
                    
            # Parse text report
            with open(report_path, 'r') as f:
                content = f.read()
                
            metadata = {}
            # Parse data source
            match_ds = re.search(r"Data Source:\s*(.*)", content)
            if match_ds:
                metadata['data_source'] = match_ds.group(1).strip()
                
            # Parse analysis time
            match_at = re.search(r"Analysis Time:\s*(.*)", content)
            if match_at:
                metadata['analysis_time'] = match_at.group(1).strip()
                
            # Parse computation time
            match_ct = re.search(r"Computation Time:\s*(.*)", content)
            if match_ct:
                metadata['computation_time'] = match_ct.group(1).strip()
                
            # Parse CP components
            cp_components = []
            cp_sec = re.search(
                r"CP TENSOR BARYCENTER COMPONENTS \(NON-GAUSSIAN VARIANCE\):\n------------------------------------------------------------\n(.*?)(?=\n\n|\n-|$)", 
                content, re.DOTALL
            )
            if cp_sec:
                lines = cp_sec.group(1).strip().split('\n')
                for line in lines:
                    m = re.match(r"Component\s+(\d+):\s*lambda\s*=\s*([\d.-]+)\s*\(([\d.-]+)%\s*variance\s*explained\)", line.strip())
                    if m:
                        cp_components.append({
                            'component': int(m.group(1)),
                            'lambda_val': float(m.group(2)),
                            'pct_variance': float(m.group(3))
                        })

            # Parse Barycenter elements
            barycenter_elements = []
            barycenter_sec = re.search(
                r"STRONGEST ELEMENTS OF BURES-WASSERSTEIN BARYCENTER:\n------------------------------------------------------------\n(.*?)(?=\n\n|\n-|$)", 
                content, re.DOTALL
            )
            if barycenter_sec:
                lines = barycenter_sec.group(1).strip().split('\n')
                for line in lines:
                    m = re.match(r"\d+\.\s+(\w+)\s*-\s*(\w+):\s*r\s*=\s*([\d.-]+)", line.strip())
                    if m:
                        barycenter_elements.append({
                            'node_a': m.group(1),
                            'node_b': m.group(2),
                            'r_val': float(m.group(3))
                        })
                        
            # Parse General and Distinct Triads from CSV
            general_triads = []
            distinct_triads = []
            csv_path = os.path.join(task_output_dir, f'{cohort}_{task}_coskewness_triads.csv')
            
            if os.path.exists(csv_path):
                # First pass: calculate sum of squares of M_abc
                sum_sq = 0.0
                all_rows = []
                with open(csv_path, 'r') as csv_file:
                    reader = csv.DictReader(csv_file)
                    for row in reader:
                        m_abc = float(row['M_abc'])
                        sum_sq += m_abc ** 2
                        all_rows.append(row)
                
                # Prevent division by zero
                if sum_sq == 0.0:
                    sum_sq = 1e-9
                    
                # Second pass: extract top 10 general and distinct triads
                general_count = 0
                distinct_count = 0
                for rank_idx, row in enumerate(all_rows, 1):
                    m_abc = float(row['M_abc'])
                    abs_m_abc = float(row['Abs_M_abc'])
                    pct_var = (m_abc ** 2) / sum_sq * 100
                    
                    triad_obj = {
                        'rank': rank_idx,
                        'node_a': row['Node_A'],
                        'node_b': row['Node_B'],
                        'node_c': row['Node_C'],
                        'm_abc': m_abc,
                        'abs_m_abc': abs_m_abc,
                        'pct_variance': pct_var
                    }
                    
                    # Add to general list (up to 10)
                    if general_count < 10:
                        general_triads.append(triad_obj)
                        general_count += 1
                        
                    # Add to distinct list if distinct (up to 10)
                    is_distinct = (row['Node_A'] != row['Node_B']) and \
                                  (row['Node_B'] != row['Node_C']) and \
                                  (row['Node_A'] != row['Node_C'])
                    if is_distinct and distinct_count < 10:
                        distinct_obj = triad_obj.copy()
                        distinct_obj['rank'] = distinct_count + 1
                        distinct_triads.append(distinct_obj)
                        distinct_count += 1
            else:
                print(f"  Warning: CSV file {csv_path} not found.")
                        
            # Load task interpretation
            interpretation_path = os.path.join(task_output_dir, f'{cohort}_{task}_interpretation.txt')
            interpretation_content = ""
            if os.path.exists(interpretation_path):
                with open(interpretation_path, 'r') as f:
                    interpretation_content = f.read()
            else:
                print(f"  Warning: Interpretation file {interpretation_path} not found.")
                
            results_data[cohort][task] = {
                'metadata': metadata,
                'cp_components': cp_components,
                'barycenter_elements': barycenter_elements,
                'general_triads': general_triads,
                'distinct_triads': distinct_triads,
                'raw_report': content,
                'interpretation': interpretation_content
            }
            
    # Process group/cohort-level analysis data
    for cohort in cohorts.keys():
        group_output_dir = os.path.join(outputs_dir, cohort, 'group')
        report_path = os.path.join(group_output_dir, f'{cohort}_task_separation_report.txt')
        
        if not os.path.exists(report_path):
            print(f"Group report for {cohort} not found at {report_path}. Skipping group analysis...")
            continue
            
        print(f"Processing group task separation for {cohort}...")
        
        # Create destination image directory
        dest_group_img_dir = os.path.join(web_images_dir, 'group')
        os.makedirs(dest_group_img_dir, exist_ok=True)
        
        # Copy group carpet plot
        carpet_name = f'{cohort}_task_separation_f_values_carpet_plot.png'
        src_carpet = os.path.join(group_output_dir, carpet_name)
        if os.path.exists(src_carpet):
            shutil.copy(src_carpet, os.path.join(dest_group_img_dir, carpet_name))
            
        # Copy all distribution plots
        for filename in os.listdir(group_output_dir):
            if filename.startswith(f'{cohort}_sep_plot_rank') and filename.endswith('.png'):
                shutil.copy(os.path.join(group_output_dir, filename), os.path.join(dest_group_img_dir, filename))
                
        # Parse group report
        with open(report_path, 'r') as f:
            content = f.read()
            
        metadata = {}
        # Parse data source
        match_ds = re.search(r"Data Source:\s*(.*)", content)
        if match_ds:
            metadata['data_source'] = match_ds.group(1).strip()
            
        # Parse analysis time
        match_at = re.search(r"Analysis Time:\s*(.*)", content)
        if match_at:
            metadata['analysis_time'] = match_at.group(1).strip()
            
        # Parse number of tasks
        match_nt = re.search(r"Number of Tasks:\s*(\d+)", content)
        if match_nt:
            metadata['num_tasks'] = int(match_nt.group(1))
            
        # Parse bootstraps per task
        match_bt = re.search(r"Bootstraps/Task:\s*(\d+)", content)
        if match_bt:
            metadata['bootstraps'] = int(match_bt.group(1))
            
        # Parse degrees of freedom
        match_df = re.search(r"DF \(Between/Within\):\s*(\d+)\s*/\s*(\d+)", content)
        if match_df:
            metadata['df_between'] = int(match_df.group(1))
            metadata['df_within'] = int(match_df.group(2))
            
        # Parse top 10 task separating connections table
        top_connections = []
        table_sec = re.search(
            r"Rank\s+Connection\s+F-value\s+df_between\s+p-value\s*\n------------------------------------------------------------\n(.*?)\n------------------------------------------------------------",
            content, re.DOTALL
        )
        if table_sec:
            lines = table_sec.group(1).strip().split('\n')
            for line in lines:
                m = re.match(r"(\d+)\s+([\w\s-]+)\s+([\d.-]+)\s+(\d+)\s+(.*)", line.strip())
                if m:
                    rank_num = int(m.group(1))
                    conn_name = m.group(2).strip()
                    f_val = float(m.group(3))
                    df_b = int(m.group(4))
                    p_val_str = m.group(5).strip()
                    
                    # Split connection name
                    net1, net2 = [x.strip() for x in conn_name.split('-')]
                    
                    top_connections.append({
                        'rank': rank_num,
                        'connection': conn_name,
                        'node_a': net1,
                        'node_b': net2,
                        'f_val': f_val,
                        'df_between': df_b,
                        'p_val': p_val_str
                    })
                    
        # Generate Group Interpretation
        group_interpretation = f"""============================================================
TASK DIFFERENTIATION INTERPRETATION: {cohort.upper()} COHORT
============================================================

INTRODUCTION:
------------------------------------------------------------
This analysis compares functional connectivity (FC) across {metadata.get('num_tasks', 'multiple')} task conditions
in the {cohort.upper()} cohort using a one-way Analysis of Variance (ANOVA) across subjects.
The goal is to determine which pairwise connection edges are most sensitive to task demands, 
shifting their coupling strength to coordinate task-specific neural processes.

KEY FINDINGS & FUNCTIONAL SEPARATION:
------------------------------------------------------------
The top distinguishing connections ranked by their F-statistic represent major neural communication
gates that are reconfigured during active task processing:
"""
        
        # Add details about top connections
        for idx, conn in enumerate(top_connections[:3], 1):
            group_interpretation += f"\n{idx}. {conn['connection']} (F = {conn['f_val']:.2f}, p {conn['p_val']})\n"
            if conn['connection'] == 'DMN - Mot':
                group_interpretation += "   -> Represents the segregation/integration boundary between self-referential thought (DMN)\n" \
                                        "      and somatic motor execution (Mot). This connection is highly anti-correlated during\n" \
                                        "      the motor task (reflecting focus on physical movements) but becomes integrated/positive\n" \
                                        "      during relational reasoning and gambling reward tracking.\n"
            elif conn['connection'] == 'VI - VII' or conn['connection'] == 'VII - VAs' or conn['connection'] == 'VI - VAs':
                group_interpretation += "   -> Represents visual sensory hierarchy coordination. The coupling changes significantly\n" \
                                        "      depending on the visual detail and complexity demands of the task (e.g. highest in relational\n" \
                                        "      matching, lowest or negative during social theory of mind animation viewing).\n"
            elif conn['connection'] == 'Mot - VAs':
                group_interpretation += "   -> Represents the sensorimotor-to-visual coordination gate, mediating how visual inputs\n" \
                                        "      are mapped to manual motor outputs (button presses) during reaction-heavy task states.\n"
            elif conn['connection'] == 'FP - DMN':
                group_interpretation += "   -> Represents the executive control vs. default mode network boundary. This edge separates\n" \
                                        "      highly structured top-down task regulation (SST/Stop Signal Task, where it is negative) from\n" \
                                        "      reward anticipation/delay (MID, where it is positive).\n"
            else:
                group_interpretation += f"   -> Represents a critical task-gating boundary between the {conn['node_a']} and {conn['node_b']} systems.\n"
                
        group_interpretation += "\nSUMMARY:\n------------------------------------------------------------\n"
        if cohort == 'hcp':
            group_interpretation += "In the HCP cohort, task differentiation is heavily dominated by the segregation of the Default\n" \
                                    "Mode Network (DMN) from somatomotor (Mot) and visual processing networks, alongside fine-tuned\n" \
                                    "visual system integration. This highlights that the normative population primarily reconfigures\n" \
                                    "its sensory processing pathways and default-mode suppression to adapt to different task states."
        else:
            group_interpretation += "In the IMAGEN cohort, task differentiation highlights stop-signal inhibition (SST) vs. reward anticipation\n" \
                                    "(MID). The primary differences reside in the coupling between visual hierarchies (VI-VII) and the\n" \
                                    "coordination between frontoparietal (FP) control and default mode (DMN) networks, showing a clear\n" \
                                    "reconfiguration of attentional focus and cognitive control strategy."
        
        group_interpretation += "\n============================================================\n"

        results_data[cohort]['group'] = {
            'metadata': metadata,
            'top_connections': top_connections,
            'raw_report': content,
            'interpretation': group_interpretation
        }
        
    # Write as JS file to make it fully standalone (double-clickable index.html without CORS issues)
    js_content = f"const RESULTS_DATA = {json.dumps(results_data, indent=2)};"
    with open(os.path.join(web_data_dir, 'results.js'), 'w') as f:
        f.write(js_content)
        
    print("\nWeb assets prepared successfully!")

if __name__ == '__main__':
    prepare_web_data()
