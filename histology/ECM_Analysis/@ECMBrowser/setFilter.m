function setFilter(obj, field, values, options)
    %SETFILTER Narrow FIELD to VALUES, beside whatever else is narrowed.
    %   B.setFilter("Treatment", ["Vehicle" "GM6001"])
    %   B.setFilter("Sex", "M")           now Treatment and Sex, both
    %   B.setFilter("Sex", "M", keep = false)   every section but the males
    %   B.setFilter(match = "any")        satisfy one condition, not all
    %   B.setFilter("Sex")                leave Sex unconstrained again
    %   B.setFilter()                     restore every section
    %
    % The same thing the filter controls do, reachable from a script,
    % because the view worth keeping is usually one that took several
    % clicks to reach.
    %
    % A field is narrowed once and conditions accumulate, so the second
    % call above leaves the first standing and the two are asked together:
    % every section whose treatment is one of the two named AND whose sex
    % is M. MATCH = "any" makes that an OR instead, and KEEP = false turns
    % one condition around without touching the rest. Pass REPLACE = true
    % to start from nothing rather than from what is already there.
    %
    % Naming a field with no values drops its condition; naming nothing at
    % all drops every condition. Either leaves MATCH where it was.
    %
    % See also SETTILING, SETCOMPARISON, SETNORMALIZATION.

    arguments
        obj
        field (1,1) string = ""
        values (1,:) string = strings(1, 0)
        options.keep (1,1) logical = true
        options.replace (1,1) logical = false
        options.match (1,1) string = ""
    end

    % Said in whichever words come to hand: the panel names the rule and
    % the operator together, and a script is as likely to reach for one
    % half as the other.
    if options.match ~= ""
        obj.FilterMatchDropDown.Value = matchRule(obj, options.match);
    end

    if options.replace
        obj.Filters(:) = [];
    end

    clearing = field == "" || field == obj.AllSections;

    % Naming no field is the request to drop every condition -- unless the
    % call was made to change the combining rule, or to clear the list
    % before setting a condition, which both name no field either.
    if clearing && ~options.replace && options.match == ""
        obj.Filters(:) = [];
        obj.FilterFieldDropDown.Value = obj.AllSections;
    end

    if ~clearing
        if ~ismember(field, obj.FilterFields)
            error("ECMBrowser:UnknownFilterField", ...
                "This dataset cannot be filtered by ""%s"".", field)
        end

        if isempty(values)
            obj.dropFilter(field);
        else
            levels = obj.levelsOf(field);
            unknown = values(~ismember(values, levels));

            if ~isempty(unknown)
                error("ECMBrowser:UnknownFilterValue", ...
                    "%s holds no value(s): %s", field, strjoin(unknown, ", "))
            end

            % Keeping every value narrows nothing, and is read as the
            % request to leave the field alone that it is, so that a loop
            % widening a field back out does not leave a condition behind
            % saying that everything is kept.
            if options.keep && numel(unique(values)) == numel(levels)
                obj.dropFilter(field);
            else
                obj.recordFilter(field, values, options.keep);
            end
        end

        obj.FilterFieldDropDown.Value = field;
    end

    % The editor is put onto whichever field was named so that the panel
    % shows the condition just set rather than the one before it, and the
    % list beside it is rebuilt whatever was changed.
    obj.onFilterFieldChanged(false);
    obj.refreshFilterList();
    obj.refresh();

end

function rule = matchRule(obj, asked)
    %MATCHRULE The combining rule ASKED for, however it was spelled.

    switch lower(asked)
        case {"all", "and", "all (and)"}
            rule = obj.FilterMatches(1);
        case {"any", "or", "any (or)"}
            rule = obj.FilterMatches(2);
        otherwise
            error("ECMBrowser:UnknownFilterMatch", ...
                "MATCH is ""all"" or ""any"", not ""%s"".", asked)
    end

end
