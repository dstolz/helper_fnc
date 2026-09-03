function indexFields(obj)
    %INDEXFIELDS Take a string view of every field worth selecting on.
    % One pass up front, so grouping, tiling, and filtering all compare
    % the same text and a numeric plate reads the same everywhere it
    % appears.

    varNames = string(obj.Files.Properties.VariableNames);

    for iVar = 1:numel(varNames)
        col = obj.Files.(varNames(iVar));

        if size(col, 2) ~= 1 || iscell(col)
            continue
        end

        txt = string(col);
        txt(ismissing(txt)) = "n/a";

        nLevels = numel(unique(txt));

        if nLevels < 2 || nLevels > obj.MaxFilterLevels
            continue
        end

        % Text that takes a different value in every section is an
        % identifier and is worth filtering on; a number that does is a
        % measurement of the section, and singling one out by its peak
        % height is not something anyone reaches for.
        if nLevels > obj.MaxGroupLevels && ~isstring(col) && ~iscategorical(col)
            continue
        end

        obj.Text.(varNames(iVar)) = txt;
        obj.FilterFields(end+1, 1) = varNames(iVar);

        if nLevels <= obj.MaxGroupLevels
            obj.GroupFields(end+1, 1) = varNames(iVar);
        end
    end

    if ismember("PixelUnit", varNames)
        obj.Unit = obj.Files.PixelUnit(1);
    end

    % Offered alphabetically rather than in the table's own column
    % order, so a field is found by name instead of by where it
    % happens to sit in the sheet.
    obj.GroupFields = sort(obj.GroupFields);
    obj.FilterFields = sort(obj.FilterFields);

end
