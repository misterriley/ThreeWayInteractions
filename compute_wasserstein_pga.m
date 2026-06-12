function compute_wasserstein_pga(dataset, task_name, use_sparse_pga, z_threshold)
% COMPUTE_WASSERSTEIN_PGA Performs Principal Geodesic Analysis (PGA) on
% functional connectivity (FC) matrices using the Bures-Wasserstein metric,
% mapping matrices to the tangent space at the Bures-Wasserstein barycenter.
% Supports bootstrap ratio thresholding to yield sparse, stable loadings.
%
% Usage:
%   compute_wasserstein_pga(dataset, task_name)
%   compute_wasserstein_pga(dataset, task_name, use_sparse_pga, z_threshold)

if nargin < 1 || isempty(dataset)
    dataset = 'hcp';
end
if nargin < 2 || isempty(task_name)
    task_name = 'wm';
end
if nargin < 3 || isempty(use_sparse_pga)
    use_sparse_pga = true;
end
if nargin < 4
    z_threshold = []; % Will be set dynamically using Bonferroni correction
end

fprintf('\n------------------------------------------------------------\n');
fprintf('STARTING WASSERSTEIN PGA FOR:\n');
fprintf('  Dataset: %s\n', upper(dataset));
fprintf('  Task:    %s\n', upper(task_name));
fprintf('------------------------------------------------------------\n');

output_dir = fullfile(pwd, 'outputs', dataset, task_name);
results_filename = fullfile(output_dir, sprintf('%s_%s_normative_results.mat', dataset, task_name));

if ~exist(results_filename, 'file')
    error('Results file %s does not exist. Please run compute_normative_profile first.', results_filename);
end

% Load results
fprintf('Loading normative results from %s...\n', results_filename);
res = load(results_filename);

if ~isfield(res, 'fc_matrices') || ~isfield(res, 'barycenter_normalized')
    error('Missing required variables (fc_matrices, barycenter_normalized) in %s', results_filename);
end

fc_matrices = res.fc_matrices;
S = res.barycenter_normalized;
n_networks = size(S, 1);
n_subs = size(fc_matrices, 3);

fprintf('Loaded %d subject FC matrices of size %dx%d.\n', n_subs, n_networks, n_networks);

