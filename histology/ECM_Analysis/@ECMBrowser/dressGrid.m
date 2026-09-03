function [yLabels, xLabels] = dressGrid(obj, t, tiles, tileAx, nCols, mode, edgeLabels)
    %DRESSGRID Thin the tick labels over the grid and name its edges.
    % Both are decisions about where a tile sits rather than about what
    % it holds, so both are made here, after every tile has been drawn.
    % Anything that reaches this point is on a grid it was given rather
    % than a flow that chose its own, so the cell a tile sits in is
    % known rather than measured.

    yLabels = gobjects(1, 0);
    xLabels = gobjects(1, 0);

    if mode == "every axis" && ~edgeLabels
        return
    end

    rowOf = [tiles.Row];
    colOf = [tiles.Col];

    % Nothing is drawn to the left of these, and nothing below these.
    % Read from the tiles that exist rather than from the extent of the
    % grid, so that a combination the dataset never held cannot take the
    % numbers off the axis a reader is left looking at.
    n = numel(tiles);
    atLeft = arrayfun(@(i) colOf(i) == min(colOf(rowOf == rowOf(i))), 1:n);
    atBottom = arrayfun(@(i) rowOf(i) == max(rowOf(colOf == colOf(i))), 1:n);

    switch mode

        case "left and bottom axes"
            obj.hideTickLabels(tileAx(~atLeft), "y")
            obj.hideTickLabels(tileAx(~atBottom), "x")

        case "bottom left axis only"
            % The lowest of the tiles drawn furthest left, which is the
            % corner of the grid whenever the corner was drawn at all.
            inCorner = false(1, n);
            lowest = rowOf == max(rowOf);
            [~, corner] = min(colOf + (~lowest) * (max(colOf) + 1));
            inCorner(corner) = true;

            obj.hideTickLabels(tileAx(~inCorner), "xy")

    end

    if edgeLabels
        [yLabels, xLabels] = obj.labelGridEdges(t, tiles, tileAx, nCols);
    end

end
