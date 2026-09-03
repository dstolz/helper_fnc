function draw(obj, parent)
    %DRAW Build one tiled layout of the sections now in view.

    [idx, Y, x] = obj.currentView();

    % The right-click menus hang off the figure rather than off the
    % panel the plot goes into, so the ones the last draw built outlive
    % the redraw that replaced their plot and are cleared here instead.
    fig = ancestor(parent, 'figure');
    delete(findall(fig, 'Type', 'uicontextmenu', 'Tag', char(obj.MenuTag)))

    if isprop(parent, 'ContextMenu')
        parent.ContextMenu = [];
    end

    if isempty(idx)
        % A comparison that came out empty is a different problem from
        % a filter that did, and is fixed by a different control: no
        % match held both the reference value and something to measure
        % against it, which usually means Pair within is asking more
        % of a match than the dataset holds.
        if obj.View.Comparison == ""
            nothing = "No sections match the current filter.";
        else
            nothing = "Nothing to compare: no match holds " + ...
                obj.CompareFieldDropDown.Value + " " + ...
                obj.CompareRefDropDown.Value + " alongside another value.";
        end

        obj.setStatus(nothing);
        uilabel(parent, Text = nothing, WordWrap = "on", ...
            Position = [20 20 400 60]);
        return
    end

    tileBy = obj.tileFields();
    groupField = string(obj.GroupDropDown.Value);

    [tiles, tileOf, nCols] = obj.tiling(tileBy, idx);
    [groups, groupOf] = obj.splitBy(groupField, idx);

    % Several fields tiled together can call for more axes than there is
    % screen to draw them in, so the ones past the cap are left off and
    % reported rather than spending a minute on a wall of empty boxes.
    nWanted = numel(tiles);
    tiles = tiles(1:min(nWanted, obj.MaxTiles));
    nRows = ceil(tiles(end).Index / nCols);

    colors = lines(max(numel(groups), 7));
    obj.rememberDefaults(groupField, groups, colors);

    % One menu per group for the artists that draw it, and one listing
    % every group for the axes behind them, which is what a right-click
    % that misses a curve finds.
    [axesMenu, groupMenus] = obj.buildStyleMenus(fig, groupField, groups);

    if isprop(parent, 'ContextMenu')
        parent.ContextMenu = axesMenu;
    end

    % A single split wraps into a flow the way it always has; a split of
    % two or more fields is placed on the grid its combinations came out
    % on, empty cells and all, which is what makes one column comparable
    % from row to row. Two fields that happen to fill one row are gridded
    % too rather than flowed, because a flow is free to wrap and the
    % edge labels below can only be trusted on a grid.
    onGrid = nRows > 1 || numel(tileBy) > 1;
    tickMode = string(obj.TickLabelDropDown.Value);

    % A flow picks its own wrap, and picks it again whenever the room
    % it has to fill changes -- taking the numbers off an axis is
    % enough to change it, which would leave the numbers on a diagonal
    % of tiles that were at the edges before they were thinned. So a
    % plot that has to know which tile sits at an edge is wrapped onto
    % a grid of its own, at the squarest shape the tiles fit into.
    if ~onGrid && tickMode ~= "every axis"
        nCols = ceil(sqrt(numel(tiles)));
        nRows = ceil(numel(tiles) / nCols);
        onGrid = true;

        for iTile = 1:numel(tiles)
            tiles(iTile).Col = mod(tiles(iTile).Index - 1, nCols) + 1;
            tiles(iTile).Row = (tiles(iTile).Index - tiles(iTile).Col) / nCols + 1;
        end
    end

    spacing = string(obj.SpacingDropDown.Value);
    padding = string(obj.PaddingDropDown.Value);

    if onGrid
        t = tiledlayout(parent, nRows, nCols, ...
            TileSpacing = spacing, Padding = padding);
    else
        t = tiledlayout(parent, "flow", TileSpacing = spacing, Padding = padding);
    end

    % One field says which value a tile holds in the tile's own title.
    % Two or more put the row's value down the left edge of the grid
    % and the column's along the bottom, said once each instead of
    % repeated in every title, so a row reads as one level of the first
    % field and a column as one level of the last.
    edgeLabels = onGrid && numel(tileBy) > 1;

    placement = string(obj.LegendDropDown.Value);
    firstAx = matlab.graphics.axis.Axes.empty;

    % The axes each tile was drawn into, kept so that the pass over the
    % grid below can find them again by the cell they sit in.
    tileAx = gobjects(1, numel(tiles));

    for iTile = 1:numel(tiles)
        if onGrid
            ax = nexttile(t, tiles(iTile).Index);
        else
            ax = nexttile(t);
        end

        tileAx(iTile) = ax;

        if iTile == 1
            firstAx = ax;
        end

        hold(ax, "on")
        ax.ContextMenu = axesMenu;

        inTile = find(tileOf == tiles(iTile).Index);

        for iGroup = 1:numel(groups)
            cols = inTile(groupOf(inTile) == groups(iGroup));

            if isempty(cols)
                continue
            end

            artists = obj.drawGroup(ax, x, Y, idx, cols, ...
                groupField, groups(iGroup), colors(iGroup, :));

            set(artists, 'ContextMenu', groupMenus(char(groups(iGroup))))
        end

        % Two or more fields name themselves on the edges of the
        % grid instead, once the whole grid has been drawn.
        if ~edgeLabels && tiles(iTile).Label ~= ""
            title(ax, tiles(iTile).Label, Interpreter = "none")
        end

        grid(ax, "on")
        box(ax, "on")
        axis(ax, "tight")

        if placement == "per tile" && numel(groups) > 1
            legend(ax, Interpreter = "none", Location = "best")
        end
    end

    % One legend for the layout is built after the tiles rather than
    % inside the loop, because it stands for every group in view rather
    % than for the ones one tile happens to hold.
    if ismember(placement, ["one at top", "one at right"]) && numel(groups) > 1
        drawn = ismember(tileOf, [tiles.Index]);
        obj.layoutLegend(firstAx, groupField, groups, colors, ...
            groupOf(drawn), placement);
    end

    if obj.LinkCheckBox.Value
        axesHandles = findobj(t, "Type", "axes");

        if numel(axesHandles) > 1
            linkaxes(axesHandles)
        end
    end

    % Last of all, once every tile holds what it is going to hold and
    % the linking has settled the limits they share: the numbers are
    % thinned to the edges of the grid if that is what was asked for,
    % and the row and column names are hung off those same edges.
    [yLabels, xLabels] = obj.dressGrid(t, tiles, tileAx, nCols, tickMode, edgeLabels);

    % The quantities go on after the edges have been named, not before.
    % The layout places its own names clear of whatever the axes inside
    % it are already wearing, so it has to be told them once the edges
    % are wearing theirs or it puts "intensity" straight through a
    % row's name.
    obj.labelLayout(t, groupField, tileBy, numel(tiles), edgeLabels);

    % And the names are lined up last of all. Every step above moves
    % the axes about -- a name added to the layout takes room from
    % them -- and an offset measured before the layout has settled is
    % measured against a tile that is about to change size.
    obj.alignLabels(yLabels, 1)
    obj.alignLabels(xLabels, 2)

    obj.setStatus(sprintf("%s | %s | %d group(s)%s%s%s", ...
        obj.countNote(numel(idx)), tile_note(numel(tiles), nWanted), ...
        numel(groups), obj.normNote(), obj.compareNote(), obj.skippedNote()));

end
