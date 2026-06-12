function h = plot_masked_carpet(A, labels, title_str, filename, cmap, clim_range, highlight_top_10, ax)
% PLOT_MASKED_CARPET Plots a lower-triangular masked carpet/matrix plot.
%
% Inputs:
%   A                : square matrix to plot
%   labels           : cell array of strings for ticks (length N, optional)
%   title_str        : title of the plot (optional)
%   filename         : output PNG path (optional; exports and closes figure if provided)
%   cmap             : colormap matrix
%   clim_range       : color limits [min max]
%   highlight_top_10 : boolean to highlight top 10 absolute off-diagonal values (default: false)
%   ax               : target axes object (optional; uses current axes/figure if empty)

    if nargin < 7 || isempty(highlight_top_10)
        highlight_top_10 = false;
    end
    if nargin < 8
        ax = [];
    end
    
    N = size(A, 1);
    
    % Mask upper triangle and diagonal (only keep bottom triangle)
    mask = tril(true(N), -1);
    A_masked = A;
    A_masked(~mask) = NaN;
    
    if isempty(ax)
        if ~isempty(filename)
            fig = figure('Visible', 'off');
        else
            fig = gcf;
        end
        ax = gca;
    else
        % Find parent figure of ax
        fig = ancestor(ax, 'figure');
    end
    
    h = imagesc(ax, A_masked);
    set(h, 'AlphaData', ~isnan(A_masked));
    axis(ax, 'square');
    colormap(ax, cmap);
    clim(ax, clim_range);
    
    if ~isempty(filename)
        colorbar(ax);
    end
    
    if ~isempty(title_str)
        title(ax, title_str, 'Interpreter', 'none');
    end
    
    % Set axis labels and ticks
    xticks(ax, 1:N);
    yticks(ax, 1:N);
    if ~isempty(labels)
        xticklabels(ax, labels);
        yticklabels(ax, labels);
    else
        xticklabels(ax, []);
        yticklabels(ax, []);
    end
    xlabel(ax, 'Canonical Network');
    ylabel(ax, 'Canonical Network');
    set(ax, 'TickLabelInterpreter', 'none', 'FontSize', 9);
    
    % Draw black staircase outline around the lower triangle
    hold(ax, 'on');
    x_coords = [0.5, 0.5, N - 0.5];
    y_coords = [1.5, N + 0.5, N + 0.5];
    for r = N:-1:2
        x_coords = [x_coords, r - 0.5, r - 1.5];
        y_coords = [y_coords, r - 0.5, r - 0.5];
    end
    plot(ax, x_coords, y_coords, 'k-', 'LineWidth', 2);
    
    % Highlight top 10 absolute values if requested
    if highlight_top_10
        abs_A = abs(A);
        abs_A(~mask) = -inf; % search only lower triangle
        [~, sort_idx] = sort(abs_A(:), 'descend');
        n_highlight = min(10, sum(mask(:)));
        top_idx = sort_idx(1:n_highlight);
        [r_coords, c_coords] = ind2sub([N, N], top_idx);
        for k = 1:length(top_idx)
            rectangle(ax, 'Position', [c_coords(k) - 0.5, r_coords(k) - 0.5, 1, 1], ...
                      'EdgeColor', 'g', 'LineWidth', 2);
        end
    end
    
    hold(ax, 'off');
    
    if ~isempty(filename) && ~isempty(fig)
        exportgraphics(fig, filename, 'Resolution', 300);
        close(fig);
    end
end
