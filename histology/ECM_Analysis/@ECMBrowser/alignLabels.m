function alignLabels(~, labels, dim)
    %ALIGNLABELS Put every label at the offset of the one furthest out.
    % Every tile is the same size, so one offset measured against the
    % tile it is on is the same place on the figure for all of them.

    if numel(labels) < 2
        return
    end

    set(labels, 'Units', 'normalized')

    % Read only once the layout has stopped moving. Taking the numbers
    % off an axis changes how wide it can be, the layout answers by
    % resizing every tile, and it does not always finish inside one
    % DRAWNOW: an offset read before it settles belongs to a tile that
    % is about to change width, and pinning a name at that offset puts
    % it somewhere no tile ever was.
    settled = [];

    for pass = 1:4
        drawnow

        % DRAWNOW hands control to any callback a control fired while
        % this one was running, and REFRESH's reentrancy guard defers
        % most of those -- but a labels array built for a panel that
        % gets torn down some other way (the browser closing mid-draw)
        % is left with nothing worth aligning rather than crashed on.
        if ~all(isvalid(labels))
            return
        end

        offsets = arrayfun(@(h) h.Position(dim), labels);

        if isequal(offsets, settled)
            break
        end

        settled = offsets;
    end

    % The one furthest out is left exactly where it was found, and it
    % is the reason the rest can be moved at all: a name placed by hand
    % stops counting toward the room the layout keeps clear for its own
    % names, and were this one moved too, that room would close up and
    % "intensity" would be drawn straight through the names.
    [furthest, keep] = min(settled);

    for iLabel = 1:numel(labels)

        if iLabel == keep
            continue
        end

        position = labels(iLabel).Position;
        position(dim) = furthest;
        labels(iLabel).Position = position;
    end

end
