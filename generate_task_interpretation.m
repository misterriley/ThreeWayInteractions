function generate_task_interpretation(dataset, task_name)
% GENERATE_TASK_INTERPRETATION Automatically generates a structured, 
% neuroscientifically-grounded interpretation of the normative results
% for a given task and dataset.
%
% Usage:
%   generate_task_interpretation('hcp', 'wm')

if nargin < 1 || isempty(dataset)
    dataset = 'hcp';
end
if nargin < 2 || isempty(task_name)
    task_name = 'wm';
end

output_dir = fullfile(pwd, 'outputs', dataset, task_name);
results_filename = fullfile(output_dir, sprintf('%s_%s_normative_results.mat', dataset, task_name));
interpretation_filename = fullfile(output_dir, sprintf('%s_%s_interpretation.txt', dataset, task_name));

if ~exist(results_filename, 'file')
    error('Normative results file %s does not exist.', results_filename);
end

% Load results
res = load(results_filename);

if ~isfield(res, 'unique_networks') || ~isfield(res, 'barycenter_normalized') || ...
   ~isfield(res, 'coskewness_triad_results') || ~isfield(res, 'pga_coefficients') || ...
   ~isfield(res, 'pga_explained')
    error('Results file is missing required fields (unique_networks, barycenter_normalized, coskewness_triad_results, pga_coefficients, pga_explained).');
end

unique_networks = res.unique_networks;
barycenter = res.barycenter_normalized;
triad_results = res.coskewness_triad_results;
triads_distinct = res.coskewness_triad_distinct_results;
pga_coeff = res.pga_coefficients;
pga_explained = res.pga_explained;
n_networks = length(unique_networks);

% --- Task Specific Intros ---
task_intros = containers.Map();
task_intros('emotion') = 'The HCP Emotion Processing task recruits brain networks involved in processing social and emotional stimuli (matching fearful or angry facial expressions compared to simple geometric shapes). In this task, the Visual Association (VAs) and Subcortical (SC) networks—specifically including the amygdala—are highly active, working alongside Frontoparietal (FP) control networks to evaluate threat and regulate emotional responses.';
task_intros('gambling') = 'The HCP Gambling/Reward task uses a card-guessing paradigm to activate reward processing and decision-making circuitry. It primarily recruits Subcortical (SC) regions (specifically the ventral striatum and thalamus) involved in reward anticipation and feedback, Frontoparietal (FP) control regions for strategic choice, and Medial Frontal (MF)/ACC regions for tracking outcomes and reward prediction errors.';
task_intros('language') = 'The HCP Language task contrasts story comprehension with simple mathematics. It targets regions involved in semantic decoding, narrative processing, and syntactic integration. This task strongly recruits the Auditory/Visual Association (VAs) networks for auditory/visual sensory processing, Frontoparietal (FP) control networks for task coordination, and the Default Mode Network (DMN), which is highly engaged during narrative-level comprehension and semantic representation.';
task_intros('motor') = 'The HCP Motor task requires execution of simple movements (clenched fists, toe taps, tongue movements). It activates the classical motor execution loop, primarily recruiting the Somatomotor (Mot) network, the Cerebellum (CBL) for movement calibration and timing, and the Subcortical (SC) basal ganglia for movement gating and initiation.';
task_intros('relational') = 'The HCP Relational Processing task involves comparing stimulus attributes (shapes, textures, sizes) and detecting whether relation patterns match. This task places high demands on relational reasoning and cognitive control, strongly recruiting the Frontoparietal (FP) control network for top-down rule evaluation, the Visual Association (VAs) network for fine-grained feature comparison, and the Medial Frontal (MF) network for monitoring decision conflict.';
task_intros('social') = 'The HCP Social Cognition task presents short animations of geometric shapes interacting (social animation) or moving randomly (control). It recruits the "theory of mind" or mentalizing network. The Default Mode Network (DMN) is heavily recruited for inferring social intentions and mental states, while the Visual Association (VAs) network acts as the primary sensory-semantic decoding channel for complex motion, and the Frontoparietal (FP) network manages task focus.';
task_intros('wm') = 'The HCP Working Memory task utilizes an N-back paradigm (contrasting 0-back and 2-back conditions) to assess working memory capacity and cognitive control. It recruits the core central executive network, demanding high-level coordination between the Frontoparietal (FP) control network (for item maintenance and updating), the Medial Frontal (MF) network (for conflict monitoring), the Salience (SAL) network (for target detection), and Visual Association (VAs) networks (for stimulus decoding).';
task_intros('rest') = 'The HCP Resting State scans capture intrinsic, self-organized brain dynamics in the absence of explicit task demands. They reveal the baseline functional architecture of the brain, characterized by strong coherence within the Default Mode Network (DMN), clear segregation between task-positive (FP/SAL) and task-negative (DMN) networks, and intrinsic sensory-motor coordination.';
task_intros('rest2') = 'The HCP Resting State scans (Run 2) capture intrinsic, self-organized brain dynamics in the absence of explicit task demands. They reveal the baseline functional architecture of the brain, characterized by strong coherence within the Default Mode Network (DMN), clear segregation between task-positive (FP/SAL) and task-negative (DMN) networks, and intrinsic sensory-motor coordination.';
task_intros('MID') = 'The IMAGEN Monetary Incentive Delay (MID) task is a widely used paradigm in developmental cognitive neuroscience to assess reward processing. It targets striatal and dopaminergic circuitry during reward anticipation and feedback. It primarily recruits the Subcortical (SC) network for reward valuation, the Salience (SAL) network for arousal and incentive tracking, and the Frontoparietal (FP) control network for motor preparation.';
task_intros('SST') = 'The IMAGEN Stop Signal Task (SST) measures response inhibition—the ability to cancel an already initiated motor action. It requires rapid cognitive control and vetoing. This task strongly recruits the Medial Frontal (MF/ACC) network for error detection and conflict monitoring, the Salience (SAL) network for detecting the stop signal, the Frontoparietal (FP) network for top-down inhibitory control, and the Somatomotor (Mot) network to execute or cancel motor button presses.';

