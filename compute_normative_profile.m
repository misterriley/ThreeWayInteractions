function compute_normative_profile(dataset, task_name, recompute_fc_matrices, recompute_barycenter, recompute_coskewness, n_lollipops)
% COMPUTE_NORMATIVE_PROFILE Loads timeseries, groups by networks, computes FC matrices,
% Wasserstein barycenters, and coskewness tensors for a given dataset and task.
%
% Usage:
%   compute_normative_profile(dataset, task_name)
%   compute_normative_profile(dataset, task_name, recompute_fc_matrices, recompute_barycenter, recompute_coskewness)
%   compute_normative_profile(dataset, task_name, recompute_fc_matrices, recompute_barycenter, recompute_coskewness, n_lollipops)

% Add Common directory to path so we can use load_timeseries
addpath('../Common');

% --- Default Arguments ---
if nargin < 1 || isempty(dataset)
    dataset = 'hcp';
end
if nargin < 2 || isempty(task_name)
    task_name = 'wm';
end
if nargin < 3 || isempty(recompute_fc_matrices)
    recompute_fc_matrices = false;
end
if nargin < 4 || isempty(recompute_barycenter)
    recompute_barycenter = true;
end
if nargin < 5 || isempty(recompute_coskewness)
    recompute_coskewness = false;
end
if nargin < 6 || isempty(n_lollipops)
    n_lollipops = 5;
end

% Parameters
n_rois = 268;

fprintf('\n============================================================\n');
fprintf('STARTING PROCESSING PIPELINE FOR:\n');
fprintf('  Dataset: %s\n', upper(dataset));
fprintf('  Task:    %s\n', upper(task_name));
fprintf('============================================================\n');

% Define output directory and filenames dynamically based on dataset and task_name
output_dir = fullfile(pwd, 'outputs', dataset, task_name);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
results_filename = fullfile(output_dir, sprintf('%s_%s_normative_results.mat', dataset, task_name));

has_saved_results = false;
if exist(results_filename, 'file')
    has_saved_results = true;
end

% If results file does not exist, we must force recomputation of all parts
if ~has_saved_results
    fprintf('No existing results file found. Forcing recomputation of all parts.\n');
    recompute_fc_matrices = true;
    recompute_barycenter  = true;
    recompute_coskewness  = true;
else
    % Load existing results as a baseline
    fprintf('Loading existing results from %s...\n', results_filename);
    load(results_filename);
end

% Determine if we need to load timeseries
need_timeseries = recompute_fc_matrices || recompute_coskewness;

if need_timeseries
    fprintf('\nLoading timeseries for %s dataset, task %s, %d ROIs...\n', dataset, task_name, n_rois);

    % Load timeseries. We pass check_var_exists = false to load all subjects
    % who have timeseries files, setting their outcomes to NaN if no behavioral
    % score is found (e.g. for motor or rest tasks).
    [valid_outcomes, valid_subject_ids, valid_timeseries, out_var_name] = ...
        load_timeseries(dataset, task_name, n_rois, '', false);

    fprintf('\nTimeseries loading complete.\n');
    fprintf('Loaded Variable Name: %s\n', out_var_name);
    fprintf('Number of valid subjects: %d\n', length(valid_subject_ids));

    % Normalize timeseries per node and transpose to 268 x T
    fprintf('Normalizing timeseries per node and transposing to %d x T...\n', n_rois);
    n_subs = length(valid_timeseries);
    for s = 1:n_subs
        ts = valid_timeseries{s}; % Original Size: T x 268
        
        % Column-wise z-scoring: normalize each node (column) to mean 0, std 1
        node_means = mean(ts, 1);
        node_stds = std(ts, 0, 1);
        
        % Avoid division by zero if standard deviation is zero
        node_stds(node_stds == 0) = 1;
        
        ts_norm = (ts - node_means) ./ node_stds;
        
        % Transpose to 268 x T
        valid_timeseries{s} = ts_norm';
    end

    if ~isempty(valid_timeseries)
        fprintf('First subject normalized timeseries size: %s\n', mat2str(size(valid_timeseries{1})));
    end

    % --- Group nodes by canonical networks using roimap.csv ---
    fprintf('\nGrouping nodes by canonical networks...\n');
    roimap_path = fullfile(pwd, '..', '..', 'Data', 'roimap.csv');
    if ~exist(roimap_path, 'file')
        error('roimap.csv not found at %s', roimap_path);
    end

    roimap = readtable(roimap_path, 'VariableNamingRule', 'preserve');

    % Map node index (1 to 268) to its canonical network label using the 'oldroi' column
    node_networks = strings(n_rois, 1);
    for i = 1:n_rois
        idx = find(roimap.oldroi == i);
        if isempty(idx)
            error('Could not find ROI %d in the oldroi column of roimap.csv', i);
        end
        node_networks(i) = string(roimap.label{idx});
    end

    % Get unique network labels ordered by category (1 to 10)
    [~, sort_idx] = sort(roimap.category);
    sorted_labels = string(roimap.label(sort_idx));
    unique_networks = unique(sorted_labels, 'stable');
    n_networks = length(unique_networks);

    fprintf('Found %d canonical networks:\n', n_networks);
    for n = 1:n_networks
        n_nodes = sum(node_networks == unique_networks(n));
        fprintf('  Network %d (%s): %d nodes\n', n, unique_networks(n), n_nodes);
    end

    % Compute network-averaged timeseries for each subject
    fprintf('\nComputing network-averaged timeseries (size %d x T) for each subject...\n', n_networks);
    network_timeseries = cell(n_subs, 1);
    for s = 1:n_subs
        ts = valid_timeseries{s}; % Size: 268 x T
        T = size(ts, 2);
        net_ts = zeros(n_networks, T);
        for n = 1:n_networks
            % Find node indices belonging to network n
            net_nodes = find(node_networks == unique_networks(n));
            % Average timeseries across nodes in this network
            net_ts(n, :) = mean(ts(net_nodes, :), 1);
        end
        network_timeseries{s} = net_ts;
    end

    if ~isempty(network_timeseries)
        fprintf('First subject network-averaged timeseries size: %s\n', mat2str(size(network_timeseries{1})));
    end
