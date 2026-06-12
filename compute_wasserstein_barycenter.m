function [barycenter, converged, iter, diff] = compute_wasserstein_barycenter(fc_matrices, max_iter, tol, S_init)
% COMPUTE_WASSERSTEIN_BARYCENTER Computes Bures-Wasserstein barycenter of FC matrices.
%
% Inputs:
%   fc_matrices : 3D array of size [n_networks, n_networks, n_subs]
%   max_iter    : maximum number of iterations (default: 100)
%   tol         : convergence tolerance (default: 1e-6)
%   S_init      : initial matrix [n_networks, n_networks] (default: arithmetic mean)
%
% Outputs:
%   barycenter  : estimated barycenter matrix
%   converged   : boolean indicating if algorithm converged
%   iter        : number of iterations actually performed
%   diff        : relative change in Frobenius norm at final step

    if nargin < 2 || isempty(max_iter)
        max_iter = 100;
    end
    if nargin < 3 || isempty(tol)
        tol = 1e-6;
    end
    
    [n_networks, ~, n_subs] = size(fc_matrices);
    
    if nargin < 4 || isempty(S_init)
        S_init = mean(fc_matrices, 3);
    end
    
    S = S_init;
    S = S + 1e-9 * eye(n_networks); % Regularize slightly to ensure strict positive definiteness
    
    converged = false;
    diff = Inf;
    for iter = 1:max_iter
        % Compute square root of S and its inverse
        [V, D] = eig(S);
        d_val = diag(D);
        d_val(d_val < 0) = 0; % Clip negative eigenvalues to avoid complex numbers
        sqrtS = V * diag(sqrt(d_val)) * V';
        invSqrtS = V * diag(1 ./ (sqrt(d_val) + 1e-9)) * V';
        
        % Sum of (sqrtS * C_i * sqrtS)^(1/2)
        M = zeros(n_networks, n_networks);
        for i = 1:n_subs
            C_i = fc_matrices(:,:,i);
            inner = sqrtS * C_i * sqrtS;
            
            % Symmetrize to prevent numerical asymmetry
            inner_sym = (inner + inner') / 2;
            [V_in, D_in] = eig(inner_sym);
            d_in = diag(D_in);
            d_in(d_in < 0) = 0;
            sqrt_inner = V_in * diag(sqrt(d_in)) * V_in';
            
            % If M contains NaNs, set S_new to S and break to prevent cascading NaNs
            if any(isnan(sqrt_inner), 'all')
                warning('NaN encountered during Bures-Wasserstein calculation. Check if subject count is zero.');
                converged = false;
                break;
            end
            
            M = M + (1/n_subs) * sqrt_inner;
        end
        
        if any(isnan(M), 'all')
            break;
        end
        
        % Update: S_new = invSqrtS * M^2 * invSqrtS
        S_new = invSqrtS * (M * M) * invSqrtS;
        S_new = (S_new + S_new') / 2; % Symmetrize
        
        % Check relative change in Frobenius norm
        diff = norm(S_new - S, 'fro') / norm(S, 'fro');
        if diff < tol
            S = S_new;
            converged = true;
            break;
        end
        S = S_new;
    end
    
    barycenter = S;
end