intro_text = '';
if task_intros.isKey(task_name)
    intro_text = task_intros(task_name);
else
    intro_text = sprintf('Normative profile analysis of the %s dataset during the %s task.', dataset, task_name);
end

% --- Network Descriptions ---
net_descs = containers.Map();
net_descs('MF') = 'Medial Frontal (action monitoring, error detection, conflict resolution)';
net_descs('FP') = 'Frontoparietal (executive control, task rules, goal-directed attention)';
net_descs('DMN') = 'Default Mode Network (self-referential thought, internal narratives, social mentalizing)';
net_descs('Mot') = 'Somatomotor (motor execution, sensory-motor integration)';
net_descs('VI') = 'Visual I (primary visual feature processing)';
net_descs('VII') = 'Visual II (secondary visual processing, feature binding)';
net_descs('VAs') = 'Visual Association (higher-order visual categorisation, semantic decoding)';
net_descs('SAL') = 'Salience (attentional switching, detection of salient events)';
net_descs('SC') = 'Subcortical (basal ganglia/thalamus gating, reward, arousal routing)';
net_descs('CBL') = 'Cerebellar (motor calibration, timing, error prediction)';

fid = fopen(interpretation_filename, 'w');
if fid == -1
    error('Could not create interpretation file: %s', interpretation_filename);
end

fprintf(fid, '============================================================\n');
fprintf(fid, 'NEUROFUNCTIONAL INTERPRETATION: %s %s\n', upper(dataset), upper(task_name));
fprintf(fid, '============================================================\n\n');

fprintf(fid, 'INTRODUCTION & COGNITIVE TASK PROFILE:\n');
fprintf(fid, '------------------------------------------------------------\n');
fprintf(fid, '%s\n\n', intro_text);

% --- SECTION 1: BURES-WASSERSTEIN BARYCENTER ---
fprintf(fid, '1. CONSENSUS POPULATION GEOMETRY (BURES-WASSERSTEIN BARYCENTER):\n');
fprintf(fid, '------------------------------------------------------------\n');
fprintf(fid, 'The Bures-Wasserstein barycenter represents the consensus functional connectivity\n');
fprintf(fid, 'average across the cohort (N = %d subjects), respecting the geometry of symmetric\n', size(res.fc_matrices, 3));
fprintf(fid, 'positive-definite correlation matrices. The strongest baseline couplings are:\n\n');

