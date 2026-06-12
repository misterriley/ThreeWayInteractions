% run_normative_pipeline.m
% Wrapper script to loop over multiple tasks and call the compute_normative_profile pipeline.

% Parameters
if ~exist('dataset', 'var')
    dataset = 'imagen';
end
if ~exist('tasks', 'var')
    if strcmp(dataset, 'imagen')
        tasks = {'MID', 'SST'};
    else
        tasks = {'emotion', 'gambling', 'language', 'motor', 'relational', 'rest', 'rest2', 'social', 'wm'};
    end
end
if ~exist('n_lollipops', 'var')
    n_lollipops = 5;
end

% Option flags:
%   Set to true to recompute, false to load existing saved results.
recompute_fc_matrices = true;
recompute_barycenter  = true;
recompute_coskewness  = true;

fprintf('Starting normative profile pipeline for dataset: %s\n', upper(dataset));
fprintf('Tasks to process: %s\n\n', strjoin(tasks, ', '));

for t = 1:length(tasks)
    task_name = tasks{t};
    
    % Call the refactored pipeline function
    try
        compute_normative_profile(dataset, task_name, ...
            recompute_fc_matrices, recompute_barycenter, recompute_coskewness, n_lollipops);
        
        % Run Principal Geodesic Analysis (PGA) using Bures-Wasserstein metric
        compute_wasserstein_pga(dataset, task_name);
        
        % Run Coskewness Triad Analysis using 4D CP Tensor Barycenter
        compute_coskewness_triads(dataset, task_name, 5, n_lollipops);
    catch ME
        fprintf('ERROR processing task %s: %s\n', task_name, ME.message);
    end
end

fprintf('\nAll tasks in the pipeline completed.\n');
