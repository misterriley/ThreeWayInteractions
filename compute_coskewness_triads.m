function compute_coskewness_triads(dataset, task_name, R, n_lollipops)
% COMPUTE_COSKEWNESS_TRIADS Performs 4D symmetric CP tensor decomposition on
% subject coskewness tensors, reconstructs the group target tensor, contracts
% it with the Wasserstein precision matrix, and ranks unique triads.
%
% Usage:
%   compute_coskewness_triads(dataset, task_name)
%   compute_coskewness_triads(dataset, task_name, R)
%   compute_coskewness_triads(dataset, task_name, R, n_lollipops)

if nargin < 1 || isempty(dataset)
    dataset = 'hcp';
end
if nargin < 2 || isempty(task_name)
    task_name = 'emotion';
end
if nargin < 3 || isempty(R)
    R = 5;
end
if nargin < 4 || isempty(n_lollipops)
    n_lollipops = 5;
end
t_start = tic;

fprintf('\n------------------------------------------------------------\n');
fprintf('STARTING COSKEWNESS TRIAD ANALYSIS FOR:\n');
fprintf('  Dataset: %s\n', upper(dataset));
fprintf('  Task:    %s\n', upper(task_name));
fprintf('  Rank R:  %d\n', R);
fprintf('------------------------------------------------------------\n');

output_dir = fullfile(pwd, 'outputs', dataset, task_name);
results_filename = fullfile(output_dir, sprintf('%s_%s_normative_results.mat', dataset, task_name));

if ~exist(results_filename, 'file')
    error('Normative results file %s does not exist. Run compute_normative_profile first.', results_filename);
end

% Load results
fprintf('Loading normative results from %s...\n', results_filename);
res = load(results_filename);

if ~isfield(res, 'barycenter_normalized') || ~isfield(res, 'coskewness_tensors') || ~isfield(res, 'unique_networks')
    error('Missing required variables (barycenter_normalized, coskewness_tensors, unique_networks) in %s', results_filename);
end

barycenter = res.barycenter_normalized;
coskewness_tensors = res.coskewness_tensors;
unique_networks = res.unique_networks;

% Step 1: Compute Precision Matrix
fprintf('Computing precision matrix Theta = inv(barycenter)...\n');
Theta = inv(barycenter);

% Step 2 & 3: Run Group-Level Symmetric 4D CP Decomposition
[n_networks, ~, ~, n_subs] = size(coskewness_tensors);
fprintf('Running 4D symmetric CP decomposition on %dx%dx%dx%d tensor...\n', ...
    n_networks, n_networks, n_networks, n_subs);

X_flat = reshape(coskewness_tensors, n_networks^3, n_subs);

V = zeros(n_networks, R);
W = zeros(n_subs, R);
lambda = zeros(R, 1);

% Fix seed for reproducibility
rng(42);

T_res = X_flat;
max_iter = 200;
tol = 1e-6;