% Get top 5 barycenter elements
abs_bary = abs(barycenter);
lower_tri_mask = tril(true(size(abs_bary)), -1);
lower_abs = abs_bary;
lower_abs(~lower_tri_mask) = -inf;
[~, sort_bary_idx] = sort(lower_abs(:), 'descend');

for k = 1:min(5, sum(lower_tri_mask(:)))
    [r_idx, c_idx] = ind2sub(size(barycenter), sort_bary_idx(k));
    netA = unique_networks{r_idx};
    netB = unique_networks{c_idx};
    r_val = barycenter(r_idx, c_idx);
    
    fprintf(fid, '   Rank %d: %s - %s (r = %.4f)\n', k, netA, netB, r_val);
    
    % Generate dynamic explanation based on correlation sign and network descriptions
    descA = net_descs(netA);
    descB = net_descs(netB);
    if r_val >= 0
        fprintf(fid, '     -> Reflects strong functional integration: the %s and\n', descA);
        fprintf(fid, '        %s work in close sync during this task state.\n', descB);
    else
        fprintf(fid, '     -> Reflects functional segregation (anti-correlation): the %s\n', descA);
        fprintf(fid, '        and %s are kept segregated to prevent cross-talk.\n', descB);
    end
    fprintf(fid, '\n');
end

% --- SECTION 2: DYNAMIC GATING & THREE-WAY INTERACTIONS ---
fprintf(fid, '2. NON-LINEAR DYNAMICS & STATE-DEPENDENT GATING (COSKEWNESS TRIADS):\n');
fprintf(fid, '------------------------------------------------------------\n');
fprintf(fid, 'A traditional 2D functional connectivity analysis (covariance) only captures linear,\n');
fprintf(fid, 'time-averaged pairwise connections. By contrast, the 3D coskewness tensor captures third-order\n');
fprintf(fid, 'moments that show dynamic, state-dependent gating: how the functional coupling between two\n');
fprintf(fid, 'regions (A and B) is gated or modulated by the state of a third region (C).\n\n');

if isfield(res, 'cp_var_explained') && ~isempty(res.cp_var_explained)
    fprintf(fid, 'Symmetric CP decomposition reveals that Component 1 explains %.2f%% of the non-Gaussian\n', res.cp_var_explained(1));
    fprintf(fid, 'variance (weight lambda = %.2f), demonstrating a highly structured non-linear communication mode.\n\n', res.cp_singular_values(1));
end

fprintf(fid, 'The strongest three-way interactions ranked by the Adjusted Triad Index M_abc are:\n\n');
for k = 1:min(5, size(triad_results, 1))
    a = triad_results(k, 1);
    b = triad_results(k, 2);
    c = triad_results(k, 3);
    m_val = triad_results(k, 4);
    netA = unique_networks{a};
    netB = unique_networks{b};
    netC = unique_networks{c};
    
    fprintf(fid, '   Rank %d: %s - %s - %s (M_abc = %.4f)\n', k, netA, netB, netC, m_val);
    
    % Explanation of triads
    if a == b && b == c
        fprintf(fid, '     -> Self-modulating hub: The %s exhibits massive non-linear self-regulation,\n', net_descs(netC));
        fprintf(fid, '        showing brief, bursty periods of high activity synchronization.\n');
    elseif a == b
        fprintf(fid, '     -> Gated communication: The self-coupling/variance of the %s\n', net_descs(netA));
        fprintf(fid, '        is dynamically gated by the activity level of the %s.\n', net_descs(netC));
    else
        fprintf(fid, '     -> Multi-system cross-talk: The connection between the %s\n', net_descs(netA));
        fprintf(fid, '        and the %s is gated or modulated by the %s.\n', net_descs(netB), net_descs(netC));
    end
    fprintf(fid, '\n');
end

