function resetGroupStyles(obj, field, level)
    %RESETGROUPSTYLES Put groups back to the colors the palette gave them.
    %   B.resetGroupStyles("Treatment", "GM6001")   one group
    %   B.resetGroupStyles("Treatment")             every group of a field
    %   B.resetGroupStyles()                        every group of every field
    %
    % Only what was chosen is forgotten. A field left out keeps what was
    % set up under it, which is the point of resetting one field rather
    % than all of them.

    arguments
        obj
        field (1,1) string = ""
        level (1,1) string = ""
    end

    if field == ""
        keys = string(obj.Styles.keys);
    elseif level == ""
        keys = string(obj.Styles.keys);
        keys = keys(startsWith(keys, field + "|"));
    else
        keys = string(obj.styleKey(field, level));
    end

    for k = 1:numel(keys)
        if isKey(obj.Styles, char(keys(k)))
            remove(obj.Styles, char(keys(k)));
        end
    end

    obj.applyStyles();

end
