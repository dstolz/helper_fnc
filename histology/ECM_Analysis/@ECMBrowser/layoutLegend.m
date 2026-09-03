function lgd = layoutLegend(obj, ax, groupField, groups, colors, groupOf, placement)
    %LAYOUTLEGEND One legend for the whole layout, outside every axes.
    % The entries are stand-ins drawn at NaN rather than the curves
    % themselves. A curve belongs to one tile and a group need not
    % appear in the first of them, so a legend built from whatever sits
    % under it would list only what that tile happened to hold; drawn
    % at NaN the stand-ins change no limit, and marked with their group
    % they follow a color picked from a right-click menu the way the
    % curves do.
    %
    % MATLAB places a legend outside a tiled layout by naming the side
    % it goes on, so the horizontal band lands between the layout title
    % and the top row of plots, and the column beside the right-hand
    % one. Either way the room every tile was spending on its own copy
    % of the key goes back to the plot.

    proxies = gobjects(1, numel(groups));
    onPeaks = string(obj.ShowDropDown.Value) == "peak summary";

    for k = 1:numel(groups)
        sty = obj.effectiveStyle(groupField, groups(k));
        label = obj.legendEntry(groups(k), nnz(groupOf == groups(k)));

        if onPeaks
            proxies(k) = scatter(ax, NaN, NaN, 42, sty.Color, "filled", ...
                MarkerFaceAlpha = 0.7, ...
                DisplayName = label);
            role = "marker";
        else
            proxies(k) = line(ax, NaN, NaN, ...
                Color = sty.Color, ...
                LineStyle = sty.LineStyle, ...
                LineWidth = 2, ...
                DisplayName = label);
            role = "line";
        end

        obj.markStyled(proxies(k), role, groupField, groups(k), colors(k, :));
    end

    lgd = legend(proxies);
    lgd.Interpreter = "none";

    if placement == "one at top"
        % Wrapped rather than run out in a single line, so a dozen
        % groups stay inside the figure instead of off the edge of it.
        lgd.NumColumns = min(numel(groups), 6);
        lgd.Layout.Tile = "north";
    else
        lgd.Orientation = "vertical";
        lgd.Layout.Tile = "east";
    end

end
