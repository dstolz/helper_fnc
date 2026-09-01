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
%   Normalize   A rescaling of the intensities, applied on top of whatever
%               ecm_prepare_analysis_data was asked for: a z-score, a 0-1
%               range, a fraction of the peak, unit area, or a comparison
%               against a baseline band. Taken from the smoothed trace
%               whichever trace is drawn, and applied to the peak summary as
%               well as to the profiles.
%   Scope       How much of the figure shares one scale. Per section rescales
%               every profile on its own, which lines up their shapes and
%               throws away every difference in level between them; the wider
%               scopes -- one scale per colour group, per group within a plot,
%               per plot, or one across every plot -- keep the differences
%               inside the pool they take, so what is drawn together stays
%               comparable. Only the sections in view are pooled, so a filter
%               narrows the scale as well as the plot, and the plot scopes
%               follow whatever Tile by holds, several fields included.
%   Ref. min/max
%               The depth window the normalization is taken from: the range
%               that sets the scale, and the band the baseline modes measure.
%               It is a control of its own rather than the depth window on
%               screen, so zooming in does not rescale the plot and the
%               normalization still reaches the peak summary.
%   Show        Every section, the group mean with an error band, or one point
%               per section in peak depth / peak intensity.
%   Error band  What the band around a group mean spans.
%   Colour by   Field whose values become the groups. Legend entries are per
%               group, not per section, so a plot of 85 sections still has a
%               legend that fits.
%   Tile by     Fields whose values each get their own axes. Pick more than
%               one -- plate and subject, say -- and every combination the
%               sections actually hold gets an axes of its own: the last field
%               runs across the columns and the ones before it down the rows,
%               so a column can be read from row to row.
%   Filter      One field, and which of its values to keep.
%   Depth       The depth window drawn, in the profiles' own distance unit.
%
% Right-click a curve, its error band, or the axes to change the colour and
% line style of a group. The change is made to the group rather than to the
% artist under the cursor, so it lands on every tile at once, survives the
% redraw the next control change forces, and reaches a figure POPOUT has
% already put on screen. A curve's menu leads with its own group and keeps
% the rest one level down; the axes menu offers every group evenly. A choice
% is remembered against the field as well as the value, so a palette set up
% under one Colour by field is still there after a detour through another.
%
% Fields are offered for grouping and tiling when they take between 2 and 25
% distinct values, and as filters when they take up to 100. A section
% identifier is therefore something to filter one section out by but not to
% group on, a measurement of the section is neither, and a field that holds
% the same value throughout is left out of all three. Several fields tiled
% together can ask for more axes than a screen can show anything in, so the
% ones past the 64th are left undrawn and the status line says so.
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
        NormalizeDropDown matlab.ui.control.DropDown
        ScopeDropDown matlab.ui.control.DropDown
        RefMinField matlab.ui.control.NumericEditField
        RefMaxField matlab.ui.control.NumericEditField
        ShowDropDown matlab.ui.control.DropDown
        ErrorDropDown matlab.ui.control.DropDown
        SectionsCheckBox matlab.ui.control.CheckBox
        GroupDropDown matlab.ui.control.DropDown
        TileListBox matlab.ui.control.ListBox
        FilterFieldDropDown matlab.ui.control.DropDown
        FilterValuesListBox matlab.ui.control.ListBox
        DepthMinField matlab.ui.control.NumericEditField
        DepthMaxField matlab.ui.control.NumericEditField
        LegendCheckBox matlab.ui.control.CheckBox
        LinkCheckBox matlab.ui.control.CheckBox
        StatusLabel matlab.ui.control.Label
    end

    properties (Access = private)
        % The transform the normalization controls describe: one centre and one
        % scale per section, taken once per draw so that the profiles and the
        % peaks drawn beside them are rescaled by the same two numbers.
        Norm struct = struct("centre", 0, "scale", 1, "degenerate", 0)

        % The colour and line style chosen for each group, keyed by field and
        % value, and the palette colour each group would otherwise take. Both
        % are handle objects and so are built in the constructor rather than
        % defaulted here, which would evaluate once for the class rather than
        % once per browser and leave two browsers sharing one palette.
        Styles
        Defaults

        % Figures POPOUT has produced, kept so a style change reaches them too.
        PopOuts matlab.ui.Figure = matlab.ui.Figure.empty
    end

    properties (Constant, Access = private)
        NoField = "(none)"
        AllSections = "(all sections)"
        MaxGroupLevels = 25
        MaxFilterLevels = 100
        MaxTiles = 64

        % The rescalings on offer, in the order they are listed: none, the
        % section's own spread, its range, its highest point, the area under
        % it, and two measured against the median of the reference band.
        NormalizeModes = ["none", "z-score", "min-max", "peak = 1", ...
            "area = 1", "subtract baseline", "% of baseline"]

        % Who shares one scale, from the narrowest pool to the widest. The two
        % named after another control mean nothing on their own when that
        % control is at (none), and widen to what it would otherwise have split.
        NormalizeScopes = ["per section", "per group", "per group in plot", ...
            "within plot", "across plots"]

        % What marks an artist as belonging to a group, what marks a menu as
        % ours to clear on the next draw, and the line styles on offer.
        StyleTag = "ECMBrowser:styled"
        MenuTag = "ECMBrowser:stylemenu"
        LineStyleNames = ["Solid", "Dashed", "Dotted", "Dash-dot"]
        LineStyleValues = ["-", "--", ":", "-."]
    end

    methods

        function obj = ECMBrowser(A)

            arguments
                A struct
            end

            obj.Data = validate_analysis(A);
            obj.Files = obj.Data.grid.files;
            obj.Styles = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.Defaults = containers.Map('KeyType', 'char', 'ValueType', 'any');
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

            % The scope and the reference window belong to the normalization
            % rather than to the view, so they stay live in the peak summary the
            % depth controls above cannot reach, and go quiet only when there is
            % nothing being rescaled.
            normalized = matlab.lang.OnOffSwitchState( ...
                string(obj.NormalizeDropDown.Value) ~= "none");
            obj.ScopeDropDown.Enable = normalized;
            obj.RefMinField.Enable = normalized;
            obj.RefMaxField.Enable = normalized;

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

        function setNormalization(obj, mode, window, options)
            %SETNORMALIZATION Rescale each section, and say where from.
            %   B.setNormalization("z-score")
            %   B.setNormalization("peak = 1", scope = "within plot")
            %   B.setNormalization("% of baseline", [800 1500])
            %   B.setNormalization()  draws the intensities as they were prepared
            %
            % The mode, the sections it pools, and the window it is measured
            % over only mean anything together, so they are set together: the
            % one call a script needs to put a figure on the scale it should be
            % read on.

            arguments
                obj
                mode (1,1) string = "none"
                window (1,2) double = [obj.RefMinField.Value obj.RefMaxField.Value]
                options.scope (1,1) string = string(obj.ScopeDropDown.Value)
            end

            if ~ismember(mode, obj.NormalizeModes)
                error("ECMBrowser:UnknownNormalization", ...
                    "Normalization must be one of: %s", strjoin(obj.NormalizeModes, ", "))
            end

            if ~ismember(options.scope, obj.NormalizeScopes)
                error("ECMBrowser:UnknownNormalizationScope", ...
                    "Scope must be one of: %s", strjoin(obj.NormalizeScopes, ", "))
            end

            if ~all(isfinite(window)) || window(2) <= window(1)
                error("ECMBrowser:EmptyReferenceWindow", ...
                    "The reference window must run from one finite depth to a larger one.")
            end

            obj.NormalizeDropDown.Value = mode;
            obj.ScopeDropDown.Value = options.scope;
            obj.RefMinField.Value = window(1);
            obj.RefMaxField.Value = window(2);
            obj.refresh();

        end

        function f = popOut(obj)
            %POPOUT Draw the current view into an ordinary figure.
            % A uifigure cannot be saved as a .fig or handed to EXPORTGRAPHICS
            % the way a plain figure can, and the current view is the only
            % thing here anyone is likely to want to keep.

            f = figure(Name = "ECM Browser", NumberTitle = "off", Color = "w");
            obj.PopOuts = [obj.PopOuts(isvalid(obj.PopOuts)), f];
            obj.draw(f);

            if nargout == 0
                clear f
            end

        end

        function setGroupStyle(obj, field, level, opts)
            %SETGROUPSTYLE Draw one group in a colour and line style of your own.
            %   B.setGroupStyle("Treatment", "GM6001", Color = [0.85 0.33 0.10])
            %   B.setGroupStyle("Treatment", "GM6001", LineStyle = "--")
            %
            % What the right-click menu does, reachable from a script. FIELD is
            % the field the group came from -- normally whatever Colour by is
            % set to -- and LEVEL one of its values. Either option can be given
            % on its own, and the other is left as it was.
            %
            % The change reaches every plot already on screen without a redraw,
            % so nothing loses the zoom it was left at, and it is kept until
            % RESETGROUPSTYLES takes it back.

            arguments
                obj
                field (1,1) string
                level (1,1) string
                opts.Color (1,:) double = []
                opts.LineStyle (1,1) string = ""
            end

            key = obj.styleKey(field, level);

            if isKey(obj.Styles, key)
                chosen = obj.Styles(key);
            else
                chosen = struct(Color = [], LineStyle = "");
            end

            if ~isempty(opts.Color)
                if numel(opts.Color) ~= 3 || any(opts.Color < 0 | opts.Color > 1)
                    error("ECMBrowser:BadColour", ...
                        "Color must be an RGB triplet with each part between 0 and 1.")
                end

                chosen.Color = opts.Color;
            end

            if opts.LineStyle ~= ""
                mustBeMember(opts.LineStyle, obj.LineStyleValues)
                chosen.LineStyle = opts.LineStyle;
            end

            obj.Styles(key) = chosen;
            obj.applyStyles();

        end

        function resetGroupStyles(obj, field, level)
            %RESETGROUPSTYLES Put groups back to the colours the palette gave them.
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

            depth = obj.Data.grid.depth;

            grid = uigridlayout(controls, [17 2]);
            grid.ColumnWidth = {90, '1x'};
            grid.RowHeight = [repmat({24}, 1, 9), {84}, {24}, {'1x'}, ...
                repmat({24}, 1, 4), {40}];
            grid.RowSpacing = 6;

            obj.SignalDropDown = obj.addRow(grid, "Signal", ...
                @() uidropdown(grid, Items = ["smoothed", "raw"]));

            obj.NormalizeDropDown = obj.addRow(grid, "Normalize", ...
                @() uidropdown(grid, Items = obj.NormalizeModes, ...
                    Tooltip = "Rescale the intensities before they are drawn."));

            obj.ScopeDropDown = obj.addRow(grid, "Scope", ...
                @() uidropdown(grid, Items = obj.NormalizeScopes, ...
                    Tooltip = "How many sections share one scale."));

            obj.RefMinField = obj.addRow(grid, "Ref. min", ...
                @() uieditfield(grid, "numeric", Value = floor(min(depth)), ...
                    Tooltip = "Start of the depth window the normalization is taken from."));

            obj.RefMaxField = obj.addRow(grid, "Ref. max", ...
                @() uieditfield(grid, "numeric", Value = ceil(max(depth)), ...
                    Tooltip = "End of that window, and of the band the baseline modes measure."));

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

            obj.TileListBox = obj.addRow(grid, "Tile by", ...
                @() uilistbox(grid, Items = [obj.NoField; obj.GroupFields], ...
                    Multiselect = "on", ...
                    Tooltip = "Pick several to split on every combination of them: " + ...
                        "the last runs across the columns, the rest down the rows."));

            obj.FilterFieldDropDown = obj.addRow(grid, "Filter by", ...
                @() uidropdown(grid, Items = [obj.AllSections; obj.FilterFields]), ...
                @(~,~) obj.onFilterFieldChanged());

            obj.FilterValuesListBox = uilistbox(grid, ...
                Items = {}, ...
                Multiselect = "on", ...
                ValueChangedFcn = @(~,~) obj.refresh());
            obj.FilterValuesListBox.Layout.Column = [1 2];

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
            obj.TileListBox.Value = cellstr(obj.preferredField(["AtlasPlate", "ROILabel", "SubjectID"]));

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
            %ONRESET Put the depth window, the scale, and the filter back.

            depth = obj.Data.grid.depth;
            obj.DepthMinField.Value = floor(min(depth));
            obj.DepthMaxField.Value = ceil(max(depth));
            obj.NormalizeDropDown.Value = "none";
            obj.ScopeDropDown.Value = "per section";
            obj.RefMinField.Value = floor(min(depth));
            obj.RefMaxField.Value = ceil(max(depth));
            obj.FilterFieldDropDown.Value = obj.AllSections;
            obj.onFilterFieldChanged();

        end

        function draw(obj, parent)
            %DRAW Build one tiled layout of the sections now in view.

            [idx, Y, x] = obj.currentView();

            % The right-click menus hang off the figure rather than off the
            % panel the plot goes into, so the ones the last draw built outlive
            % the redraw that replaced their plot and are cleared here instead.
            fig = ancestor(parent, 'figure');
            delete(findall(fig, 'Type', 'uicontextmenu', 'Tag', char(obj.MenuTag)))

            if isprop(parent, 'ContextMenu')
                parent.ContextMenu = [];
            end

            if isempty(idx)
                obj.setStatus("No sections match the current filter.");
                uilabel(parent, Text = "No sections match the current filter.", ...
                    Position = [20 20 400 22]);
                return
            end

            tileBy = obj.tileFields();
            groupField = string(obj.GroupDropDown.Value);

            [tiles, tileOf, nCols] = obj.tiling(tileBy, idx);
            [groups, groupOf] = obj.splitBy(groupField, idx);

            % Several fields tiled together can call for more axes than there is
            % screen to draw them in, so the ones past the cap are left off and
            % reported rather than spending a minute on a wall of empty boxes.
            nWanted = numel(tiles);
            tiles = tiles(1:min(nWanted, obj.MaxTiles));
            nRows = ceil(tiles(end).Index / nCols);

            colours = lines(max(numel(groups), 7));
            obj.rememberDefaults(groupField, groups, colours);

            % One menu per group for the artists that draw it, and one listing
            % every group for the axes behind them, which is what a right-click
            % that misses a curve finds.
            [axesMenu, groupMenus] = obj.buildStyleMenus(fig, groupField, groups);

            if isprop(parent, 'ContextMenu')
                parent.ContextMenu = axesMenu;
            end

            % A single split wraps into a flow the way it always has; a split of
            % two or more fields is placed on the grid its combinations came out
            % on, empty cells and all, which is what makes one column comparable
            % from row to row.
            if nRows > 1
                t = tiledlayout(parent, nRows, nCols, ...
                    TileSpacing = "compact", Padding = "compact");
            else
                t = tiledlayout(parent, "flow", TileSpacing = "compact", Padding = "compact");
            end

            for iTile = 1:numel(tiles)
                if nRows > 1
                    ax = nexttile(t, tiles(iTile).Index);
                else
                    ax = nexttile(t);
                end

                hold(ax, "on")
                ax.ContextMenu = axesMenu;

                inTile = find(tileOf == tiles(iTile).Index);

                for iGroup = 1:numel(groups)
                    cols = inTile(groupOf(inTile) == groups(iGroup));

                    if isempty(cols)
                        continue
                    end

                    artists = obj.drawGroup(ax, x, Y, idx, cols, ...
                        groupField, groups(iGroup), colours(iGroup, :));

                    set(artists, 'ContextMenu', groupMenus(char(groups(iGroup))))
                end

                if tiles(iTile).Label ~= ""
                    title(ax, tiles(iTile).Label, Interpreter = "none")
                end

                grid(ax, "on")
                box(ax, "on")
                axis(ax, "tight")

                if obj.LegendCheckBox.Value && numel(groups) > 1
                    legend(ax, Interpreter = "none", Location = "best")
                end
            end

            obj.labelLayout(t, groupField, tileBy, numel(tiles));

            if obj.LinkCheckBox.Value
                axesHandles = findobj(t, "Type", "axes");

                if numel(axesHandles) > 1
                    linkaxes(axesHandles)
                end
            end

            obj.setStatus(sprintf("%d of %d sections | %s | %d group(s)%s%s", ...
                numel(idx), height(obj.Files), tile_note(numel(tiles), nWanted), ...
                numel(groups), obj.normNote(), obj.skippedNote()));

        end

        function h = drawGroup(obj, ax, x, Y, idx, cols, groupField, groupName, colour)
            %DRAWGROUP Draw one group's sections into one tile.
            % Only the first artist of a group carries a DisplayName, so the
            % legend lists groups rather than every section in them.
            %
            % Everything drawn is handed back and marked with the group it
            % belongs to and the part it plays in it, which is what lets a
            % colour chosen later find its way to every tile at once.

            sty = obj.effectiveStyle(groupField, groupName);

            h = gobjects(1, 0);
            roles = strings(1, 0);

            switch string(obj.ShowDropDown.Value)

                case "peak summary"
                    rows = idx(cols);
                    h(end+1) = scatter(ax, obj.Files.PeakX(rows), obj.peakHeights(rows), 42, ...
                        sty.Color, "filled", ...
                        MarkerFaceAlpha = 0.7, ...
                        DisplayName = groupName);
                    roles(end+1) = "marker";

                case "sections"
                    for iCol = 1:numel(cols)
                        h(end+1) = line(ax, x, Y(:, cols(iCol)), ...
                            Color = sty.Color, ...
                            LineStyle = sty.LineStyle, ...
                            LineWidth = 1, ...
                            DisplayName = groupName, ...
                            HandleVisibility = visibility(iCol == 1)); %#ok<AGROW>
                        roles(end+1) = "line"; %#ok<AGROW>
                    end

                case "group mean"
                    if obj.SectionsCheckBox.Value
                        for iCol = 1:numel(cols)
                            h(end+1) = line(ax, x, Y(:, cols(iCol)), ...
                                Color = [sty.Color 0.25], ...
                                LineStyle = sty.LineStyle, ...
                                LineWidth = 0.5, ...
                                HandleVisibility = "off"); %#ok<AGROW>
                            roles(end+1) = "faint"; %#ok<AGROW>
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

                        h(end+1) = fill(ax, [xb; flipud(xb)], [mb - eb; flipud(mb + eb)], ...
                            sty.Color, ...
                            FaceAlpha = 0.2, ...
                            EdgeColor = "none", ...
                            HandleVisibility = "off");
                        roles(end+1) = "band";
                    end

                    h(end+1) = line(ax, x(n >= 1), m(n >= 1), ...
                        Color = sty.Color, ...
                        LineStyle = sty.LineStyle, ...
                        LineWidth = 2, ...
                        DisplayName = sprintf("%s (n=%d)", groupName, numel(cols)));
                    roles(end+1) = "line";
            end

            obj.markStyled(h, roles, groupField, groupName, colour);

        end

        function y = peakHeights(obj, rows)
            %PEAKHEIGHTS The section peaks on the scale the profiles are drawn on.
            % A.peaks holds one height per section in the units it was measured
            % in, so the transform that rescaled the profiles has to reach it
            % too; a summary read beside a normalized plot would otherwise be
            % answering a different question from the one on screen.

            centre = obj.Norm.centre(:);
            scale = obj.Norm.scale(:);

            y = (obj.Files.PeakY(rows) - centre(rows)) ./ scale(rows);

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

            keep = true(height(obj.Files), 1);
            field = string(obj.FilterFieldDropDown.Value);

            if field ~= obj.AllSections
                keep = ismember(obj.Text.(field), string(obj.FilterValuesListBox.Value));
            end

            idx = find(keep);

            % Whichever trace is drawn, the transform is taken from the smoothed
            % one: raw and smoothed then sit on a single scale, so switching
            % Signal moves between two views of one plot rather than rescaling
            % it, and one noisy sample cannot become a section's peak or range.
            % The filter is settled first because a pooled scale is taken from
            % the sections actually drawn, and rescaling before the depth trim
            % is what keeps the reference window independent of the window on
            % screen. The transform is kept on the object for the rest of this
            % draw because the peak summary needs the same numbers.
            obj.Norm = obj.normalizationOf(x, obj.Data.grid.smoothed, keep);

            Y = (Y - obj.Norm.centre) ./ obj.Norm.scale;

            inDepth = x >= obj.DepthMinField.Value & x <= obj.DepthMaxField.Value;
            x = x(inDepth);
            Y = Y(inDepth, idx);

        end

        function n = normalizationOf(obj, depth, reference, inView)
            %NORMALIZATIONOF The rescaling the normalization controls describe.
            % Every mode is one affine map -- subtract a centre, divide by a
            % scale -- so a mode is a choice of which statistic those two
            % numbers are read from, and a scope is a choice of how many
            % sections are pooled to read it. One pair of vectors then rescales
            % the profile grid and the section peaks alike. REFERENCE is the
            % smoothed grid over the whole depth axis; the reference window and
            % the sections in view are applied here.

            nSections = size(reference, 2);

            centre = zeros(1, nSections);
            scale = ones(1, nSections);

            mode = string(obj.NormalizeDropDown.Value);

            if mode == "none"
                n = struct("centre", centre, "scale", scale, "degenerate", 0);
                return
            end

            inRef = depth >= obj.RefMinField.Value & depth <= obj.RefMaxField.Value;

            if ~any(inRef)
                n = struct("centre", centre, "scale", scale, "degenerate", nnz(inView));
                return
            end

            xRef = depth(inRef);
            R = reference(inRef, :);

            poolId = obj.poolOf(inView);
            pools = unique(poolId(~isnan(poolId)));

            for iPool = 1:numel(pools)
                inPool = poolId == pools(iPool);

                [poolCentre, poolScale] = pool_stats(mode, xRef, R(:, inPool));

                centre(inPool) = poolCentre;
                scale(inPool) = poolScale;
            end

            % A pool the transform cannot be taken from -- one that never
            % reached the reference window, one that is flat inside it, or one
            % whose divisor is not positive because the profiles were already
            % centred on zero upstream -- is left in its own units rather than
            % blown up by a scale near zero, and its sections are counted so
            % that the status line can say it happened.
            usable = isfinite(centre) & isfinite(scale) & scale > 0;

            centre(~usable) = 0;
            scale(~usable) = 1;

            n = struct("centre", centre, "scale", scale, ...
                "degenerate", sum(~usable & ~isnan(poolId)));

        end

        function poolId = poolOf(obj, inView)
            %POOLOF Label each section with the sections it shares a scale with.
            % A section that is filtered out is left unlabelled: it is not on
            % screen, so it has no business setting the scale of a plot it is
            % absent from.

            inView = reshape(logical(inView), 1, []);

            poolId = nan(1, numel(inView));

            switch string(obj.ScopeDropDown.Value)

                case "per section"
                    poolId(inView) = find(inView);

                case "per group"
                    poolId = obj.poolByFields(inView, string(obj.GroupDropDown.Value));

                case "per group in plot"
                    poolId = obj.poolByFields(inView, ...
                        [string(obj.GroupDropDown.Value), obj.tileFields()]);

                case "within plot"
                    poolId = obj.poolByFields(inView, obj.tileFields());

                otherwise
                    poolId(inView) = 1;
            end

        end

        function poolId = poolByFields(obj, inView, fields)
            %POOLBYFIELDS One pool per combination of the named fields.
            % A field left at (none) splits nothing, so a scope named after a
            % control that is not in use widens to everything in view rather
            % than being refused: with no Tile by field there is one plot, and
            % within it is across it.

            fields = unique(fields(fields ~= obj.NoField), "stable");

            poolId = nan(1, numel(inView));

            if isempty(fields)
                poolId(inView) = 1;
                return
            end

            key = table();

            for iField = 1:numel(fields)
                key.(fields(iField)) = obj.Text.(fields(iField));
            end

            id = reshape(findgroups(key), 1, []);
            poolId(inView) = id(inView);

        end

        function fields = tileFields(obj)
            %TILEFIELDS The fields the Tile by list now has selected.
            % Put back into the order the list offers them, so which field runs
            % down the rows and which across the columns is the order on screen
            % rather than the order they happened to be clicked in. "(none)" is
            % not a field, so a selection holding it comes back one field short
            % and a selection of nothing else comes back empty.

            selected = string(obj.TileListBox.Value);
            fields = obj.GroupFields(ismember(obj.GroupFields, selected));
            fields = reshape(fields, 1, []);

        end

        function [tiles, tileOf, nCols] = tiling(obj, fields, idx)
            %TILING The axes the Tile by selection asks for, and the one each
            %section belongs in.
            % TILES is one entry per cell that holds sections, in the order they
            % are drawn, carrying the cell it goes in and the title it wears;
            % TILEOF says which cell each section in view fell into, counted
            % across a grid NCOLS wide. A cell no section landed in is left
            % out, so a combination the dataset never held costs nothing but
            % the gap it leaves in the grid.

            nSections = numel(idx);

            if isempty(fields)
                tiles = struct("Index", 1, "Label", "");
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
                levels{iField} = obj.levelsOf(fields(iField));
                [~, ranks(:, iField)] = ismember( ...
                    obj.Text.(fields(iField))(idx), levels{iField});
            end

            [colRanks, ~, colOf] = unique(ranks(:, end));
            nCols = numel(colRanks);

            if isscalar(fields)
                rowRanks = zeros(1, 0);
                rowOf = ones(nSections, 1);
            else
                [rowRanks, ~, rowOf] = unique(ranks(:, 1:end-1), "rows");
            end

            tileOf = (rowOf - 1) * nCols + colOf;

            occupied = unique(tileOf);
            tiles = repmat(struct("Index", 0, "Label", ""), numel(occupied), 1);

            for iTile = 1:numel(occupied)
                iCol = mod(occupied(iTile) - 1, nCols) + 1;
                iRow = (occupied(iTile) - iCol) / nCols + 1;

                values = strings(1, numel(fields));
                values(end) = levels{end}(colRanks(iCol));

                for iField = 1:numel(fields) - 1
                    values(iField) = levels{iField}(rowRanks(iRow, iField));
                end

                tiles(iTile).Index = occupied(iTile);

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

        function labelLayout(obj, t, groupField, tileFields, nTiles)
            %LABELLAYOUT Name the axes once for the whole layout.

            if string(obj.ShowDropDown.Value) == "peak summary"
                % Named from the analysis rather than from the Signal control,
                % which does not reach the peaks: they were taken from whichever
                % trace ecm_prepare_analysis_data was asked to search.
                xlabel(t, obj.withUnit("peak depth from surface"))
                ylabel(t, obj.withNormalization(strtrim(obj.peakSource() + " peak intensity")))
            else
                xlabel(t, obj.withUnit("depth from cortical surface"))
                ylabel(t, obj.withNormalization(string(obj.SignalDropDown.Value) + " intensity"))
            end

            if groupField == obj.NoField
                title(t, "all sections")
            else
                title(t, "coloured by " + groupField, Interpreter = "none")
            end

            if nTiles > 1 && ~isempty(tileFields)
                subtitle(t, "tiled by " + strjoin(tileFields, " x "), Interpreter = "none")
            end

        end

        function source = peakSource(obj)
            %PEAKSOURCE The trace A.peaks was measured from.

            source = "";

            if isfield(obj.Data, "options") && isfield(obj.Data.options, "peakSource")
                source = string(obj.Data.options.peakSource);
            end

        end

        function text = withNormalization(obj, label)
            %WITHNORMALIZATION Name the scale the intensities are drawn on.
            % Normalized intensities carry no unit, and the mode and the scope
            % together are the only thing that says what a value of 1 means, so
            % both are named on the axis rather than left in the control panel
            % of whoever drew the figure.

            switch string(obj.NormalizeDropDown.Value)
                case "z-score"
                    scaleName = "z-score";
                case "min-max"
                    scaleName = "0-1";
                case "peak = 1"
                    scaleName = "fraction of peak";
                case "area = 1"
                    scaleName = "unit area";
                case "subtract baseline"
                    scaleName = "baseline subtracted";
                case "% of baseline"
                    scaleName = "% of baseline";
                otherwise
                    text = label;
                    return
            end

            scope = string(obj.ScopeDropDown.Value);

            if scope ~= "per section"
                scaleName = scaleName + ", " + scope;
            end

            text = label + " (" + scaleName + ")";

        end

        function text = withUnit(obj, label)
            %WITHUNIT Name the distance unit the profiles were measured in.

            if obj.Unit == "" || ismissing(obj.Unit)
                text = label;
                return
            end

            text = sprintf("%s (%s)", label, obj.Unit);

        end

        function note = normNote(obj)
            %NORMNOTE Say how many sections the rescaling could not be taken from.

            note = "";

            if obj.Norm.degenerate > 0
                note = sprintf(" | %d section(s) drawn unnormalized", obj.Norm.degenerate);
            end

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

        function key = styleKey(~, field, level)
            %STYLEKEY One value of one field, as a key both halves have to match.
            % The field is part of it so that a colour picked for Treatment
            % GM6001 is still there after a look at the same sections split by
            % Hemisphere, rather than following the palette slot it happened to
            % share with a hemisphere.

            key = char(field + "|" + level);

        end

        function rememberDefaults(obj, groupField, groups, colours)
            %REMEMBERDEFAULTS Note the palette colour each group started from.
            % The menu needs it to open the colour picker on the colour actually
            % on screen, and a reset needs it to have somewhere to go back to.

            for k = 1:numel(groups)
                obj.Defaults(obj.styleKey(groupField, groups(k))) = colours(k, :);
            end

        end

        function sty = effectiveStyle(obj, field, level)
            %EFFECTIVESTYLE What one group is drawn in: chosen, or the palette.

            key = obj.styleKey(field, level);

            sty = struct(Color = lines(1), LineStyle = "-");

            if isKey(obj.Defaults, key)
                sty.Color = obj.Defaults(key);
            end

            if ~isKey(obj.Styles, key)
                return
            end

            chosen = obj.Styles(key);

            if ~isempty(chosen.Color)
                sty.Color = chosen.Color;
            end

            if chosen.LineStyle ~= ""
                sty.LineStyle = chosen.LineStyle;
            end

        end

        function markStyled(obj, h, roles, field, level, colour)
            %MARKSTYLED Say which group an artist draws, and what part of it.
            % The palette colour is written onto the artist rather than looked
            % up again later, so a popped-out figure keeps the colours it was
            % drawn with even after the panel behind it has been regrouped.

            for k = 1:numel(h)
                h(k).Tag = char(obj.StyleTag);
                h(k).UserData = struct( ...
                    Field = field, ...
                    Group = level, ...
                    Role = roles(k), ...
                    Colour = colour);
            end

        end

        function applyStyles(obj)
            %APPLYSTYLES Repaint every artist that belongs to a restyled group.
            % Reaching the artists themselves rather than redrawing is what puts
            % the change on every tile at once without disturbing a zoom, and
            % what lets it reach a popped-out figure the controls no longer
            % drive.

            obj.PopOuts = obj.PopOuts(isvalid(obj.PopOuts));

            figs = obj.PopOuts;

            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                figs = [obj.Fig, figs];
            end

            for iFig = 1:numel(figs)
                artists = findall(figs(iFig), 'Tag', char(obj.StyleTag));

                for k = 1:numel(artists)
                    obj.repaint(artists(k));
                end
            end

        end

        function repaint(obj, h)
            %REPAINT One artist, in whatever its group is drawn in now.
            % A band and a scatter have no line style to take, and the sections
            % drawn faintly behind a mean carry their transparency in the colour
            % itself, so each part of a group is put back its own way.

            mark = h.UserData;
            key = obj.styleKey(mark.Field, mark.Group);

            colour = mark.Colour;
            lineStyle = "-";

            if isKey(obj.Styles, key)
                chosen = obj.Styles(key);

                if ~isempty(chosen.Color)
                    colour = chosen.Color;
                end

                if chosen.LineStyle ~= ""
                    lineStyle = chosen.LineStyle;
                end
            end

            switch mark.Role
                case "line"
                    h.Color = colour;
                    h.LineStyle = lineStyle;

                case "faint"
                    h.Color = [colour 0.25];
                    h.LineStyle = lineStyle;

                case "band"
                    h.FaceColor = colour;

                case "marker"
                    h.CData = colour;
            end

        end

        function [axesMenu, groupMenus] = buildStyleMenus(obj, fig, groupField, groups)
            %BUILDSTYLEMENUS One menu per group, and one for the axes behind them.

            axesMenu = obj.buildStyleMenu(fig, groupField, groups, "");
            groupMenus = containers.Map('KeyType', 'char', 'ValueType', 'any');

            for k = 1:numel(groups)
                groupMenus(char(groups(k))) = ...
                    obj.buildStyleMenu(fig, groupField, groups, groups(k));
            end

        end

        function cm = buildStyleMenu(obj, fig, groupField, groups, clicked)
            %BUILDSTYLEMENU The menu behind one right-click.
            % A curve's menu leads with its own group, because that is the one
            % the click was about, and keeps the rest a level down so that a
            % click landing on the wrong curve is still one menu away from the
            % right group.

            cm = uicontextmenu(fig, Tag = char(obj.MenuTag), ...
                ContextMenuOpeningFcn = @(src, ~) obj.syncStyleMenu(src));

            others = groups;

            if clicked ~= ""
                obj.addStyleItems(cm, groupField, clicked, clicked + ": ");
                others = groups(groups ~= clicked);
            end

            if ~isempty(others)
                parent = cm;

                if clicked ~= ""
                    parent = uimenu(cm, Text = "Other groups", Separator = "on");
                end

                for k = 1:numel(others)
                    obj.addStyleItems(uimenu(parent, Text = others(k)), ...
                        groupField, others(k), "");
                end
            end

            uimenu(cm, Text = "Reset all groups", Separator = "on", ...
                MenuSelectedFcn = @(~, ~) obj.resetGroupStyles(groupField));

        end

        function addStyleItems(obj, parent, groupField, level, prefix)
            %ADDSTYLEITEMS The colour, line style, and reset one group offers.
            % PREFIX names the group in the items when they sit at the top of a
            % menu, and is empty when they sit under a submenu already carrying
            % the name.

            uimenu(parent, Text = prefix + "Colour...", ...
                MenuSelectedFcn = @(~, ~) obj.pickColour(groupField, level));

            styles = uimenu(parent, Text = prefix + "Line style");

            for k = 1:numel(obj.LineStyleValues)
                % Which style is ticked is settled when the menu opens rather
                % than when it is built, so the tick is right however the style
                % was last set.
                uimenu(styles, Text = obj.LineStyleNames(k), ...
                    UserData = struct(Field = groupField, Group = level, ...
                        LineStyle = obj.LineStyleValues(k)), ...
                    MenuSelectedFcn = @(src, ~) obj.setGroupStyle(groupField, level, ...
                        LineStyle = src.UserData.LineStyle));
            end

            uimenu(parent, Text = prefix + "Reset", Separator = "on", ...
                MenuSelectedFcn = @(~, ~) obj.resetGroupStyles(groupField, level));

        end

        function syncStyleMenu(obj, cm)
            %SYNCSTYLEMENU Tick the line style each group is currently drawn in.

            items = findall(cm, 'Type', 'uimenu');

            for k = 1:numel(items)
                mark = items(k).UserData;

                if ~isstruct(mark) || ~isfield(mark, "LineStyle")
                    continue
                end

                sty = obj.effectiveStyle(mark.Field, mark.Group);
                items(k).Checked = matlab.lang.OnOffSwitchState(sty.LineStyle == mark.LineStyle);
            end

        end

        function pickColour(obj, groupField, level)
            %PICKCOLOUR Ask for a colour for one group and put it on every plot.
            % UISETCOLOR hands back what it was opened on when it is cancelled,
            % so a cancel quietly sets the colour the group already had.

            sty = obj.effectiveStyle(groupField, level);
            chosen = uisetcolor(sty.Color, char("Colour for " + level));

            if ~isequal(size(chosen), [1 3])
                return
            end

            obj.setGroupStyle(groupField, level, Color = chosen);

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