for r = 1:R
    fprintf('  Extracting component %d/%d...\n', r, R);
    vr = randn(n_networks, 1);
    vr = vr / norm(vr);
    wr = randn(n_subs, 1);
    wr = wr / norm(wr);
    
    for iter = 1:max_iter
        vr_old = vr;
        
        % Update wr (subject loadings)
        v_outer = reshape(vr * reshape(vr * vr', 1, []), n_networks^3, 1);
        wr = T_res' * v_outer;
        norm_wr = norm(wr);
        if norm_wr > 1e-9
            wr = wr / norm_wr;
        end
        
        % Update vr (spatial loadings)
        T_3d = reshape(T_res * wr, n_networks, n_networks, n_networks);
        for pow_iter = 1:10
            vr_new = zeros(n_networks, 1);
            for i = 1:n_networks
                vr_new(i) = vr' * squeeze(T_3d(i, :, :)) * vr;
            end
            norm_vr = norm(vr_new);
            if norm_vr > 1e-9
                vr = vr_new / norm_vr;
            end
        end
        
        % Check convergence
        if norm(vr - vr_old) < tol
            break;
        end
    end
    
    % Compute signed scale
    v_outer = reshape(vr * reshape(vr * vr', 1, []), n_networks^3, 1);
    lambda_r = wr' * T_res' * v_outer;
    
    % Force positive lambda by flipping vr if negative
    if lambda_r < 0
        vr = -vr;
        lambda_r = -lambda_r;
    end
    
    V(:, r) = vr;
    W(:, r) = wr;
    lambda(r) = lambda_r;
    
    % Deflate residual
    v_outer = reshape(vr * reshape(vr * vr', 1, []), n_networks^3, 1);
    T_res = T_res - lambda_r * v_outer * wr';
end

% Sort components by singular value
[lambda, sort_idx] = sort(lambda, 'descend');
V = V(:, sort_idx);
W = W(:, sort_idx);

% Calculate percent variance explained for each CP component
cp_var_explained = (lambda.^2) / sum(lambda.^2) * 100;

% Compile the population target tensor W
fprintf('Compiling reconstructed population tensor W...\n');
W_tensor = zeros(n_networks, n_networks, n_networks);
for r = 1:R
    vr = V(:, r);
    W_tensor = W_tensor + lambda(r) * reshape(vr * reshape(vr * vr', 1, []), n_networks, n_networks, n_networks);
end

% Step 4: Symmetrical Slicing Loop & Localized Tensor Contraction
fprintf('Computing Adjusted Triad Index (M_abc) for 220 unique triads...\n');
n_triads = n_networks * (n_networks + 1) * (n_networks + 2) / 6;
triad_results = zeros(n_triads, 5); % [a, b, c, M_abc, Abs_M_abc]

idx_triad = 1;
for a = 1:n_networks
    for b = a:n_networks
        for c = b:n_networks
            Theta_a = Theta(:, a);
            Theta_b = Theta(:, b);
            Theta_c = Theta(:, c);
            
            % 1. Full tensor contraction (explicit)
            M_val_explicit = sum(sum(sum(W_tensor .* ...
                reshape(Theta_a, [n_networks, 1, 1]) .* ...
                reshape(Theta_b, [1, n_networks, 1]) .* ...
                reshape(Theta_c, [1, 1, n_networks]))));
            
            % 2. Fast vectorized contraction (reconstruction shortcut)
            M_val_fast = 0;
            for r = 1:R
                vr = V(:, r);
                M_val_fast = M_val_fast + lambda(r) * (Theta_a' * vr) * (Theta_b' * vr) * (Theta_c' * vr);
            end
            
            % Verify they match
            if abs(M_val_explicit - M_val_fast) > 1e-9
                warning('Precision mismatch between explicit and fast contraction: %e', abs(M_val_explicit - M_val_fast));
            end
            
            triad_results(idx_triad, :) = [a, b, c, M_val_fast, abs(M_val_fast)];
            idx_triad = idx_triad + 1;
        end
    end
end

% Step 5: Tabulate and Rank the Triad Modulations
fprintf('Ranking triads by absolute influence...\n');
[~, sort_triad_idx] = sort(triad_results(:, 5), 'descend');
triad_results_sorted = triad_results(sort_triad_idx, :);

% Display top 10 primary biological results
fprintf('\n============================================================\n');
fprintf('TOP 10 TRIADS BY ABSOLUTE INFLUENCE (%s):\n', upper(task_name));
fprintf('------------------------------------------------------------\n');
fprintf('%-6s %-25s %-25s %-25s %-12s %-12s\n', 'Rank', 'Node A', 'Node B', 'Node C', 'M_abc', 'Abs(M_abc)');
fprintf('------------------------------------------------------------\n');
for k = 1:10
    a = triad_results_sorted(k, 1);
    b = triad_results_sorted(k, 2);
    c = triad_results_sorted(k, 3);
    val = triad_results_sorted(k, 4);
    abs_val = triad_results_sorted(k, 5);
    fprintf('%-6d %-25s %-25s %-25s %-12.6f %-12.6f\n', ...
        k, unique_networks(a), unique_networks(b), unique_networks(c), val, abs_val);
end
fprintf('============================================================\n');

% Save to CSV
triad_table = table(unique_networks(triad_results_sorted(:, 1)), ...
                    unique_networks(triad_results_sorted(:, 2)), ...
                    unique_networks(triad_results_sorted(:, 3)), ...
                    triad_results_sorted(:, 4), ...
                    triad_results_sorted(:, 5), ...
                    'VariableNames', {'Node_A', 'Node_B', 'Node_C', 'M_abc', 'Abs_M_abc'});

csv_filename = fullfile(output_dir, sprintf('%s_%s_coskewness_triads.csv', dataset, task_name));
writetable(triad_table, csv_filename);
fprintf('Saved 220 triads to %s\n', csv_filename);

% Append results to MAT file
cp_spatial_components = V;
cp_subject_loadings = W;
cp_singular_values = lambda;
coskewness_target_tensor = W_tensor;
coskewness_precision_matrix = Theta;
coskewness_triad_results = triad_results_sorted;

% Filter for distinct triads (a < b < c)
distinct_mask = (triad_results_sorted(:, 1) < triad_results_sorted(:, 2)) & ...
                (triad_results_sorted(:, 2) < triad_results_sorted(:, 3));
triads_distinct = triad_results_sorted(distinct_mask, :);
coskewness_triad_distinct_results = triads_distinct;

save(results_filename, 'cp_spatial_components', 'cp_subject_loadings', ...
     'cp_singular_values', 'cp_var_explained', 'coskewness_target_tensor', 'coskewness_precision_matrix', ...
     'coskewness_triad_results', 'coskewness_triad_distinct_results', '-append');
fprintf('Appended variables to %s\n', results_filename);

% --- Generate Lollipop Plot of Top ranked Triads ---
fprintf('Generating lollipop plot of top %d highlighted triads...\n', n_lollipops);
n_plot = min(n_lollipops, size(triad_results_sorted, 1));
top_triad_vals = zeros(n_plot, 1);
triad_lollipop_labels = cell(n_plot, 1);
for k = 1:n_plot
    a = triad_results_sorted(k, 1);
    b = triad_results_sorted(k, 2);
    c = triad_results_sorted(k, 3);
    top_triad_vals(k) = triad_results_sorted(k, 4); % M_abc
    triad_lollipop_labels{k} = sprintf('%s - %s - %s', unique_networks(a), unique_networks(b), unique_networks(c));
end

triad_plot_filename = fullfile(output_dir, sprintf('%s_%s_coskewness_triads_lollipop_plot.png', dataset, task_name));
plot_lollipop(top_triad_vals, triad_lollipop_labels, ...
    sprintf('%s %s: Top %d Highlighted Triads (M_abc)', upper(dataset), upper(task_name), n_plot), ...
    'Adjusted Triad Index (M_abc)', triad_plot_filename);
fprintf('Triad lollipop plot saved to %s\n', triad_plot_filename);

% --- Generate Lollipop Plot of Top ranked Distinct Triads ---
fprintf('Generating lollipop plot of top %d distinct triads...\n', n_lollipops);
n_plot_dist = min(n_lollipops, size(triads_distinct, 1));
distinct_triad_vals = zeros(n_plot_dist, 1);
distinct_triad_lollipop_labels = cell(n_plot_dist, 1);
for k = 1:n_plot_dist
    a = triads_distinct(k, 1);
    b = triads_distinct(k, 2);
    c = triads_distinct(k, 3);
    distinct_triad_vals(k) = triads_distinct(k, 4); % M_abc
    distinct_triad_lollipop_labels{k} = sprintf('%s - %s - %s', unique_networks(a), unique_networks(b), unique_networks(c));
end

distinct_plot_filename = fullfile(output_dir, sprintf('%s_%s_coskewness_triads_distinct_lollipop_plot.png', dataset, task_name));
plot_lollipop(distinct_triad_vals, distinct_triad_lollipop_labels, ...
    sprintf('%s %s: Top %d Distinct Triads (M_abc)', upper(dataset), upper(task_name), n_plot_dist), ...
    'Adjusted Triad Index (M_abc)', distinct_plot_filename);
fprintf('Distinct triad lollipop plot saved to %s\n', distinct_plot_filename);

t_elapsed = toc(t_start);
fprintf('Coskewness triad analysis complete for %s task in %.2f seconds.\n', upper(task_name), t_elapsed);

% --- Generate Text Report ---
report_filename = fullfile(output_dir, sprintf('%s_%s_normative_report.txt', dataset, task_name));
fid = fopen(report_filename, 'w');
if fid ~= -1
    fprintf(fid, '============================================================\n');
    fprintf(fid, 'NORMATIVE PROFILE REPORT: %s %s\n', upper(dataset), upper(task_name));
    fprintf(fid, '============================================================\n\n');
    fprintf(fid, 'Data Source:       %s dataset\n', upper(dataset));
    fprintf(fid, 'Analysis Time:     %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    fprintf(fid, 'Computation Time:  %.2f seconds\n\n', t_elapsed);
    
    % CP Tensor components (Non-Gaussian Variance Explained)
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, 'CP TENSOR BARYCENTER COMPONENTS (NON-GAUSSIAN VARIANCE):\n');
    fprintf(fid, '------------------------------------------------------------\n');
    for r = 1:length(lambda)
        fprintf(fid, 'Component %d: lambda = %.6f (%.2f%% variance explained)\n', ...
            r, lambda(r), cp_var_explained(r));
    end
    fprintf(fid, '\n');
    
    % Strongest elements of Bures-Wasserstein Barycenter (Lower Triangle)
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, 'STRONGEST ELEMENTS OF BURES-WASSERSTEIN BARYCENTER:\n');
    fprintf(fid, '------------------------------------------------------------\n');
    abs_bary = abs(barycenter);
    lower_tri_mask = tril(true(size(abs_bary)), -1);
    lower_abs = abs_bary;
    lower_abs(~lower_tri_mask) = -inf;
    [~, sort_bary_idx] = sort(lower_abs(:), 'descend');
    
    for k = 1:min(5, sum(lower_tri_mask(:)))
        [r_idx, c_idx] = ind2sub(size(barycenter), sort_bary_idx(k));
        fprintf(fid, '%d. %s - %s: r = %.6f\n', k, ...
            unique_networks(r_idx), unique_networks(c_idx), barycenter(r_idx, c_idx));
    end
    fprintf(fid, '\n');
    
    % Strongest 3-Way Interactions (Top 10 Triads)
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, 'STRONGEST 3-WAY INTERACTIONS (ADJUSTED TRIAD INDEX M_abc):\n');
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, '%-4s %-25s %-25s %-25s %-12s %-12s\n', 'Rank', 'Node A', 'Node B', 'Node C', 'M_abc', 'Abs(M_abc)');
    fprintf(fid, '------------------------------------------------------------\n');
    for k = 1:10
        a = triad_results_sorted(k, 1);
        b = triad_results_sorted(k, 2);
        c = triad_results_sorted(k, 3);
        val = triad_results_sorted(k, 4);
        abs_val = triad_results_sorted(k, 5);
        fprintf(fid, '%-4d %-25s %-25s %-25s %-12.6f %-12.6f\n', ...
            k, unique_networks(a), unique_networks(b), unique_networks(c), val, abs_val);
    end
    fprintf(fid, '\n');
    
    % Strongest Distinct 3-Way Interactions (Top 10 Triads, mutually distinct networks)
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, 'STRONGEST DISTINCT 3-WAY INTERACTIONS (ALL 3 NODES DIFFERENT):\n');
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, '%-4s %-25s %-25s %-25s %-12s %-12s\n', 'Rank', 'Node A', 'Node B', 'Node C', 'M_abc', 'Abs(M_abc)');
    fprintf(fid, '------------------------------------------------------------\n');
    for k = 1:min(10, size(triads_distinct, 1))
        a = triads_distinct(k, 1);
        b = triads_distinct(k, 2);
        c = triads_distinct(k, 3);
        val = triads_distinct(k, 4);
        abs_val = triads_distinct(k, 5);
        fprintf(fid, '%-4d %-25s %-25s %-25s %-12.6f %-12.6f\n', ...
            k, unique_networks(a), unique_networks(b), unique_networks(c), val, abs_val);
    end
    
    fclose(fid);
    fprintf('Saved summary report to %s\n', report_filename);
else
    warning('Could not create report file: %s', report_filename);
end
end
