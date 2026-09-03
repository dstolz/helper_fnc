function T = viewTable(obj, layout)
    %VIEWTABLE The current view as one table, in the layout asked for.
    % The three tables SAVEDATA writes, built here rather than there so
    % that the clipboard and the file are handed the same one.

    v = obj.viewData();

    if v.unit == "" || ismissing(v.unit)
        depthName = "Depth";
    else
        depthName = "Depth_" + v.unit;
    end

    depthName = string(matlab.lang.makeValidName(depthName));

    switch layout

        case "wide"
            T = array2table(v.values, VariableNames = cellstr(v.sectionNames));
            T = addvars(T, v.depth, Before = 1, NewVariableNames = depthName);

        case "long"
            nDepth = numel(v.depth);
            nSection = numel(v.sectionNames);

            T = table(repmat(v.depth, nSection, 1), ...
                repelem(v.sectionNames(:), nDepth, 1), ...
                v.values(:), ...
                VariableNames = [depthName, "Section", "Value"]);

            % Every field the sections can be grouped or filtered by,
            % so the rows carry what the plot was split on and nothing
            % has to be joined back to A.grid.files to ask a question
            % of them.
            fields = string(fieldnames(obj.View.Text));

            for iField = 1:numel(fields)
                if ismember(fields(iField), string(T.Properties.VariableNames))
                    continue
                end

                T.(fields(iField)) = ...
                    repelem(obj.View.Text.(fields(iField))(v.rows), nDepth, 1);
            end

            % A section is interpolated onto the shared depth axis and
            % holds nothing outside the depths it measured, which in a
            % row-per-sample table is a row with no measurement in it.
            T(~isfinite(T.Value), :) = [];

        case "sections"
            T = writable_columns(v.sections);

            % The peak on the scale the profiles beside it are drawn
            % on, which is the one thing this table does not already
            % hold: PeakY is in the units it was measured in. A
            % comparison is read off the drawn profiles to begin with,
            % so its PeakY is already that number and adding a second
            % copy of it under another name would only invite the
            % question of how the two differ.
            if v.comparison == ""
                T.PeakY_drawn = v.peakHeight;
            end

            named = matlab.lang.makeUniqueStrings( ...
                ["Section", string(T.Properties.VariableNames)], 1);
            T = addvars(T, v.sectionNames(:), Before = 1, ...
                NewVariableNames = named(1));
    end

end