function a = column_area(x, Y)
%COLUMN_AREA Integrate each column over the depths it actually measured.
% TRAPZ has no omitnan, and a section that stops short of the reference window
% leaves NaN behind, so each column is integrated over its own finite samples
% rather than being given up on for the depths it never reached.

a = nan(1, size(Y, 2));

for iCol = 1:size(Y, 2)
    finiteSample = isfinite(Y(:, iCol));

    if nnz(finiteSample) > 1
        a(iCol) = trapz(x(finiteSample), Y(finiteSample, iCol));
    end
end

end

function [centre, scale] = pool_stats(mode, x, R)
%POOL_STATS The centre and scale one pool of sections is rescaled by.
% R holds every sample the pool contributes inside the reference window, and
% the statistic is taken over the whole block rather than column by column: a
% pool of one section and a pool of a whole plot are then the same arithmetic,
% and pooling keeps the differences between the sections it holds instead of
% flattening them the way rescaling each section separately does.

v = R(:);

centre = 0;
scale = 1;

switch mode

    case "z-score"
        centre = mean(v, 1, "omitnan");
        scale = std(v, 0, 1, "omitnan");

    case "min-max"
        centre = min(v, [], 1, "omitnan");
        scale = max(v, [], 1, "omitnan") - centre;

    case "peak = 1"
        scale = max(v, [], 1, "omitnan");

    case "area = 1"
        % The mean area of the pool rather than its total, so that the average
        % section comes out at one whether the pool holds one or thirty.
        scale = mean(column_area(x, R), 2, "omitnan");

    case "subtract baseline"
        % The median rather than the mean: the band is chosen to hold
        % background, and one stray bright sample in it should not shift
        % everything drawn against it.
        centre = median(v, 1, "omitnan");

    case "% of baseline"
        scale = median(v, 1, "omitnan") ./ 100;
end

end

function note = tile_note(nDrawn, nWanted)
%TILE_NOTE Say how many tiles are on screen, and how many were left off.

if nDrawn < nWanted
    note = sprintf("%d of %d tile(s), the rest left undrawn", nDrawn, nWanted);
else
    note = sprintf("%d tile(s)", nDrawn);
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
