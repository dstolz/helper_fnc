function [tiles, tileOf, nCols] = tiling(obj, fields, idx)
    %TILING The axes the Tile by selection asks for, and the one each
    %section belongs in.
    % TILES is one entry per cell that holds sections, in the order they
    % are drawn, carrying the cell it goes in, the row and column that
    % cell sits at, the title it wears and the row and column values it
    % stands for; TILEOF says which cell each section in view fell into,
    % counted across a grid NCOLS wide. A cell no section landed in is
    % left out, so a combination the dataset never held costs nothing
    % but the gap it leaves in the grid.

    nSections = numel(idx);
    blank = struct("Index", 0, "Row", 0, "Col", 0, ...
        "Label", "", "RowLabel", "", "ColLabel", "");

    if isempty(fields)
        tiles = blank;
        tiles.Index = 1;
        tiles.Row = 1;
        tiles.Col = 1;
        tileOf = ones(nSections, 1);
        nCols = 1;
        return
    end

    % Sections are ranked within each field's own level order rather
    % than sorted on their text, so the tiles come out in the order the
    % levels are drawn in -- plate 5 before plate 27 -- and one UNIQUE
    % over the ranks orders the combinations by the leading field first.
    ranks = zeros(nSections, numel(fields));
    levels = cell(1, numel(fields));

    for iField = 1:numel(fields)
        levels{iField} = obj.viewLevelsOf(fields(iField));
        [~, ranks(:, iField)] = ismember( ...
            obj.View.Text.(fields(iField))(idx), levels{iField});
    end

    % The last field's levels and the combinations of the fields
    % before it are worked out the same way either way; Transpose
    % decides only which of the two runs across the grid.
    [lastRanks, ~, lastOf] = unique(ranks(:, end));

    if isscalar(fields)
        leadRanks = zeros(1, 0);
        leadOf = ones(nSections, 1);
    else
        [leadRanks, ~, leadOf] = unique(ranks(:, 1:end-1), "rows");
    end

    transposed = obj.TransposeCheckBox.Value;

    if transposed
        [rowOf, colOf] = deal(lastOf, leadOf);
        nCols = max(leadOf);
    else
        [rowOf, colOf] = deal(leadOf, lastOf);
        nCols = numel(lastRanks);
    end

    tileOf = (rowOf - 1) * nCols + colOf;

    occupied = unique(tileOf);
    tiles = repmat(blank, numel(occupied), 1);

    for iTile = 1:numel(occupied)
        iCol = mod(occupied(iTile) - 1, nCols) + 1;
        iRow = (occupied(iTile) - iCol) / nCols + 1;

        if transposed
            [iLead, iLast] = deal(iCol, iRow);
        else
            [iLead, iLast] = deal(iRow, iCol);
        end

        values = strings(1, numel(fields));
        values(end) = levels{end}(lastRanks(iLast));

        for iField = 1:numel(fields) - 1
            values(iField) = levels{iField}(leadRanks(iLead, iField));
        end

        tiles(iTile).Index = occupied(iTile);
        tiles(iTile).Row = iRow;
        tiles(iTile).Col = iCol;

        % One value belongs to every tile in its column and the other
        % to every tile in its row, which is what lets the grid wear
        % them on its edges instead of in every title. Transpose says
        % which of the two goes on which edge.
        leadLabel = "";

        if ~isscalar(fields)
            leadLabel = strjoin(values(1:end-1), " | ");
        end

        if transposed
            tiles(iTile).RowLabel = values(end);
            tiles(iTile).ColLabel = leadLabel;
        else
            tiles(iTile).RowLabel = leadLabel;
            tiles(iTile).ColLabel = values(end);
        end

        % One field names itself in every title, the way it always has.
        % Several would spend the whole title on field names that do not
        % change from tile to tile, so the values go up alone and the
        % layout's subtitle says which order they are in.
        if isscalar(fields)
            tiles(iTile).Label = fields(1) + " " + values(1);
        else
            tiles(iTile).Label = strjoin(values, " | ");
        end
    end

end
