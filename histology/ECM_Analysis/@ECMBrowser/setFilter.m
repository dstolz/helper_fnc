function setFilter(obj, field, values)
    %SETFILTER Keep only the sections whose FIELD holds one of VALUES.
    %   B.setFilter("Treatment", ["Vehicle" "GM6001"])
    %   B.setFilter()  restores every section
    %
    % The same thing the two filter controls do, reachable from a
    % script, because the view worth keeping is usually one that took
    % several clicks to reach.

    arguments
        obj
        field (1,1) string = obj.AllSections
        values (1,:) string = strings(1, 0)
    end

    if ~ismember(field, [obj.AllSections; obj.FilterFields])
        error("ECMBrowser:UnknownFilterField", ...
            "This dataset cannot be filtered by ""%s"".", field)
    end

    obj.FilterFieldDropDown.Value = field;
    obj.onFilterFieldChanged();

    if field == obj.AllSections || isempty(values)
        return
    end

    unknown = values(~ismember(values, string(obj.FilterValuesListBox.Items)));

    if ~isempty(unknown)
        error("ECMBrowser:UnknownFilterValue", ...
            "%s holds no value(s): %s", field, strjoin(unknown, ", "))
    end

    obj.FilterValuesListBox.Value = cellstr(values);
    obj.refresh();

end
