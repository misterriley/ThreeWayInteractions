function analyze_task_separation(dataset)
% ANALYZE_TASK_SEPARATION Performs task separation analysis on Bures-Wasserstein bootstrap barycenters.
%
% Inputs:
%   dataset : 'hcp' or 'imagen' (default: 'hcp')

    if nargin < 1 || isempty(dataset)
        dataset = 'hcp';
    end
    
    fprintf('============================================================\n');
    fprintf('STARTING TASK SEPARATION ANALYSIS FOR DATASET: %s\n', upper(dataset));
    fprintf('============================================================\n');

    % Define tasks based on dataset
    if strcmp(dataset, 'imagen')
        tasks = {'MID', 'SST'};
    else
        tasks = {'emotion', 'gambling', 'language', 'motor', 'relational', 'rest', 'rest2', 'social', 'wm'};
    end
    
    k = length(tasks);
    
    % Define output directory
    output_dir = fullfile(pwd, 'outputs', dataset, 'group');
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    
    % --- Step 1: Load all bootstrap barycenters ---
    fprintf('Loading bootstrap barycenters for all tasks...\n');
    all_boot_barycenters = [];
    unique_networks = {};
    
    for t = 1:k
        task_name = tasks{t};
        mat_file = fullfile(pwd, 'outputs', dataset, task_name, sprintf('%s_%s_normative_results.mat', dataset, task_name));
        if ~exist(mat_file, 'file')
            error('Normative results file not found for task %s at:\n  %s\nRun recompute_barycenters first!', task_name, mat_file);
        end
        
        data = load(mat_file, 'boot_barycenters', 'unique_networks');
        
        if t == 1
            unique_networks = string(data.unique_networks);
            n_networks = length(unique_networks);
            n_boot = size(data.boot_barycenters, 3);
            all_boot_barycenters = zeros(n_networks, n_networks, n_boot, k);
        else
            if ~isequal(string(data.unique_networks), unique_networks)
                error('Network labels do not match between tasks!');
            end
        end
        all_boot_barycenters(:, :, :, t) = data.boot_barycenters;
    end
    
    n_edges = n_networks * (n_networks - 1) / 2;
    fprintf('Loaded %d tasks, %d bootstrap iterations, %d canonical networks.\n', k, n_boot, n_networks);
    fprintf('Calculating F-statistics for each of the %d unique edges...\n', n_edges);
    
    % --- Step 2: Compute one-way ANOVA F-statistics for each edge ---
    edge_list = struct('r', {}, 'c', {}, 'net1', {}, 'net2', {}, 'F', {}, 'p_val', {}, 'means', {}, 'stds', {});
    edge_idx = 1;
    
    % Degrees of freedom
    df_between = k - 1;
    df_within = (n_boot * k) - k;
    
    for r = 1:n_networks
        for c = r+1:n_networks
            % Extract bootstrap values for this edge across all tasks
            % Size: [n_boot, k]
            vals = squeeze(all_boot_barycenters(r, c, :, :));
            
            % Compute means and standard deviations per task
            task_means = mean(vals, 1);
            task_stds = std(vals, 0, 1);
            
            % Grand mean
            grand_mean = mean(vals, 'all');
            
            % Sum of squares between
            ss_between = sum(n_boot * (task_means - grand_mean).^2);
            
            % Sum of squares within
            ss_within = sum((vals - task_means).^2, 'all');
            
            % Mean squares
            ms_between = ss_between / df_between;
            ms_within = ss_within / df_within;
            
            % F-statistic
            F_val = ms_between / ms_within;
            
            % P-value using incomplete beta function (fully self-contained)
            x_val = (df_between * F_val) / (df_between * F_val + df_within);
            p_val = 1 - betainc(x_val, df_between / 2, df_within / 2);
            
            % Save to struct
            edge_list(edge_idx).r = r;
            edge_list(edge_idx).c = c;
            edge_list(edge_idx).net1 = unique_networks(r);
            edge_list(edge_idx).net2 = unique_networks(c);
            edge_list(edge_idx).F = F_val;
            edge_list(edge_idx).p_val = p_val;
            edge_list(edge_idx).means = task_means;
            edge_list(edge_idx).stds = task_stds;
            
            edge_idx = edge_idx + 1;
        end
    end
    
    % Sort edges by F-statistic in descending order
    [~, sort_idx] = sort([edge_list.F], 'descend');
    edge_list_sorted = edge_list(sort_idx);
    
    % Build F-statistic matrix
    F_matrix = zeros(n_networks, n_networks);
    for e = 1:length(edge_list_sorted)
        item = edge_list_sorted(e);
        F_matrix(item.r, item.c) = item.F;
        F_matrix(item.c, item.r) = item.F;
    end
    
    % --- Step 3: Generate Heatmap on a Carpet Plot ---
    fprintf('Generating F-values carpet plot...\n');
    
    % Custom sequential colormap: light grey-blue to deep royal purple
    r_cmap = linspace(0.96, 0.3, 256)';
    g_cmap = linspace(0.96, 0.0, 256)';
    b_cmap = linspace(0.98, 0.5, 256)';
    F_cmap = [r_cmap, g_cmap, b_cmap];
    
    carpet_plot_filename = fullfile(output_dir, sprintf('%s_task_separation_f_values_carpet_plot.png', dataset));
    
    % We use plot_masked_carpet helper function
    % We pass highlight_top_10 = true to highlight the top 10 task separating connections
    max_F = max(F_matrix, [], 'all');
    plot_masked_carpet(F_matrix, unique_networks, ...
        sprintf('%s: Task Separation F-Values (Top 10 Highlighted)', upper(dataset)), ...
        carpet_plot_filename, F_cmap, [0 max_F], true);
    
    % --- Step 4: Write Text Report ---
    fprintf('Writing text report...\n');
    report_filename = fullfile(output_dir, sprintf('%s_task_separation_report.txt', dataset));
    
    fid = fopen(report_filename, 'w');
    if fid == -1
        error('Cannot open report file for writing: %s', report_filename);
    end
    
    fprintf(fid, '============================================================\n');
    fprintf(fid, 'TASK SEPARATION ANALYSIS REPORT: %s\n', upper(dataset));
    fprintf(fid, '============================================================\n\n');
    fprintf(fid, 'Data Source:       %s dataset\n', dataset);
    fprintf(fid, 'Analysis Time:     %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Number of Tasks:   %d\n', k);
    fprintf(fid, 'Tasks Compared:    %s\n', strjoin(tasks, ', '));
    fprintf(fid, 'Bootstraps/Task:   %d\n', n_boot);
    fprintf(fid, 'DF (Between/Within): %d / %d\n\n', df_between, df_within);
    
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, 'TOP 10 FC CONNECTIONS SEPARATING TASK CONDITIONS:\n');
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, '%-4s %-25s %-12s %-12s %-12s\n', 'Rank', 'Connection', 'F-value', 'df_between', 'p-value');
    fprintf(fid, '------------------------------------------------------------\n');
    
    for rank = 1:10
        item = edge_list_sorted(rank);
        conn_str = sprintf('%s - %s', item.net1, item.net2);
        if item.p_val < 0.0001
            p_str = '< 0.0001';
        else
            p_str = sprintf('%.4f', item.p_val);
        end
        fprintf(fid, '%-4d %-25s %-12.2f %-12d %-12s\n', rank, conn_str, item.F, df_between, p_str);
    end
    fprintf(fid, '------------------------------------------------------------\n\n');
    
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, 'TASK-SPECIFIC BREAKDOWN (MEAN AND STD OF BOOTSTRAP VALUES):\n');
    fprintf(fid, '------------------------------------------------------------\n');
    
    for rank = 1:10
        item = edge_list_sorted(rank);
        conn_str = sprintf('%s - %s', item.net1, item.net2);
        fprintf(fid, 'Rank %d: %s (F = %.2f, p = %s)\n', rank, conn_str, item.F, ...
            iff(item.p_val < 0.0001, '< 0.0001', sprintf('%.4f', item.p_val)));
        
        for t = 1:k
            fprintf(fid, '  - %-12s: mean = % 6.4f, std = %.4f\n', tasks{t}, item.means(t), item.stds(t));
        end
        fprintf(fid, '\n');
    end
    
    fclose(fid);
    fprintf('Report saved to %s\n', report_filename);
    
    % --- Step 5: Generate Distribution Plots for Top 10 Edges ---
    fprintf('Generating distribution plots for top 10 edges...\n');
    
    % Beautiful color palette (up to 10 tasks)
    colors = [
        0.1216, 0.4667, 0.7059; % Blue
        1.0000, 0.4980, 0.0549; % Orange
        0.1725, 0.6275, 0.1725; % Green
        0.8392, 0.1529, 0.1569; % Red
        0.5804, 0.4039, 0.7412; % Purple
        0.5490, 0.3373, 0.2941; % Brown
        0.8902, 0.4667, 0.7608; % Pink
        0.4980, 0.4980, 0.4980; % Grey
        0.7373, 0.7412, 0.1333; % Olive
        0.0902, 0.7451, 0.8118  % Cyan
    ];

    for rank = 1:10
        item = edge_list_sorted(rank);
        
        % Extract values for this edge
        % Size: [n_boot, k]
        vals = squeeze(all_boot_barycenters(item.r, item.c, :, :));
        
        x_grid = linspace(-1, 1, 500);
        
        % Calculate Normal PDFs
        pdfs = zeros(k, length(x_grid));
        for t = 1:k
            mu = item.means(t);
            sigma = item.stds(t);
            if sigma == 0, sigma = 1e-9; end
            pdfs(t, :) = (1 / (sigma * sqrt(2*pi))) * exp(-0.5 * ((x_grid - mu)/sigma).^2);
        end
        
        max_pdf = max(pdfs(:));
        if isempty(max_pdf) || max_pdf == 0, max_pdf = 1.0; end
        
        % Setup Figure
        fig = figure('Visible', 'off');
        ax = gca;
        hold(ax, 'on');
        
        % 1. Plot the rug plot (dots with jitter at the bottom)
        y_dots_offset = -0.05 * max_pdf;
        jitter_range = 0.03 * max_pdf;
        
        for t = 1:k
            t_vals = vals(:, t);
            % Jittered y positions
            t_y = y_dots_offset + (rand(size(t_vals)) - 0.5) * jitter_range;
            
            scatter(ax, t_vals, t_y, 20, colors(t, :), 'filled', ...
                'MarkerFaceAlpha', 0.5, 'HandleVisibility', 'off');
        end
        
        % 2. Plot normal curves and shaded areas, sorted by task mean (ascending)
        [~, mean_sort_idx] = sort(item.means);
        for i = 1:k
            t = mean_sort_idx(i);
            % Shaded area
            fill(ax, [x_grid, fliplr(x_grid)], [pdfs(t, :), zeros(size(x_grid))], ...
                colors(t, :), 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
            
            % Density line
            plot(ax, x_grid, pdfs(t, :), 'Color', colors(t, :), 'LineWidth', 2.0, ...
                'DisplayName', tasks{t});
        end
        
        % 3. Plot a horizontal line at y=0 as baseline
        plot(ax, [-1, 1], [0 0], 'k-', 'LineWidth', 1.0, 'HandleVisibility', 'off');
        
        % Style the plot
        xlabel(ax, 'Functional Connectivity (r)', 'FontSize', 11);
        ylabel(ax, 'Probability Density', 'FontSize', 11);
        xlim(ax, [-1, 1]);
        ylim(ax, [-0.1 * max_pdf, 1.2 * max_pdf]);
        
        title_str = sprintf('Rank %d: %s - %s (F = %.2f, p = %s)', rank, item.net1, item.net2, item.F, ...
            iff(item.p_val < 0.0001, '< 0.0001', sprintf('%.4f', item.p_val)));
        title(ax, title_str, 'Interpreter', 'none', 'FontSize', 12, 'FontWeight', 'bold');
        
        legend(ax, 'Location', 'northeast', 'Interpreter', 'none', 'FontSize', 9);
        grid(ax, 'on');
        set(ax, 'Box', 'on', 'TickDir', 'out', 'LineWidth', 1, 'FontSize', 9);
        
        % Save Plot
        conn_name = sprintf('%s_%s', item.net1, item.net2);
        plot_filename = fullfile(output_dir, sprintf('%s_sep_plot_rank%02d_%s.png', dataset, rank, conn_name));
        exportgraphics(fig, plot_filename, 'Resolution', 300);
        close(fig);
    end
    
    fprintf('All 10 distribution plots generated.\n');
    fprintf('Overarching task separation analysis for %s completed!\n\n', upper(dataset));
end

function val = iff(cond, true_val, false_val)
    if cond
        val = true_val;
    else
        val = false_val;
    end
end
