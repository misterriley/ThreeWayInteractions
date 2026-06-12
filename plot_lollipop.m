function plot_lollipop(vals, labels, title_str, xlabel_str, filename)
% PLOT_LOLLIPOP Generates a horizontal lollipop plot.
%
% Inputs:
%   vals       : vector of values to plot (length K)
%   labels     : cell array of strings for y-axis labels (length K)
%   title_str  : title of the plot
%   xlabel_str : label of the x-axis
%   filename   : full path where the plot image should be saved

    K = length(vals);
    if K == 0
        warning('No values provided for lollipop plot.');
        return;
    end
    
    fig_lollipop = figure('Visible', 'off');
    hold on;
    
    % Draw baseline at x = 0
    plot([0, 0], [0.5, K + 0.5], 'Color', [0.5, 0.5, 0.5], 'LineStyle', '--', 'LineWidth', 1);
    
    % Color palette for positive/negative connections
    pos_color = [0.85, 0.2, 0.2];  % Red
    neg_color = [0.15, 0.45, 0.75]; % Blue
    
    % Plot stems and circles
    for k = K:-1:1
        val = vals(k);
        y_pos = K + 1 - k;
        
        if val >= 0
            color = pos_color;
        else
            color = neg_color;
        end
        
        % Draw stem: horizontal line from 0 to val
        plot([0, val], [y_pos, y_pos], 'Color', color, 'LineWidth', 2.5);
        
        % Draw lollipop head
        plot(val, y_pos, 'o', 'MarkerSize', 10, 'MarkerFaceColor', color, 'MarkerEdgeColor', 'w', 'LineWidth', 1.5);
    end
    
    % Styling
    yticks(1:K);
    yticklabels(labels(K:-1:1));
    ylim([0.5, K + 0.5]);
    
    max_abs_val = max(abs(vals));
    if max_abs_val == 0
        max_abs_val = 1;
    end
    xlim([-max_abs_val - 0.05, max_abs_val + 0.05]);
    
    xlabel(xlabel_str);
    title(title_str);
    grid on;
    set(gca, 'GridColor', [0.9, 0.9, 0.9], 'Box', 'off', 'TickLabelInterpreter', 'none');
    
    exportgraphics(fig_lollipop, filename, 'Resolution', 300);
    close(fig_lollipop);
end