% Top distinct triads
fprintf(fid, 'Strongest cross-talk interactions among mutually distinct networks:\n\n');
for k = 1:min(3, size(triads_distinct, 1))
    a = triads_distinct(k, 1);
    b = triads_distinct(k, 2);
    c = triads_distinct(k, 3);
    m_val = triads_distinct(k, 4);
    netA = unique_networks{a};
    netB = unique_networks{b};
    netC = unique_networks{c};
    
    fprintf(fid, '   * %s - %s - %s (M_abc = %.4f)\n', netA, netB, netC, m_val);
    fprintf(fid, '     -> The functional communication channel between the %s\n', net_descs(netA));
    fprintf(fid, '        and the %s is actively modulated by the %s.\n', net_descs(netB), net_descs(netC));
    if m_val < 0
        fprintf(fid, '        The negative index indicates an inhibitory gating effect: co-activation\n');
        fprintf(fid, '        suppresses communication in this triad, acting as a functional veto.\n');
    else
        fprintf(fid, '        The positive index indicates a synergistic facilitation effect: co-activation\n');
        fprintf(fid, '        enhances communication across these three systems.\n');
    end
    fprintf(fid, '\n');
end

% --- SECTION 3: PRINCIPAL GEODESIC VARIATION ---
fprintf(fid, '3. COHORT VARIATION & INDIVIDUAL NEURAL STRATEGIES (WASSERSTEIN PGA):\n');
fprintf(fid, '------------------------------------------------------------\n');
fprintf(fid, 'Principal Geodesic Analysis (PGA) identifies the primary directions of individual variation\n');
fprintf(fid, 'around the cohort Bures-Wasserstein barycenter. The top two geodesic dimensions explain:\n');
fprintf(fid, '   * PC 1: %.2f%% of population variance\n', pga_explained(1));
fprintf(fid, '   * PC 2: %.2f%% of population variance\n\n', pga_explained(2));

% PC1 Loadings
fprintf(fid, 'PC 1 Geodesic Axis Loadings (Strongest sparse elements):\n');
coeff1 = pga_coeff(:, 1);
[~, sorted_idx1] = sort(abs(coeff1), 'descend');
count = 0;
for i = 1:length(sorted_idx1)
    f_idx = sorted_idx1(i);
    if coeff1(f_idx) ~= 0 && count < 5
        feat_name = get_feature_name(f_idx, unique_networks);
        fprintf(fid, '   * %s: %.4f\n', feat_name, coeff1(f_idx));
        count = count + 1;
    end
end
fprintf(fid, '   -> PC1 represents a main dimension of individual variation. Subjects with high scores\n');
fprintf(fid, '      display increased coupling in positive loading edges, whereas subjects with negative\n');
fprintf(fid, '      scores show segregation or decoupling along these channels.\n\n');

% PC2 Loadings
fprintf(fid, 'PC 2 Geodesic Axis Loadings (Strongest sparse elements):\n');
coeff2 = pga_coeff(:, 2);
[~, sorted_idx2] = sort(abs(coeff2), 'descend');
count = 0;
for i = 1:length(sorted_idx2)
    f_idx = sorted_idx2(i);
    if coeff2(f_idx) ~= 0 && count < 5
        feat_name = get_feature_name(f_idx, unique_networks);
        fprintf(fid, '   * %s: %.4f\n', feat_name, coeff2(f_idx));
        count = count + 1;
    end
end
fprintf(fid, '   -> PC2 represents a secondary axis of individual variation, showing a trade-off\n');
fprintf(fid, '      between top-down cognitive sets and bottom-up sensory action readiness.\n\n');

fprintf(fid, '============================================================\n');
fclose(fid);
fprintf('Saved interpretation report to %s\n', interpretation_filename);

end

% --- HELPER FUNCTION FOR PGA FEATURES ---
function name = get_feature_name(f_idx, unique_networks)
    n_networks = length(unique_networks);
    if f_idx <= n_networks
        name = sprintf('%s (diag)', unique_networks{f_idx});
    else
        offset = f_idx - n_networks;
        idx = 1;
        for j = 1:n_networks
            for k = j+1:n_networks
                if idx == offset
                    name = sprintf('%s - %s', unique_networks{j}, unique_networks{k});
                    return;
                end
                idx = idx + 1;
            end
        end
    end
end