else
    fprintf('\nSkipping timeseries loading and preprocessing (Option flags do not require it).\n');
    n_networks = length(unique_networks);
    n_subs = size(fc_matrices, 3);
end

% --- Step 1: Compute individual 10x10 FC matrices ---
if recompute_fc_matrices
    fprintf('\nComputing functional connectivity (FC) matrices for each person...\n');
    fc_matrices = zeros(n_networks, n_networks, n_subs);
    for s = 1:n_subs
        % Pearson correlation of the 10 x T matrix (transposed to T x 10 for corr)
        fc_matrices(:,:,s) = corr(network_timeseries{s}');
    end
    fprintf('Individual FC matrices computed. Size: %s\n', mat2str(size(fc_matrices)));
else
    fprintf('\nSkipping FC matrix calculation (using previously saved results).\n');
end

% --- Step 2: Compute Wasserstein barycenter and arithmetic mean of the FC matrices ---
if recompute_barycenter
    fprintf('\nComputing Wasserstein barycenter and arithmetic mean of FC matrices...\n');
    
    % Compute arithmetic mean of FC matrices
    arithmetic_mean = mean(fc_matrices, 3);
    
    % Diverging blue-white-red colormap
    n_colors = 256;
    half = n_colors / 2;
    r1 = linspace(0, 1, half)';
    g1 = linspace(0, 1, half)';
    b1 = ones(half, 1);
    r2 = ones(half, 1);
    g2 = linspace(1, 0, half)';
    b2 = linspace(1, 0, half)';
    bwr_cmap = [r1, g1, b1; r2, g2, b2];
    
    % Compute Bures-Wasserstein barycenter using helper function
    max_iter = 100;
    tol = 1e-6;
    [barycenter, converged, iter, diff] = compute_wasserstein_barycenter(fc_matrices, max_iter, tol, arithmetic_mean);
    if converged
        fprintf('Bures-Wasserstein barycenter converged in %d iterations (diff = %e)\n', iter, diff);
    else
        warning('Bures-Wasserstein barycenter did not converge within %d iterations', max_iter);
    end

    % --- Normalize Wasserstein barycenter to be a true correlation matrix ---
    fprintf('Normalizing Wasserstein barycenter to a correlation matrix...\n');
    D_bary = diag(barycenter);
    barycenter_normalized = barycenter ./ sqrt(D_bary * D_bary');
    
    % --- Run bootstrap resampling on FC matrices to identify stable barycenter elements ---
    fprintf('Running bootstrap analysis (100 iterations) to find stable barycenter elements...\n');
    n_boot = 100;
    boot_barycenters = zeros(n_networks, n_networks, n_boot);
    
    for b = 1:n_boot
        % Resample subject indices with replacement
        boot_idx = randi(n_subs, n_subs, 1);
        fc_boot = fc_matrices(:, :, boot_idx);
        
        % Initialize S_boot with the arithmetic mean of resampled FCs
        S_boot = mean(fc_boot, 3);
        S_boot = S_boot + 1e-9 * eye(n_networks);
        
        % Compute Bures-Wasserstein barycenter for this bootstrap sample using helper function
        S_init_boot = mean(fc_boot, 3);
        [S_boot, ~] = compute_wasserstein_barycenter(fc_boot, 15, 1e-4, S_init_boot);
        
        % Normalize bootstrap barycenter to be a correlation matrix
        D_b = diag(S_boot);
        boot_barycenters(:, :, b) = S_boot ./ sqrt(D_b * D_b');
    end
    
    % Compute standard deviation of loadings across bootstrap runs
    bary_boot_std = std(boot_barycenters, 0, 3);
    
    % Compute Bootstrap Ratio (Z-score)
    bary_bootstrap_ratios = barycenter_normalized ./ (bary_boot_std + 1e-9);
    
    % Set dynamic z-threshold (Bonferroni FWER = 0.05 for 45 unique off-diagonal comparisons)
    n_off_diagonal = n_networks * (n_networks - 1) / 2;
    alpha_bary = 0.05 / n_off_diagonal;
    bary_z_threshold = sqrt(2) * erfinv(1 - alpha_bary);
    
    fprintf('Barycenter thresholding (FWER = 0.05, %d tests): Z-threshold = %.4f\n', n_off_diagonal, bary_z_threshold);
    
    % Threshold barycenter for display
    barycenter_corrected = barycenter_normalized;
    for j = 1:n_networks
        for k = j+1:n_networks
            if abs(bary_bootstrap_ratios(j, k)) < bary_z_threshold
                barycenter_corrected(j, k) = 0;
                barycenter_corrected(k, j) = 0;
            end
        end
    end
    
    % --- Display the bootstrap-corrected barycenter using a carpet/matrix plot ---
    bary_plot_filename = fullfile(output_dir, sprintf('%s_%s_barycenter_carpet_plot.png', dataset, task_name));
    plot_masked_carpet(barycenter_corrected, unique_networks, ...
        sprintf('%s %s: Wasserstein Barycenter (Bootstrap-Corrected)', upper(dataset), upper(task_name)), ...
        bary_plot_filename, bwr_cmap, [-1 1], true);
    fprintf('Barycenter carpet plot saved to %s\n', bary_plot_filename);

    % --- Step 2a-2: Generate Lollipop Plot of Top Highlighted Barycenter Connections ---
    fprintf('Generating lollipop plot of top %d highlighted Bures-Wasserstein barycenter connections...\n', n_lollipops);
    
    % Extract unique off-diagonal entries from the upper triangle
    abs_bary = abs(barycenter_normalized);
    upper_tri_mask = triu(true(size(abs_bary)), 1);
    upper_abs = abs_bary;
    upper_abs(~upper_tri_mask) = -inf;
    
    [~, sort_idx] = sort(upper_abs(:), 'descend');
    n_plot = min(n_lollipops, sum(upper_tri_mask(:)));
    top_idx = sort_idx(1:n_plot);
    [r_coords, c_coords] = ind2sub(size(barycenter_normalized), top_idx);
    
    top_vals = zeros(n_plot, 1);
    lollipop_labels = cell(n_plot, 1);
    for k = 1:n_plot
        top_vals(k) = barycenter_normalized(r_coords(k), c_coords(k));
        lollipop_labels{k} = sprintf('%s - %s', unique_networks(r_coords(k)), unique_networks(c_coords(k)));
    end
    
    lollipop_plot_filename = fullfile(output_dir, sprintf('%s_%s_barycenter_lollipop_plot.png', dataset, task_name));
    plot_lollipop(top_vals, lollipop_labels, ...
        sprintf('%s %s: Top %d Highlighted Barycenter Connections', upper(dataset), upper(task_name), n_plot), ...
        'Correlation Value (r)', lollipop_plot_filename, [-1, 1]);
    fprintf('Barycenter lollipop plot saved to %s\n', lollipop_plot_filename);

    % --- Step 2b: Compute the difference matrix for calculations ---
    diff_matrix = arithmetic_mean - barycenter_normalized;
    max_diff = max(abs(diff_matrix), [], 'all');
    fprintf('Maximum difference between Arithmetic Mean and Normalized Barycenter: %f\n', max_diff);
else
    fprintf('\nSkipping barycenter calculation and plotting (using previously saved results).\n');
end

% --- Step 3: Compute third-order coskewness tensors for each person ---
if recompute_coskewness
    fprintf('\nComputing third-order coskewness tensors for each person...\n');
    coskewness_tensors = zeros(n_networks, n_networks, n_networks, n_subs);

    for s = 1:n_subs
        % Get the 10 x T network timeseries for this subject
        Y_s = network_timeseries{s};
        T = size(Y_s, 2);
        
        % Normalize each network's timeseries to have mean 0, std 1
        Y_mean = mean(Y_s, 2);
        Y_std = std(Y_s, 0, 2);
        Y_std(Y_std == 0) = 1; % Avoid division by zero
        Y_s_norm = (Y_s - Y_mean) ./ Y_std;
        
        % Compute third-order tensor (10 x 10 x 10)
        T_s = zeros(n_networks, n_networks, n_networks);
        for i = 1:n_networks
            % Vectorized slice calculation: (row i .* Y) * Y^T / T
            T_s(i, :, :) = ((Y_s_norm(i, :) .* Y_s_norm) * Y_s_norm') / T;
        end
        coskewness_tensors(:, :, :, s) = T_s;
    end
    fprintf('Coskewness tensors computed. Size: %s\n', mat2str(size(coskewness_tensors)));
else
    fprintf('\nSkipping coskewness tensor calculation (using previously saved results).\n');
end

% --- Save results to MAT-file ---
fprintf('\nSaving results to %s...\n', results_filename);
save(results_filename, 'valid_subject_ids', 'valid_outcomes', 'fc_matrices', ...
     'barycenter', 'barycenter_normalized', 'barycenter_corrected', 'bary_bootstrap_ratios', ...
     'bary_z_threshold', 'arithmetic_mean', 'coskewness_tensors', 'unique_networks', 'out_var_name', ...
     'boot_barycenters', '-v7.3');
fprintf('All processing completed successfully.\n');
end
