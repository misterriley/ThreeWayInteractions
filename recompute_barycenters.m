% recompute_barycenters.m
% Script to re-run the Wasserstein barycenter calculation (including bootstrap resampling)
% for all tasks in HCP and IMAGEN datasets and save the boot_barycenters variable.
% Since the individual FC matrices are already computed and saved, we can pass:
%   recompute_fc_matrices = false
%   recompute_barycenter  = true
%   recompute_coskewness  = false
% This will run very quickly because it loads the cached FC matrices and only does the
% bootstrap barycenter calculations (100 iterations per task).

datasets = {'hcp', 'imagen'};

for d = 1:length(datasets)
    dataset = datasets{d};
    if strcmp(dataset, 'imagen')
        tasks = {'MID', 'SST'};
    else
        tasks = {'emotion', 'gambling', 'language', 'motor', 'relational', 'rest', 'rest2', 'social', 'wm'};
    end
    
    fprintf('=== Recomputing barycenters with bootstrap for dataset: %s ===\n', upper(dataset));
    for t = 1:length(tasks)
        task_name = tasks{t};
        fprintf('\nProcessing task: %s...\n', upper(task_name));
        
        try
            % Call compute_normative_profile with:
            %   recompute_fc_matrices = false
            %   recompute_barycenter  = true
            %   recompute_coskewness  = false
            %   n_lollipops = 5
            compute_normative_profile(dataset, task_name, false, true, false, 5);
        catch ME
            fprintf('ERROR processing %s - %s: %s\n', dataset, task_name, ME.message);
        end
    end
end

fprintf('\nAll tasks recomputed and saved successfully.\n');
