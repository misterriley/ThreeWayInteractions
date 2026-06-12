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
                        
            results_data[cohort][task] = {
                'metadata': metadata,
                'cp_components': cp_components,
                'barycenter_elements': barycenter_elements,
                'general_triads': general_triads,
                'distinct_triads': distinct_triads
            }
            
    # Write as JS file to make it fully standalone (double-clickable index.html without CORS issues)
    js_content = f"const RESULTS_DATA = {json.dumps(results_data, indent=2)};"
    with open(os.path.join(web_data_dir, 'results.js'), 'w') as f:
        f.write(js_content)
        
    print("\nWeb assets prepared successfully!")

if __name__ == '__main__':
    prepare_web_data()
