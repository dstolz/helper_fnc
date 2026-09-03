function [yLabels, xLabels] = labelGridEdges(obj, t, tiles, tileAx, nCols)
    %LABELGRIDEDGES Hang the row and column values off the grid's edges.
    % Every row name goes in one column of the grid and every column
    % name in one row of it, so the names line up down the left of the
    % figure and along the bottom of it rather than following whichever
    % tile of a row happens to have been drawn furthest left.

    leftCol = min([tiles.Col]);
    bottomRow = max([tiles.Row]);

    yLabels = gobjects(1, 0);
    xLabels = gobjects(1, 0);

    for iRow = unique([tiles.Row])
        ax = obj.edgeAxes(t, tiles, tileAx, iRow, leftCol, nCols);
        first = find([tiles.Row] == iRow, 1);

        ylabel(ax, tiles(first).RowLabel, Interpreter = "none", FontWeight = "bold")
        yLabels(end+1) = ax.YLabel; %#ok<AGROW>
    end

    for iCol = unique([tiles.Col])
        ax = obj.edgeAxes(t, tiles, tileAx, bottomRow, iCol, nCols);
        first = find([tiles.Col] == iCol, 1);

        xlabel(ax, tiles(first).ColLabel, Interpreter = "none", FontWeight = "bold")
        xLabels(end+1) = ax.XLabel; %#ok<AGROW>
    end

    % A blank cell has none of the axis color a name is otherwise
    % painted in, so every name is given the color an axis label wears
    % by default and one on a blank cell cannot come out any different
    % from the rest.
    set([yLabels xLabels], 'Color', obj.LabelColor)

end
