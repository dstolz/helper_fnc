function setComparison(obj, op, field, options)
    %SETCOMPARISON Measure one value of a field against another.
    %   B.setComparison("difference", "Hemisphere")
    %   B.setComparison("log2 ratio", "Hemisphere", reference = "Left")
    %   B.setComparison("difference", "Treatment", ...
    %       reference = "Vehicle", within = ["SubjectID" "AtlasPlate"])
    %   B.setComparison("difference", "SubjectID", ...
    %       reference = "(each vs. the rest)", within = "AtlasPlate")
    %   B.setComparison()  draws the sections themselves again
    %
    % The operation, what it is taken across, which value it is taken
    % against, and what has to match for two sections to be compared
    % are one decision in four parts, so they are set in one call. The
    % reference defaults to the first of the field's values and the
    % matching to whatever Pair within is already showing; a field
    % with no natural reference takes "(each vs. the rest)" or
    % "(every pair)" in place of one of its values.

    arguments
        obj
        op (1,1) string = "none"
        field (1,1) string = obj.NoField
        options.reference (1,1) string = ""
        options.within (1,:) string = string(obj.PairListBox.Value)
    end

    if ~ismember(op, obj.CompareOps)
        error("ECMBrowser:UnknownComparison", ...
            "The comparison must be one of: %s", strjoin(obj.CompareOps, ", "))
    end

    if ~ismember(field, [obj.NoField; obj.GroupFields])
        error("ECMBrowser:UnknownCompareField", ...
            "This dataset cannot be compared by ""%s"".", field)
    end

    unknown = options.within(~ismember(options.within, ...
        [obj.NoField; obj.FilterFields]));

    if ~isempty(unknown)
        error("ECMBrowser:UnknownPairField", ...
            "Sections cannot be paired within: %s", strjoin(unknown, ", "))
    end

    obj.CompareDropDown.Value = op;
    obj.CompareFieldDropDown.Value = field;
    obj.onCompareFieldChanged(false);

    if options.reference ~= ""
        if ~ismember(options.reference, string(obj.CompareRefDropDown.Items))
            error("ECMBrowser:UnknownReferenceLevel", ...
                "%s holds no value ""%s"".", field, options.reference)
        end

        obj.CompareRefDropDown.Value = options.reference;
    end

    within = options.within(options.within ~= obj.NoField);

    if isempty(within)
        within = obj.NoField;
    end

    obj.PairListBox.Value = cellstr(within);
    obj.refresh();

end