% --- Ensure S is strictly positive definite ---
[V_S, D_S] = eig(S);
d_S = diag(D_S);
d_S(d_S < 1e-9) = 1e-9;
S_reg = V_S * diag(d_S) * V_S';
S_reg = (S_reg + S_reg') / 2;

% Compute S^(1/2) and S^(-1/2)
sqrtS = V_S * diag(sqrt(d_S)) * V_S';
invSqrtS = V_S * diag(1 ./ (sqrt(d_S))) * V_S';

% --- Map each subject to the tangent space at the barycenter ---
fprintf('Mapping subjects to the tangent space...\n');
n_features = n_networks * (n_networks + 1) / 2;

% Set dynamic z_threshold if empty (defaults to Bonferroni correction for FWER = 0.05)
if isempty(z_threshold)
    alpha_corrected = 0.05 / n_features;
    z_threshold = sqrt(2) * erfinv(1 - alpha_corrected);
    fprintf('No z_threshold specified. Applying Bonferroni FWER correction (alpha = 0.05):\n');
    fprintf('  Number of tests (features): %d\n', n_features);
    fprintf('  Corrected alpha level:     %e\n', alpha_corrected);
    fprintf('  Critical Z-threshold:      %.4f\n\n', z_threshold);
else
    fprintf('Using user-specified Z-threshold: %.4f\n\n', z_threshold);
end

X_data = zeros(n_subs, n_features);

for i = 1:n_subs
    C_i = fc_matrices(:, :, i);
    
    % Ensure C_i is positive semidefinite
    [V_C, D_C] = eig(C_i);
    d_C = diag(D_C);
    d_C(d_C < 0) = 0;
    C_i_reg = V_C * diag(d_C) * V_C';
    C_i_reg = (C_i_reg + C_i_reg') / 2;
    
    % Compute (S^(1/2) * C_i * S^(1/2))^(1/2)
    temp = sqrtS * C_i_reg * sqrtS;
    temp = (temp + temp') / 2;
    [V_t, D_t] = eig(temp);
    d_t = diag(D_t);
    d_t(d_t < 0) = 0;
    sqrt_temp = V_t * diag(sqrt(d_t)) * V_t';
    
    % Tangent vector matrix X_i
    X_i = sqrt_temp - S_reg;
    
    % Vectorize X_i (scaling off-diagonal elements by sqrt(2))
    x_i = zeros(n_features, 1);
    idx = 1;
    for j = 1:n_networks
        x_i(idx) = X_i(j, j);
        idx = idx + 1;
    end
    for j = 1:n_networks
        for k = j+1:n_networks
            x_i(idx) = sqrt(2) * X_i(j, k);
            idx = idx + 1;
        end
    end
    
    X_data(i, :) = x_i';
end

% --- Perform Principal Component Analysis (PCA) ---
fprintf('Performing Principal Component Analysis on tangent vectors...\n');
[pga_coefficients, pga_scores, pga_latent, ~, pga_explained, pga_mu] = pca(X_data);

pga_coefficients_dense = pga_coefficients; % keep original dense loadings
pga_bootstrap_ratios = [];

if use_sparse_pga
    fprintf('Running bootstrap analysis (100 iterations) to find stable features...\n');
    n_boot = 100;
    n_pcs = min(5, size(pga_coefficients, 2));
    boot_loadings = zeros(n_features, n_pcs, n_boot);
    
    for b = 1:n_boot
        % Resample subjects with replacement
        boot_idx = randi(n_subs, n_subs, 1);
        X_boot = X_data(boot_idx, :);
        
        % Run PCA on bootstrap sample
        [coeff_b, ~] = pca(X_boot);
        
        % Align signs to reference (original) eigenvectors
        for pc = 1:n_pcs
            u_orig = pga_coefficients(:, pc);
            if pc <= size(coeff_b, 2)
                u_b = coeff_b(:, pc);
                if dot(u_b, u_orig) < 0
                    u_b = -u_b;
                end
                boot_loadings(:, pc, b) = u_b;
            else
                boot_loadings(:, pc, b) = 0;
            end
        end
    end
    
    % Compute standard deviation of loadings across bootstrap runs
    boot_std = std(boot_loadings, 0, 3);
    
    % Compute Bootstrap Ratio (Z-score)
    pga_bootstrap_ratios = zeros(size(pga_coefficients));
    pga_bootstrap_ratios(:, 1:n_pcs) = pga_coefficients(:, 1:n_pcs) ./ (boot_std + 1e-9);
    
    % Threshold coefficients
    pga_coefficients_sparse = pga_coefficients;
    for pc = 1:n_pcs
        mask = abs(pga_bootstrap_ratios(:, pc)) >= z_threshold;
        pga_coefficients_sparse(~mask, pc) = 0;
        
        % Re-normalize
        norm_val = norm(pga_coefficients_sparse(:, pc));
        if norm_val > 0
            pga_coefficients_sparse(:, pc) = pga_coefficients_sparse(:, pc) / norm_val;
        else
            % Fallback: keep the single largest loading if none survived
            [~, max_idx] = max(abs(pga_coefficients(:, pc)));
            pga_coefficients_sparse(max_idx, pc) = sign(pga_coefficients(max_idx, pc));
        end
    end
    
    pga_coefficients = pga_coefficients_sparse;
    % Recompute scores based on sparse loadings
    pga_scores = (X_data - pga_mu) * pga_coefficients;
end

% Save PGA results back to MAT file
fprintf('Saving PGA results to %s...\n', results_filename);
save(results_filename, 'pga_coefficients', 'pga_coefficients_dense', 'pga_scores', ...
     'pga_latent', 'pga_explained', 'pga_mu', 'pga_bootstrap_ratios', ...
     'use_sparse_pga', 'z_threshold', '-append');

% --- Visualizations ---
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

% 1. Scree Plot
fprintf('Generating Scree plot...\n');
fig_scree = figure('Visible', 'off');
bar(pga_explained(1:min(10, length(pga_explained))), 'FaceColor', [0.15, 0.45, 0.75]);
ylim([0, 25]);
ylabel('Percentage of Variance Explained (%)');
xlabel('Principal Geodesic Component');
title(sprintf('%s %s: PGA Explained Variance (Top 10)', upper(dataset), upper(task_name)));
grid on;
set(gca, 'Box', 'off');
scree_plot_filename = fullfile(output_dir, sprintf('%s_%s_pga_scree_plot.png', dataset, task_name));
exportgraphics(fig_scree, scree_plot_filename, 'Resolution', 300);
close(fig_scree);

% 2. Geodesic Reconstructions (PC1 & PC2)
unique_networks = res.unique_networks;
steps = [-2, -1, 0, 1, 2];
n_steps = length(steps);

for pc = 1:min(2, size(pga_coefficients, 2))
    fprintf('Reconstructing and plotting geodesic variation along PC %d...\n', pc);
    
    % Compute standard deviation of scores along this PC
    pc_std = std(pga_scores(:, pc));
    if pc_std == 0
        pc_std = 1;
    end
    
    fig_geod = figure('Visible', 'off', 'Position', [100, 100, 1500, 300]);
    
    for s_idx = 1:n_steps
        factor = steps(s_idx);
        score_val = factor * pc_std;
        
        % Reconstruct tangent vector: x_rec = mu + score_val * pc_eigenvector
        x_rec = pga_mu' + score_val * pga_coefficients(:, pc);
        
        % De-vectorize to symmetric matrix X_rec
        X_rec = zeros(n_networks, n_networks);
        idx = 1;
        for j = 1:n_networks
            X_rec(j, j) = x_rec(idx);
            idx = idx + 1;
        end
        for j = 1:n_networks
            for k = j+1:n_networks
                val = x_rec(idx) / sqrt(2);
                X_rec(j, k) = val;
                X_rec(k, j) = val;
                idx = idx + 1;
            end
        end
        
        % Project back to manifold via exponential map
        Z = invSqrtS * X_rec * invSqrtS;
        M_t = eye(n_networks) + Z;
        C_rec = M_t * S_reg * M_t;
        C_rec = (C_rec + C_rec') / 2;
        
        % Normalize reconstructed covariance matrix to correlation matrix
        d_rec = diag(C_rec);
        d_rec(d_rec < 1e-9) = 1e-9;
        C_rec_norm = C_rec ./ sqrt(d_rec * d_rec');
        C_rec_norm(logical(eye(size(C_rec_norm)))) = 1; % ensure exact ones on diagonal
        
        % Subplot
        subplot(1, n_steps, s_idx);
        ax_sub = gca;
        if s_idx == 1
            sub_labels = unique_networks;
        else
            sub_labels = {};
        end
        plot_masked_carpet(C_rec_norm, sub_labels, sprintf('Score: %d\\sigma', factor), '', bwr_cmap, [-1 1], false, ax_sub);
        
        % Subplot-specific adjustments
        xlabel(ax_sub, '');
        ylabel(ax_sub, '');
        set(ax_sub, 'FontSize', 8);
        if s_idx == n_steps
            colorbar(ax_sub);
        end
    end
    
    % Add overall title
    sgtitle(sprintf('%s %s: Variation along Principal Geodesic PC%d', ...
        upper(dataset), upper(task_name), pc), 'Interpreter', 'none');
    
    geod_plot_filename = fullfile(output_dir, sprintf('%s_%s_pga_pc%d_geodesic.png', dataset, task_name, pc));
    exportgraphics(fig_geod, geod_plot_filename, 'Resolution', 300);
    close(fig_geod);
end

% 3. PC Tangent Directions (Eigenvectors in Tangent Space)
for pc = 1:min(2, size(pga_coefficients, 2))
    fprintf('Plotting tangent direction for PC %d...\n', pc);
    
    % Get the eigenvector (column of pga_coefficients)
    u_k = pga_coefficients(:, pc);
    
    % De-vectorize to symmetric matrix U_k (reversing the sqrt(2) scaling)
    U_k = zeros(n_networks, n_networks);
    idx = 1;
    for j = 1:n_networks
        U_k(j, j) = u_k(idx);
        idx = idx + 1;
    end
    for j = 1:n_networks
        for k = j+1:n_networks
            val = u_k(idx) / sqrt(2);
            U_k(j, k) = val;
            U_k(k, j) = val;
            idx = idx + 1;
        end
    end
    
    % Generate carpet plot of the tangent direction using the helper function
    dir_plot_filename = fullfile(output_dir, sprintf('%s_%s_pga_pc%d_direction_carpet_plot.png', dataset, task_name, pc));
    max_val = max(abs(U_k), [], 'all');
    clim_dir = [-1 1];
    if max_val > 0 && ~isnan(max_val)
        clim_dir = [-max_val, max_val];
    end
    
    plot_masked_carpet(U_k, unique_networks, ...
        sprintf('%s %s: PC%d Tangent Direction (Eigenvector)', upper(dataset), upper(task_name), pc), ...
        dir_plot_filename, bwr_cmap, clim_dir, false);
end

fprintf('PGA and plotting completed for %s task.\n', upper(task_name));
end
