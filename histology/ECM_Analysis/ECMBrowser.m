classdef ECMBrowser < handle
%ECMBROWSER Browse the profiles ecm_prepare_analysis_data produced.
%   B = ECMBrowser(A)
%
% A is the struct returned by ECM_PREPARE_ANALYSIS_DATA. Everything drawn
% comes from A.grid -- one column per section on a shared depth axis -- and
% A.grid.files, the section table beside it, which supplies every field the
% profiles can be coloured, tiled, and filtered by.
%
% Working off the grid rather than the point-level table is what keeps this
% simple: sections are already on one depth axis, so a group mean is a mean
% across columns rather than a regrouping, and any field of the section table
% can group or tile without recomputing anything.
%
% The controls are, in order:
%   Signal      Smoothed or raw intensity.
%   Show        Every section, the group mean with an error band, or one point
%               per section in peak depth / peak intensity.
%   Error band  What the band around a group mean spans.
%   Colour by   Field whose values become the groups. Legend entries are per
%               group, not per section, so a plot of 85 sections still has a
%               legend that fits.
%   Tile by     Field whose values each get their own axes.
%   Filter      One field, and which of its values to keep.
%   Depth       The depth window drawn, in the profiles' own distance unit.
%
% Fields are offered for grouping and tiling when they take between 2 and 25
% distinct values, and as filters when they take up to 100. A section
% identifier is therefore something to filter one section out by but not to
% group on, a measurement of the section is neither, and a field that holds
% the same value throughout is left out of all three.
%
% See also ECM_PREPARE_ANALYSIS_DATA, LAUNCH_ECM_BROWSER, HISTOLOGYIMAGEBROWSER.

    properties (SetAccess = private)
        Data struct                     % The analysis struct being browsed.
        Files table                     % A.grid.files, one row per section.
        Text struct = struct()          % String view of every candidate field.
        GroupFields string = strings(0,1)
        FilterFields string = strings(0,1)
        Unit string = ""
    end

    properties (SetAccess = private)
        % The controls, readable so that a script can set one and call REFRESH.
        Fig matlab.ui.Figure
        PlotPanel matlab.ui.container.Panel
        SignalDropDown matlab.ui.control.DropDown
        ShowDropDown matlab.ui.control.DropDown
        ErrorDropDown matlab.ui.control.DropDown
        SectionsCheckBox matlab.ui.control.CheckBox
        GroupDropDown matlab.ui.control.DropDown
        TileDropDown matlab.ui.control.DropDown
        FilterFieldDropDown matlab.ui.control.DropDown
        FilterValuesListBox matlab.ui.control.ListBox
        DepthMinField matlab.ui.control.NumericEditField
        DepthMaxField matlab.ui.control.NumericEditField
        LegendCheckBox matlab.ui.control.CheckBox
        LinkCheckBox matlab.ui.control.CheckBox
        StatusLabel matlab.ui.control.Label
    end

    properties (Constant, Access = private)
        NoField = "(none)"
        AllSections = "(all sections)"
        MaxGroupLevels = 25
        MaxFilterLevels = 100
    end

    methods

        function obj = ECMBrowser(A)

            arguments
                A struct
            end

            obj.Data = validate_analysis(A);
            obj.Files = obj.Data.grid.files;
            obj.indexFields();
            obj.buildUI();
            obj.refresh();

            if nargout == 0
                clear obj
            end

        end

        function refresh(obj)
            %REFRESH Redraw the panel from the current control state.
            % Public, so a control can be set from the command line or a test
            % and the view brought up to date without reaching inside.

            % A control that cannot affect the current view is greyed out
            % rather than left to be tried: the peak summary is one point per
            % section taken from A.peaks, so neither the signal nor the depth
            % window reaches it.
            show = string(obj.ShowDropDown.Value);

            obj.ErrorDropDown.Enable = matlab.lang.OnOffSwitchState(show == "group mean");
            obj.SectionsCheckBox.Enable = obj.ErrorDropDown.Enable;

            onProfiles = matlab.lang.OnOffSwitchState(show ~= "peak summary");
            obj.SignalDropDown.Enable = onProfiles;
            obj.DepthMinField.Enable = onProfiles;
            obj.DepthMaxField.Enable = onProfiles;

            delete(obj.PlotPanel.Children);
            obj.draw(obj.PlotPanel);

        end

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

        function f = popOut(obj)
            %POPOUT Draw the current view into an ordinary figure.
            % A uifigure cannot be saved as a .fig or handed to EXPORTGRAPHICS
            % the way a plain figure can, and the current view is the only
            % thing here anyone is likely to want to keep.

            f = figure(Name = "ECM Browser", NumberTitle = "off", Color = "w");
            obj.draw(f);

            if nargout == 0
                clear f
            end

        end

    end

    methods (Access = private)

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

        end

        function levels = levelsOf(obj, field)
            %LEVELSOF List one field's values in the order they should be drawn.
            % Numbers sort as numbers, so plate 5 comes before plate 27 rather
            % than after it.

            levels = unique(obj.Text.(field));

            asNumber = double(levels);

            if ~any(isnan(asNumber))
                [~, order] = sort(asNumber);
                levels = levels(order);
            end

        end

        function buildUI(obj)
            %BUILDUI Lay out the controls beside the plot.

            obj.Fig = uifigure(Name = "ECM Browser", Position = [80 80 1280 780]);

            layout = uigridlayout(obj.Fig, [1 2]);
            layout.ColumnWidth = {270, '1x'};
            layout.RowHeight = {'1x'};

            controls = uipanel(layout, Title = "Display");
            obj.PlotPanel = uipanel(layout, BorderType = "none");

            grid = uigridlayout(controls, [16 2]);
            grid.ColumnWidth = {90, '1x'};
            grid.RowHeight = [repmat({24}, 1, 7), {'1x'}, repmat({24}, 1, 7), {40}];
            grid.RowSpacing = 6;

            obj.SignalDropDown = obj.addRow(grid, "Signal", ...
                @() uidropdown(grid, Items = ["smoothed", "raw"]));

            obj.ShowDropDown = obj.addRow(grid, "Show", ...
                @() uidropdown(grid, Items = ["sections", "group mean", "peak summary"]));

            obj.ErrorDropDown = obj.addRow(grid, "Error band", ...
                @() uidropdown(grid, Items = ["sem", "std", "ci95", "none"]));

            obj.SectionsCheckBox = uicheckbox(grid, ...
                Text = "Sections behind the mean", ...
                Value = true, ...
                ValueChangedFcn = @(~,~) obj.refresh());
            obj.SectionsCheckBox.Layout.Column = [1 2];

            obj.GroupDropDown = obj.addRow(grid, "Colour by", ...
                @() uidropdown(grid, Items = [obj.NoField; obj.GroupFields]));

            obj.TileDropDown = obj.addRow(grid, "Tile by", ...
                @() uidropdown(grid, Items = [obj.NoField; obj.GroupFields]));

            obj.FilterFieldDropDown = obj.addRow(grid, "Filter by", ...
                @() uidropdown(grid, Items = [obj.AllSections; obj.FilterFields]), ...
                @(~,~) obj.onFilterFieldChanged());

            obj.FilterValuesListBox = uilistbox(grid, ...
                Items = {}, ...
                Multiselect = "on", ...
                ValueChangedFcn = @(~,~) obj.refresh());
            obj.FilterValuesListBox.Layout.Column = [1 2];

            depth = obj.Data.grid.depth;

            obj.DepthMinField = obj.addRow(grid, "Depth min", ...
                @() uieditfield(grid, "numeric", Value = floor(min(depth))));

            obj.DepthMaxField = obj.addRow(grid, "Depth max", ...
                @() uieditfield(grid, "numeric", Value = ceil(max(depth))));

            obj.LegendCheckBox = uicheckbox(grid, Text = "Legend", Value = true, ...
                ValueChangedFcn = @(~,~) obj.refresh());
            obj.LinkCheckBox = uicheckbox(grid, Text = "Link axes", Value = true, ...
                ValueChangedFcn = @(~,~) obj.refresh());

            uibutton(grid, Text = "Reset", ButtonPushedFcn = @(~,~) obj.onReset());
            uibutton(grid, Text = "Pop out", ButtonPushedFcn = @(~,~) obj.popOut());

            obj.StatusLabel = uilabel(grid, Text = "", WordWrap = "on", ...
                VerticalAlignment = "top");
            obj.StatusLabel.Layout.Column = [1 2];

            obj.applyDefaults();

        end

        function control = addRow(obj, grid, labelText, makeControl, callback)
            %ADDROW Put one labelled control on the next row of the panel.

            arguments
                obj
                grid
                labelText (1,1) string
                makeControl function_handle
                callback = []
            end

            if isempty(callback)
                callback = @(~,~) obj.refresh();
            end

            uilabel(grid, Text = labelText);
            control = makeControl();
            control.ValueChangedFcn = callback;

        end

        function applyDefaults(obj)
            %APPLYDEFAULTS Open on the split this dataset is most likely wanted in.

            obj.GroupDropDown.Value = obj.preferredField(["Treatment", "Hemisphere", "SubjectID"]);
            obj.TileDropDown.Value = obj.preferredField(["AtlasPlate", "ROILabel", "SubjectID"]);

        end

        function field = preferredField(obj, wanted)
            %PREFERREDFIELD First of the wanted fields this dataset actually has.

            found = wanted(ismember(wanted, obj.GroupFields));

            if isempty(found)
                field = obj.NoField;
                return
            end

            field = found(1);

        end

        function onFilterFieldChanged(obj)
            %ONFILTERFIELDCHANGED Offer the new field's values, all of them kept.

            field = string(obj.FilterFieldDropDown.Value);

            if field == obj.AllSections
                obj.FilterValuesListBox.Items = {};
                obj.FilterValuesListBox.Enable = "off";
            else
                levels = obj.levelsOf(field);
                obj.FilterValuesListBox.Items = cellstr(levels);
                obj.FilterValuesListBox.Value = cellstr(levels);
                obj.FilterValuesListBox.Enable = "on";
            end

            obj.refresh();

        end

        function onReset(obj)
            %ONRESET Put the depth window and the filter back to everything.

            depth = obj.Data.grid.depth;
            obj.DepthMinField.Value = floor(min(depth));
            obj.DepthMaxField.Value = ceil(max(depth));
            obj.FilterFieldDropDown.Value = obj.AllSections;
            obj.onFilterFieldChanged();

        end

        function draw(obj, parent)
            %DRAW Build one tiled layout of the sections now in view.

            [idx, Y, x] = obj.currentView();

            if isempty(idx)
                obj.setStatus("No sections match the current filter.");
                uilabel(parent, Text = "No sections match the current filter.", ...
                    Position = [20 20 400 22]);
                return
            end

            tileField = string(obj.TileDropDown.Value);
            groupField = string(obj.GroupDropDown.Value);

            [tiles, tileOf] = obj.splitBy(tileField, idx);
            [groups, groupOf] = obj.splitBy(groupField, idx);

            colours = lines(max(numel(groups), 7));

            t = tiledlayout(parent, "flow", TileSpacing = "compact", Padding = "compact");

            for iTile = 1:numel(tiles)
                ax = nexttile(t);
                hold(ax, "on")

                inTile = find(tileOf == tiles(iTile));

                for iGroup = 1:numel(groups)
                    cols = inTile(groupOf(inTile) == groups(iGroup));

                    if isempty(cols)
                        continue
                    end

                    obj.drawGroup(ax, x, Y, idx, cols, groups(iGroup), colours(iGroup, :));
                end

                if tileField ~= obj.NoField
                    title(ax, tileField + " " + tiles(iTile), Interpreter = "none")
                end

                grid(ax, "on")
                box(ax, "on")
                axis(ax, "tight")

                if obj.LegendCheckBox.Value && numel(groups) > 1
                    legend(ax, Interpreter = "none", Location = "best")
                end
            end

            obj.labelLayout(t, groupField, numel(tiles));

            if obj.LinkCheckBox.Value
                axesHandles = findobj(t, "Type", "axes");

                if numel(axesHandles) > 1
                    linkaxes(axesHandles)
                end
            end

            obj.setStatus(sprintf("%d of %d sections | %d tile(s) | %d group(s)%s", ...
                numel(idx), height(obj.Files), numel(tiles), numel(groups), obj.skippedNote()));

        end

        function drawGroup(obj, ax, x, Y, idx, cols, groupName, colour)
            %DRAWGROUP Draw one group's sections into one tile.
            % Only the first artist of a group carries a DisplayName, so the
            % legend lists groups rather than every section in them.

            switch string(obj.ShowDropDown.Value)

                case "peak summary"
                    rows = idx(cols);
                    scatter(ax, obj.Files.PeakX(rows), obj.Files.PeakY(rows), 42, ...
                        colour, "filled", ...
                        MarkerFaceAlpha = 0.7, ...
                        DisplayName = groupName);

                case "sections"
                    for iCol = 1:numel(cols)
                        line(ax, x, Y(:, cols(iCol)), ...
                            Color = colour, ...
                            LineWidth = 1, ...
                            DisplayName = groupName, ...
                            HandleVisibility = visibility(iCol == 1));
                    end

                case "group mean"
                    if obj.SectionsCheckBox.Value
                        for iCol = 1:numel(cols)
                            line(ax, x, Y(:, cols(iCol)), ...
                                Color = [colour 0.25], ...
                                LineWidth = 0.5, ...
                                HandleVisibility = "off");
                        end
                    end

                    M = Y(:, cols);
                    n = sum(isfinite(M), 2);
                    m = mean(M, 2, "omitnan");
                    e = obj.errorOf(M, n);

                    banded = n >= 2 & isfinite(m) & isfinite(e);

                    if any(banded)
                        xb = x(banded);
                        mb = m(banded);
                        eb = e(banded);

                        fill(ax, [xb; flipud(xb)], [mb - eb; flipud(mb + eb)], colour, ...
                            FaceAlpha = 0.2, ...
                            EdgeColor = "none", ...
                            HandleVisibility = "off");
                    end

                    line(ax, x(n >= 1), m(n >= 1), ...
                        Color = colour, ...
                        LineWidth = 2, ...
                        DisplayName = sprintf("%s (n=%d)", groupName, numel(cols)));
            end

        end

        function e = errorOf(obj, M, n)
            %ERROROF Spread of one group at each depth.

            sd = std(M, 0, 2, "omitnan");

            switch string(obj.ErrorDropDown.Value)
                case "sem"
                    e = sd ./ sqrt(n);
                case "std"
                    e = sd;
                case "ci95"
                    e = 1.96 * (sd ./ sqrt(n));
                otherwise
                    e = nan(size(sd));
            end

        end

        function [idx, Y, x] = currentView(obj)
            %CURRENTVIEW The sections and depths the controls have selected.

            x = obj.Data.grid.depth;

            if string(obj.SignalDropDown.Value) == "raw"
                Y = obj.Data.grid.raw;
            else
                Y = obj.Data.grid.smoothed;
            end

            inDepth = x >= obj.DepthMinField.Value & x <= obj.DepthMaxField.Value;
            x = x(inDepth);
            Y = Y(inDepth, :);

            keep = true(height(obj.Files), 1);
            field = string(obj.FilterFieldDropDown.Value);

            if field ~= obj.AllSections
                keep = ismember(obj.Text.(field), string(obj.FilterValuesListBox.Value));
            end

            idx = find(keep);
            Y = Y(:, idx);

        end

        function [levels, levelOf] = splitBy(obj, field, idx)
            %SPLITBY Label each section in view with the value it is split on.

            if field == obj.NoField
                levels = "all";
                levelOf = repmat("all", numel(idx), 1);
                return
            end

            levelOf = obj.Text.(field)(idx);
            levels = obj.levelsOf(field);
            levels = levels(ismember(levels, levelOf));

        end

        function labelLayout(obj, t, groupField, nTiles)
            %LABELLAYOUT Name the axes once for the whole layout.

            if string(obj.ShowDropDown.Value) == "peak summary"
                % Named from the analysis rather than from the Signal control,
                % which does not reach the peaks: they were taken from whichever
                % trace ecm_prepare_analysis_data was asked to search.
                xlabel(t, obj.withUnit("peak depth from surface"))
                ylabel(t, strtrim(obj.peakSource() + " peak intensity"))
            else
                xlabel(t, obj.withUnit("depth from cortical surface"))
                ylabel(t, string(obj.SignalDropDown.Value) + " intensity")
            end

            if groupField == obj.NoField
                title(t, "all sections")
            else
                title(t, "coloured by " + groupField, Interpreter = "none")
            end

            if nTiles > 1
                subtitle(t, "tiled by " + string(obj.TileDropDown.Value), Interpreter = "none")
            end

        end

        function source = peakSource(obj)
            %PEAKSOURCE The trace A.peaks was measured from.

            source = "";

            if isfield(obj.Data, "options") && isfield(obj.Data.options, "peakSource")
                source = string(obj.Data.options.peakSource);
            end

        end

        function text = withUnit(obj, label)
            %WITHUNIT Name the distance unit the profiles were measured in.

            if obj.Unit == "" || ismissing(obj.Unit)
                text = label;
                return
            end

            text = sprintf("%s (%s)", label, obj.Unit);

        end

        function note = skippedNote(obj)
            %SKIPPEDNOTE Say how many sections never made it into the grid.

            note = "";

            if ~isfield(obj.Data, "diagnostics") || isempty(obj.Data.diagnostics)
                return
            end

            nLost = sum(obj.Data.diagnostics.Status ~= "ok");

            if nLost > 0
                note = sprintf(" | %d section(s) skipped or failed, see A.diagnostics", nLost);
            end

        end

        function setStatus(obj, text)
            %SETSTATUS Report what is on screen.

            obj.StatusLabel.Text = text;

        end

    end

end

function A = validate_analysis(A)
%VALIDATE_ANALYSIS Refuse anything that is not a populated analysis struct.

required = ["grid", "peaks", "aligned"];
missingFields = required(~isfield(A, required));

if ~isempty(missingFields)
    error("ECMBrowser:NotAnalysisStruct", ...
        "Expected the struct returned by ecm_prepare_analysis_data. Missing: %s", ...
        strjoin(missingFields, ", "))
end

if isempty(A.grid.depth) || isempty(A.grid.files)
    error("ECMBrowser:NothingToBrowse", ...
        "This analysis holds no profiles. Check A.diagnostics for why.")
end

end

function state = visibility(tf)
%VISIBILITY Turn a condition into a HandleVisibility setting.

if tf
    state = "on";
else
    state = "off";
end

end
