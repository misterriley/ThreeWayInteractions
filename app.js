/**
 * NeuroFlow - Normative Brain Dynamics Dashboard
 * Frontend application logic for a fully standalone web application.
 */

document.addEventListener('DOMContentLoaded', () => {
    // 1. Check if RESULTS_DATA is available
    if (typeof RESULTS_DATA === 'undefined') {
        console.error('Error: RESULTS_DATA is not loaded. Please make sure assets/data/results.js exists and is populated.');
        document.getElementById('current-task-title').textContent = 'Error Loading Data';
        document.querySelector('.subtitle').textContent = 'Please run python prepare_web_data.py to generate results.js';
        return;
    }

    // 2. Define tasks, labels, and cohorts
    const hcpTasks = ['emotion', 'gambling', 'language', 'motor', 'relational', 'rest', 'rest2', 'social', 'wm'];
    const imagenTasks = ['MID', 'SST'];
    
    const taskLabels = {
        // HCP tasks
        'emotion': 'Emotion Processing',
        'gambling': 'Gambling / Reward',
        'language': 'Language Processing',
        'motor': 'Motor Task',
        'relational': 'Relational Processing',
        'rest': 'Resting State (Run 1)',
        'rest2': 'Resting State (Run 2)',
        'social': 'Social Cognition',
        'wm': 'Working Memory',
        // IMAGEN tasks
        'MID': 'Monetary Incentive Delay (MID)',
        'SST': 'Stop Signal Task (SST)'
    };

    let currentCohort = 'hcp';
    let currentTask = 'emotion';
    let currentView = 'task';
    let searchQuery = '';

    // Helper to generate task navigation item
    function createTaskItem(cohort, task) {
        const li = document.createElement('li');
        li.className = `task-item${cohort === currentCohort && task === currentTask ? ' active' : ''}`;
        li.dataset.task = task;
        li.dataset.cohort = cohort;
        
        // Add task icon based on type
        let iconHtml = '<i class="fa-solid fa-brain nav-icon"></i>';
        if (task.startsWith('rest')) {
            iconHtml = '<i class="fa-solid fa-bed nav-icon"></i>';
        } else if (task === 'motor' || task === 'SST') {
            iconHtml = '<i class="fa-solid fa-person-running nav-icon"></i>';
        } else if (task === 'language') {
            iconHtml = '<i class="fa-solid fa-comments nav-icon"></i>';
        } else if (task === 'gambling' || task === 'MID') {
            iconHtml = '<i class="fa-solid fa-dice nav-icon"></i>';
        } else if (task === 'emotion') {
            iconHtml = '<i class="fa-solid fa-face-smile nav-icon"></i>';
        } else if (task === 'social') {
            iconHtml = '<i class="fa-solid fa-users nav-icon"></i>';
        } else if (task === 'relational') {
            iconHtml = '<i class="fa-solid fa-diagram-project nav-icon"></i>';
        } else if (task === 'wm') {
            iconHtml = '<i class="fa-solid fa-list-check nav-icon"></i>';
        }
        
        li.innerHTML = `${iconHtml}<span>${taskLabels[task] || task}</span>`;
        
        li.addEventListener('click', () => {
            if (currentCohort === cohort && currentTask === task && currentView === 'task') return;
            
            // Update active states in both lists
            document.querySelectorAll('.task-item').forEach(item => item.classList.remove('active'));
            li.classList.add('active');
            
            // Switch task and cohort
            currentCohort = cohort;
            currentTask = task;
            currentView = 'task';
            loadTaskData(currentCohort, currentTask);
        });
        
        return li;
    }

    // Helper to generate group navigation item
    function createGroupItem(cohort) {
        const li = document.createElement('li');
        li.className = `task-item group-nav-item${cohort === currentCohort && currentView === 'group' ? ' active' : ''}`;
        li.innerHTML = `<i class="fa-solid fa-ranking-stars nav-icon"></i><span>Task Differentiation</span>`;
        
        li.addEventListener('click', () => {
            if (currentCohort === cohort && currentView === 'group') return;
            
            // Update active states in both lists
            document.querySelectorAll('.task-item').forEach(item => item.classList.remove('active'));
            li.classList.add('active');
            
            currentCohort = cohort;
            currentView = 'group';
            loadGroupData(currentCohort);
        });
        
        return li;
    }

    // 3. Initialize Sidebar Lists
    const hcpListEl = document.getElementById('hcp-task-list');
    const imagenListEl = document.getElementById('imagen-task-list');
    
    hcpListEl.innerHTML = '';
    imagenListEl.innerHTML = '';

    hcpTasks.forEach(task => {
        hcpListEl.appendChild(createTaskItem('hcp', task));
    });
    hcpListEl.appendChild(createGroupItem('hcp'));

    imagenTasks.forEach(task => {
        imagenListEl.appendChild(createTaskItem('imagen', task));
    });
    imagenListEl.appendChild(createGroupItem('imagen'));

    // 4. Initialize Tabs System
    const tabBtns = document.querySelectorAll('.tab-btn');
    const tabContents = document.querySelectorAll('.tab-content');

    tabBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            const targetTab = btn.dataset.tab;
            
            // Toggle active buttons
            tabBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            
            // Toggle active content panels
            tabContents.forEach(content => {
                if (content.id === targetTab) {
                    content.classList.add('active');
                } else {
                    content.classList.remove('active');
                }
            });
        });
    });

    // 5. Initialize Search Input
    const searchInput = document.getElementById('triad-search-input');
    searchInput.addEventListener('input', (e) => {
        searchQuery = e.target.value.trim().toLowerCase();
        renderTriadsTable();
    });

    // 6. Data Loading & Rendering Function
    function loadTaskData(cohortName, taskName) {
        const cohortData = RESULTS_DATA[cohortName];
        if (!cohortData) {
            console.error(`No cohort data found for: ${cohortName}`);
            return;
        }
        
        const taskData = cohortData[taskName];
        if (!taskData) {
            console.error(`No task data found for: ${taskName} in cohort ${cohortName}`);
            return;
        }

        // Show task view containers, hide group container
        document.querySelector('.tabs-container').style.display = 'flex';
        document.querySelector('.tab-content-container').style.display = 'block';
        document.getElementById('group-analysis-container').style.display = 'none';

        // A. Update Header Title & Subtitle
        document.getElementById('current-task-title').textContent = taskLabels[taskName] || taskName;
        
        // B. Update Metadata Container
        const metaContainer = document.getElementById('metadata-container');
        metaContainer.innerHTML = `
            <div class="meta-pill" title="Data Source">
                <i class="fa-solid fa-database"></i>
                <span>Source: <span class="val">${taskData.metadata.data_source || (cohortName.toUpperCase() + ' Cohort')}</span></span>
            </div>
            <div class="meta-pill" title="Analysis Timestamp">
                <i class="fa-solid fa-calendar-day"></i>
                <span>Analyzed: <span class="val">${taskData.metadata.analysis_time || 'N/A'}</span></span>
            </div>
            <div class="meta-pill" title="Computation Wall-time">
                <i class="fa-solid fa-stopwatch"></i>
                <span>Duration: <span class="val">${taskData.metadata.computation_time || 'N/A'}</span></span>
            </div>
        `;

        // C. Update Images with cohort-specific prefixes and folders
        const imgPrefix = `${cohortName}_${taskName}`;
        
        // Overview Tab
        document.getElementById('img-barycenter-carpet').src = `assets/images/${taskName}/${imgPrefix}_barycenter_carpet_plot.png`;
        document.getElementById('img-barycenter-lollipop').src = `assets/images/${taskName}/${imgPrefix}_barycenter_lollipop_plot.png`;
        
        // Wasserstein PGA Tab
        document.getElementById('img-pga-scree').src = `assets/images/${taskName}/${imgPrefix}_pga_scree_plot.png`;
        document.getElementById('img-pga-pc1-geodesic').src = `assets/images/${taskName}/${imgPrefix}_pga_pc1_geodesic.png`;
        document.getElementById('img-pga-pc2-geodesic').src = `assets/images/${taskName}/${imgPrefix}_pga_pc2_geodesic.png`;
        document.getElementById('img-pga-pc1-direction').src = `assets/images/${taskName}/${imgPrefix}_pga_pc1_direction_carpet_plot.png`;
        document.getElementById('img-pga-pc2-direction').src = `assets/images/${taskName}/${imgPrefix}_pga_pc2_direction_carpet_plot.png`;
        
        // 3-Way Interactions Tab
        document.getElementById('img-triads-lollipop').src = `assets/images/${taskName}/${imgPrefix}_coskewness_triads_lollipop_plot.png`;
        document.getElementById('img-triads-distinct-lollipop').src = `assets/images/${taskName}/${imgPrefix}_coskewness_triads_distinct_lollipop_plot.png`;

        // D. Populate Barycenter table
        const barycenterBody = document.getElementById('barycenter-table-body');
        barycenterBody.innerHTML = '';
        
        if (taskData.barycenter_elements && taskData.barycenter_elements.length > 0) {
            taskData.barycenter_elements.forEach((el, index) => {
                const tr = document.createElement('tr');
                const signClass = el.r_val >= 0 ? 'pos' : 'neg';
                const signText = el.r_val >= 0 ? 'Positive' : 'Negative';
                
                tr.innerHTML = `
                    <td>${index + 1}</td>
                    <td><strong>${el.node_a}</strong></td>
                    <td><strong>${el.node_b}</strong></td>
                    <td class="num-col">${el.r_val.toFixed(6)}</td>
                    <td class="num-col">
                        <span class="sign-badge ${signClass}">${signText}</span>
                    </td>
                `;
                barycenterBody.appendChild(tr);
            });
        } else {
            barycenterBody.innerHTML = '<tr><td colspan="5" style="text-align: center;">No barycenter elements found</td></tr>';
        }

        // D2. Populate CP Components (Non-Gaussian Variance Explained)
        const cpContainer = document.getElementById('cp-components-container');
        cpContainer.innerHTML = '';
        
        if (taskData.cp_components && taskData.cp_components.length > 0) {
            taskData.cp_components.forEach(cp => {
                const card = document.createElement('div');
                card.className = 'cp-component-card';
                card.innerHTML = `
                    <div class="cp-component-num">Component ${cp.component}</div>
                    <div class="cp-component-pct">${cp.pct_variance.toFixed(1)}%</div>
                    <div class="cp-component-lambda">&lambda; = ${cp.lambda_val.toFixed(4)}</div>
                `;
                cpContainer.appendChild(card);
            });
        } else {
            cpContainer.innerHTML = '<div style="grid-column: span 5; text-align: center; color: var(--text-muted); padding: 12px;">No CP components data available.</div>';
        }

        // E. Populate Triads (both tables)
        renderTriadsTable();
    }

    // 7. Render Triads Tables with Search/Filtering
    function renderTriadsTable() {
        const cohortData = RESULTS_DATA[currentCohort];
        if (!cohortData) return;
        
        const taskData = cohortData[currentTask];
        if (!taskData) return;

        const overallBody = document.getElementById('overall-triads-table-body');
        const distinctBody = document.getElementById('distinct-triads-table-body');
        const searchMeta = document.getElementById('search-results-meta');

        overallBody.innerHTML = '';
        distinctBody.innerHTML = '';

        // Filter function helper
        const matchesQuery = (triad) => {
            if (!searchQuery) return true;
            return triad.node_a.toLowerCase().includes(searchQuery) ||
                   triad.node_b.toLowerCase().includes(searchQuery) ||
                   triad.node_c.toLowerCase().includes(searchQuery);
        };

        const filteredGeneral = (taskData.general_triads || []).filter(matchesQuery);
        const filteredDistinct = (taskData.distinct_triads || []).filter(matchesQuery);

        // Render Overall/General Triads
        if (filteredGeneral.length > 0) {
            filteredGeneral.forEach(triad => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${triad.rank}</td>
                    <td><strong>${triad.node_a}</strong> - <strong>${triad.node_b}</strong> - <strong>${triad.node_c}</strong></td>
                    <td class="num-col ${triad.m_abc >= 0 ? 'pos-num' : 'neg-num'}">${triad.m_abc.toFixed(6)}</td>
                    <td class="num-col font-bold">${triad.abs_m_abc.toFixed(6)}</td>
                    <td class="num-col font-bold">${triad.pct_variance.toFixed(2)}%</td>
                `;
                overallBody.appendChild(tr);
            });
        } else {
            overallBody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-muted);">No matching interactions</td></tr>';
        }

        // Render Distinct Triads
        if (filteredDistinct.length > 0) {
            filteredDistinct.forEach(triad => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${triad.rank}</td>
                    <td><strong>${triad.node_a}</strong> - <strong>${triad.node_b}</strong> - <strong>${triad.node_c}</strong></td>
                    <td class="num-col ${triad.m_abc >= 0 ? 'pos-num' : 'neg-num'}">${triad.m_abc.toFixed(6)}</td>
                    <td class="num-col font-bold">${triad.abs_m_abc.toFixed(6)}</td>
                    <td class="num-col font-bold">${triad.pct_variance.toFixed(2)}%</td>
                `;
                distinctBody.appendChild(tr);
            });
        } else {
            distinctBody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-muted);">No matching interactions</td></tr>';
        }

        // Update search metadata description
        if (searchQuery) {
            searchMeta.textContent = `Found ${filteredGeneral.length} overall and ${filteredDistinct.length} distinct matches.`;
            searchMeta.style.color = 'var(--accent-cyan)';
        } else {
            const totalGen = (taskData.general_triads || []).length;
            const totalDist = (taskData.distinct_triads || []).length;
            searchMeta.textContent = `Showing top ${totalGen} overall and top ${totalDist} distinct interactions.`;
            searchMeta.style.color = 'var(--text-secondary)';
        }
    }

    // Group analysis loading function
    function loadGroupData(cohortName) {
        const cohortData = RESULTS_DATA[cohortName];
        if (!cohortData || !cohortData.group) {
            console.error(`No group data found for cohort: ${cohortName}`);
            return;
        }
        
        const groupData = cohortData.group;

        // Hide task view containers, show group container
        document.querySelector('.tabs-container').style.display = 'none';
        document.querySelector('.tab-content-container').style.display = 'none';
        document.getElementById('group-analysis-container').style.display = 'block';

        // Update Header Title & Subtitle
        document.getElementById('current-task-title').textContent = `${cohortName.toUpperCase()} Task Differentiation`;
        document.querySelector('.subtitle').textContent = `F-statistics comparing functional connectivity across task conditions`;
        
        // Update Metadata Container
        const metaContainer = document.getElementById('metadata-container');
        metaContainer.innerHTML = `
            <div class="meta-pill" title="Data Source">
                <i class="fa-solid fa-database"></i>
                <span>Source: <span class="val">${groupData.metadata.data_source || (cohortName.toUpperCase() + ' Cohort')}</span></span>
            </div>
            <div class="meta-pill" title="Analysis Timestamp">
                <i class="fa-solid fa-calendar-day"></i>
                <span>Analyzed: <span class="val">${groupData.metadata.analysis_time || 'N/A'}</span></span>
            </div>
            <div class="meta-pill" title="Degrees of Freedom (Between / Within)">
                <i class="fa-solid fa-calculator"></i>
                <span>DF: <span class="val">${groupData.metadata.df_between} / ${groupData.metadata.df_within}</span></span>
            </div>
        `;

        // Update Carpet Plot Image
        document.getElementById('img-group-carpet').src = `assets/images/group/${cohortName}_task_separation_f_values_carpet_plot.png`;

        // Populate Top 10 Table
        const groupTableBody = document.getElementById('group-table-body');
        groupTableBody.innerHTML = '';
        
        if (groupData.top_connections && groupData.top_connections.length > 0) {
            groupData.top_connections.forEach((conn) => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${conn.rank}</td>
                    <td><strong>${conn.node_a}</strong> - <strong>${conn.node_b}</strong></td>
                    <td class="num-col font-bold">${conn.f_val.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</td>
                    <td class="num-col">${conn.p_val}</td>
                `;
                groupTableBody.appendChild(tr);
            });
            
            // Populate Top 5 Distribution Plots Grid
            const gridEl = document.getElementById('group-dist-plots-grid');
            gridEl.innerHTML = '';
            
            const top5 = groupData.top_connections.slice(0, 5);
            top5.forEach((conn, index) => {
                const card = document.createElement('div');
                card.className = 'card glass-card';
                if (index === 4) {
                    card.style.gridColumn = 'span 2'; // Center/span the 5th card for visual balance
                }
                
                const rankStr = String(conn.rank).padStart(2, '0');
                const connName = `${conn.node_a}_${conn.node_b}`;
                const imgName = `${cohortName}_sep_plot_rank${rankStr}_${connName}.png`;
                const fValStr = conn.f_val.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2});
                
                card.innerHTML = `
                    <div class="card-header">
                        <h3 class="card-title">Rank ${conn.rank}: ${conn.connection}</h3>
                        <p class="card-subtitle">F-value = ${fValStr} (p-value: ${conn.p_val})</p>
                    </div>
                    <div class="card-body plot-body flex-center" style="padding: 16px 0;">
                        <div class="img-container" style="max-height: 400px; width: 100%; display: flex; justify-content: center;">
                            <img src="assets/images/group/${imgName}" alt="Distribution Plot for ${conn.connection}" style="max-height: 380px; width: auto; object-fit: contain;">
                        </div>
                    </div>
                `;
                gridEl.appendChild(card);
            });
        } else {
            groupTableBody.innerHTML = '<tr><td colspan="4" style="text-align: center;">No task separation results found</td></tr>';
        }
    }

    // Load initial task
    loadTaskData(currentCohort, currentTask);
});
