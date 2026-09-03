function setTiling(obj, fields)
    %SETTILING Give every combination of FIELDS its own axes.
    %   B.setTiling("AtlasPlate")
    %   B.setTiling(["AtlasPlate" "SubjectID"])
    %   B.setTiling()  draws everything into one axes
    %
    % Which field ends up down the rows and which across the columns is
    % the order the Tile by list offers them in rather than the order
    % given here, because the list is what the next click will change.

    arguments
        obj
        fields (1,:) string = strings(1, 0)
    end

    unknown = fields(~ismember(fields, obj.GroupFields));

    if ~isempty(unknown)
        error("ECMBrowser:UnknownTileField", ...
            "This dataset cannot be tiled by: %s", strjoin(unknown, ", "))
    end

    if isempty(fields)
        obj.TileListBox.Value = cellstr(obj.NoField);
    else
        obj.TileListBox.Value = cellstr(fields);
    end

    obj.refresh();

end
