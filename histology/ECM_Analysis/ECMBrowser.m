classdef ECMBrowser < handle
%ECMBROWSER Browse the profiles ecm_prepare_analysis_data produced.
%   B = ECMBrowser(A)
%
% A is the struct returned by ECM_PREPARE_ANALYSIS_DATA. Everything drawn
% comes from A.grid -- one column per section on a shared depth axis -- and
% A.grid.files, the section table beside it, which supplies every field the
% profiles can be colored, tiled, and filtered by.
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
%               scopes -- one scale per color group, per group within a plot,
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
%   Error band  What the band around a group mean spans: the spread of its
%               sections, a normal interval for their mean, or a bootstrap
%               one that resamples the sections instead of assuming a shape
%               for them and may sit unevenly around the mean.
%   Color by   Field whose values become the groups. Legend entries are per
%               group, not per section, so a plot of 85 sections still has a
%               legend that fits.
%   Tile by     Fields whose values each get their own axes. Pick more than
%               one -- plate and subject, say -- and every combination the
%               sections actually hold gets an axes of its own: the last field
%               runs across the columns and the ones before it down the rows,
%               so a column can be read from row to row.
%   Filter      One field, and which of its values to keep.
%   Depth       The depth window drawn, in the profiles' own distance unit.
%   Transpose   Turns the plot on its side: depth runs down the vertical
%               axis, surface at the top and deeper below it, the way a
%               section is looked at, and the intensity runs across. It is
%               a choice about how the plot is read rather than what is in
%               it, so everything else -- the normalization, the tiling,
%               the legend, an export -- is unchanged by it.
%   Legend      Where the key goes. Per tile is one legend inside every axes,
%               as it has always been; the two consolidated placements draw a
%               single legend outside them all -- a horizontal band across the
%               top of the layout, under its title, or a column down its right
%               -- and hand the room the repeated keys were taking back to the
%               plots. A consolidated legend lists every group in view whether
%               or not a given tile holds it, so one key reads across all of
%               them, and it follows a color or line style set from a
%               right-click menu the same way the curves do.
%
% Right-click a curve, its error band, or the axes to change the color and
% line style of a group. The change is made to the group rather than to the
% artist under the cursor, so it lands on every tile at once, survives the
% redraw the next control change forces, and reaches a figure POPOUT has
% already put on screen. A curve's menu leads with its own group and keeps
% the rest one level down; the axes menu offers every group evenly. A choice
% is remembered against the field as well as the value, so a palette set up
% under one Color by field is still there after a detour through another.
%
% Fields are offered for grouping and tiling when they take between 2 and 25
% distinct values, and as filters when they take up to 100. A section
% identifier is therefore something to filter one section out by but not to
% group on, a measurement of the section is neither, and a field that holds
% the same value throughout is left out of all three. Several fields tiled
% together can ask for more axes than a screen can show anything in, so the
% ones past the 64th are left undrawn and the status line says so.
%
% Config, near the foot of the panel, remembers the state of every control
% above -- not a color or line style set from a right-click menu, which is
% kept of its own accord. Save adds the state on screen now to the list under
% an autogenerated name; picking a name back out of the list puts the panel
% back the way it was; Delete removes the name showing, and Purge every name
% at once. The list is kept in MATLAB's own preferences rather than a file of
% its own, so it survives from one ECMBrowser to the next, and a config saved
% against a field this dataset does not have -- a color-by, tile-by, or
% filter field from a different one -- is left unset rather than refused.
%
% Export, on the menu bar, is how anything leaves the browser, and what it
% sends out is the plot alone -- the panel of controls is how a figure was
% arrived at, not part of it. The plot is redrawn into a plain figure for
% each export, at the size it is on screen and on the limits it was left at,
% so a zoom is exported rather than thrown away and a vector format is
% available, which it is not from a uifigure. Copy puts it on the clipboard
% as a bitmap or as vector graphics; Save plot writes PNG, TIFF, or JPEG for
% a bitmap, PDF, EPS, or SVG for something that stays sharp at any size, and
% .fig for the figure itself, still open to editing. Data sends the numbers
% under the plot the same way: to the base workspace, to the clipboard, or
% to a CSV -- one column per section for a plotting program, one row per
% sample carrying every field the sections can be split by for a statistics
% package, or one row per section for the peaks. Image resolution and
% Background set what the bitmap formats are written at and whether the
% paper behind the plot is white or left out altogether, which only the
% vector formats and the clipboard can do; both are kept for the session. Copy view summary writes out every choice that decides what
% the plot means, which is what a methods paragraph needs and a screenshot
% does not hold.
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
        LegendDropDown matlab.ui.control.DropDown
        LinkCheckBox matlab.ui.control.CheckBox
        TransposeCheckBox matlab.ui.control.CheckBox
        ConfigDropDown matlab.ui.control.DropDown
        StatusLabel matlab.ui.control.Label
    end

    properties (Access = private)
        % The transform the normalization controls describe: one center and one
        % scale per section, taken once per draw so that the profiles and the
        % peaks drawn beside them are rescaled by the same two numbers.
        Norm struct = struct("center", 0, "scale", 1, "degenerate", 0)

        % The color and line style chosen for each group, keyed by field and
        % value, and the palette color each group would otherwise take. Both
        % are handle objects and so are built in the constructor rather than
        % defaulted here, which would evaluate once for the class rather than
        % once per browser and leave two browsers sharing one palette.
        Styles
        Defaults

        % Figures POPOUT has produced, kept so a style change reaches them too.
        PopOuts matlab.ui.Figure = matlab.ui.Figure.empty

        % What an export is made at and made on: the dots per inch a bitmap
        % is written with, and whether the paper behind the plot comes out
        % white or not at all. Both are set from the Export menu and kept for
        % the session rather than asked for again on every save.
        ExportResolution (1,1) double = 300
        ExportBackground (1,1) string = "white"

        % The two submenus those choices are made in, kept so that whichever
        % is in force can be ticked.
        ResolutionMenu matlab.ui.container.Menu
        BackgroundMenu matlab.ui.container.Menu
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

        % What the shading around a group mean measures: the spread of the
        % sections, two intervals for where their mean lies, or nothing.
        % The last of them resamples the sections rather than reading an
        % interval off a normal curve, so it does not assume one, and is
        % taken at BOOTREPS resamples -- enough for a 95% interval to be
        % steady between draws without a wait between them.
        ErrorBands = ["sem", "std", "ci95", "bootstrap 95%", "none"]
        BootReps = 2000

        % Where the key goes, from the legend in every axes to no legend at
        % all. The two in between are one legend for the whole layout, placed
        % outside the tiles rather than over any one of them.
        LegendPlacements = ["per tile", "one at top", "one at right", "none"]

        % What marks an artist as belonging to a group, what marks a menu as
        % ours to clear on the next draw, and the line styles on offer.
        StyleTag = "ECMBrowser:styled"
        MenuTag = "ECMBrowser:stylemenu"
        LineStyleNames = ["Solid", "Dashed", "Dotted", "Dash-dot"]
        LineStyleValues = ["-", "--", ":", "-."]

        % Where saved configurations live: MATLAB's own preferences, kept
        % between sessions without a file of their own to manage.
        PrefGroup = "ECMBrowser"
        PrefName = "SavedConfigs"
        NoConfig = "(none saved)"

        % Where a plot can go when it leaves the browser. EXPORTGRAPHICS
        % writes all but two of these: SVG it has no format for and PRINT
        % writes instead, and a .fig is the figure itself rather than a
        % picture of it, saved so that it can still be opened and edited.
        PlotFormats = { ...
            '*.png', 'PNG image (*.png)'; ...
            '*.pdf', 'PDF, vector (*.pdf)'; ...
            '*.tif', 'TIFF image (*.tif)'; ...
            '*.eps', 'EPS, vector (*.eps)'; ...
            '*.svg', 'SVG, vector (*.svg)'; ...
            '*.jpg', 'JPEG image (*.jpg)'; ...
            '*.fig', 'MATLAB figure (*.fig)'}

        % And where the numbers behind it can go. WRITETABLE reads the
        % delimiter off the extension, so neither needs an argument of its own.
        DataFormats = { ...
            '*.csv', 'Comma separated values (*.csv)'; ...
            '*.txt', 'Tab separated text (*.txt)'}

        % The resolutions offered, and the name a view sent to the base
        % workspace goes under before a counter is put on the end of it to
        % keep it clear of whatever is there already.
        ExportResolutions = [150 300 600 1200]
        WorkspaceVar = "ECMview"
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

            % A control that cannot affect the current view is grayed out
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

        function copyPlot(obj, options)
            %COPYPLOT Put the plot on the clipboard, without the panel beside it.
            %   B.copyPlot()
            %   B.copyPlot(ContentType = "vector")
            %
            % What the first two items of the Export menu do. An image pastes
            % into anything; vector graphics keep every curve a curve for
            % whatever will take one, which is most of what a figure ends up
            % in, and cannot be asked of the browser window itself.

            arguments
                obj
                options.ContentType (1,1) string ...
                    {mustBeMember(options.ContentType, ["image", "vector"])} = "image"
            end

            if ~obj.canExport()
                return
            end

            f = obj.exportFigure();
            closeWhenDone = onCleanup(@() delete(f));

            try
                if options.ContentType == "vector"
                    copygraphics(f, ContentType = "vector", ...
                        BackgroundColor = obj.backgroundArg())
                else
                    copygraphics(f, ContentType = "image", ...
                        Resolution = obj.ExportResolution, ...
                        BackgroundColor = obj.backgroundArg())
                end
            catch ME
                uialert(obj.Fig, ME.message, "Could not copy the plot");
                return
            end

            obj.setStatus("Plot copied to the clipboard as " + options.ContentType + ".");

        end

        function file = savePlot(obj, filename)
            %SAVEPLOT Write the plot to a file, without the panel beside it.
            %   B.savePlot()                   asks where, and in what format
            %   B.savePlot("profiles.pdf")
            %
            % The format is the extension: PNG, TIFF, and JPEG are written at
            % the resolution the Export menu is set to, PDF, EPS, and SVG as
            % vector graphics that stay sharp however large they are printed,
            % and .fig as the figure itself, to be opened and edited later.
            % What was written is handed back, and "" if the dialog was
            % canceled or the write failed.

            arguments
                obj
                filename (1,1) string = ""
            end

            file = "";

            if ~obj.canExport()
                return
            end

            if filename == ""
                filename = obj.askForFile(obj.PlotFormats, "Save plot", obj.defaultFileName());

                if filename == ""
                    return
                end
            end

            [~, ~, ext] = fileparts(filename);
            ext = lower(string(ext));

            if ext == ""
                ext = ".png";
                filename = filename + ext;
            end

            [background, note] = obj.backgroundArg(ext);

            f = obj.exportFigure();
            closeWhenDone = onCleanup(@() delete(f));

            try
                switch ext

                    case ".fig"
                        % SAVEFIG records the figure as it stands, its
                        % visibility included, and the export figure is drawn
                        % out of sight: a .fig saved from it as it is would
                        % open into a window nobody can see.
                        f.Visible = "on";
                        savefig(f, char(filename))

                    case ".svg"
                        % PRINT writes the SVG, and it has no background of
                        % its own to be told about: the paper is the figure's
                        % color, and only if the figure is also told not to
                        % have it turned white on the way out.
                        if background == "none"
                            set(f, Color = "none", InvertHardcopy = "off")
                        end

                        print(f, '-dsvg', char(filename))

                    case {".pdf", ".eps"}
                        exportgraphics(f, filename, ContentType = "vector", ...
                            BackgroundColor = background)

                    otherwise
                        exportgraphics(f, filename, ...
                            Resolution = obj.ExportResolution, ...
                            BackgroundColor = background)
                end
            catch ME
                uialert(obj.Fig, ME.message, "Could not save the plot");
                return
            end

            file = filename;
            obj.setStatus("Saved " + filename + note);

        end

        function v = viewData(obj)
            %VIEWDATA The numbers behind the plot, as one struct.
            %   v = B.viewData()
            %
            % Everything the controls have settled: the depth axis, one column
            % of intensities per section on the scale they are drawn on, the
            % rows of A.grid.files they came from, and each section's peak
            % rescaled the same way the profiles were. The plot and the numbers
            % under it come out of the same call, so a figure and the table
            % beside it cannot disagree about what was normalized or filtered.

            [idx, Y, x] = obj.currentView();

            v = struct();
            v.depth = x;
            v.values = Y;
            v.rows = idx;
            v.sections = obj.Files(idx, :);
            v.sectionNames = obj.sectionNames(idx);
            v.peakDepth = obj.Files.PeakX(idx);
            v.peakHeight = obj.peakHeights(idx);
            v.unit = obj.Unit;
            v.settings = obj.captureSettings();

        end

        function file = saveData(obj, filename, options)
            %SAVEDATA Write the numbers behind the plot to a delimited file.
            %   B.saveData()                                asks where
            %   B.saveData("profiles.csv")
            %   B.saveData("samples.csv", Layout = "long")
            %   B.saveData("sections.csv", Layout = "sections")
            %
            % Three layouts, because three different things get asked of one
            % view. "wide" is a depth column and one intensity column per
            % section, which is what a plotting program wants pasted into it.
            % "long" is one row per sample, carrying every field the sections
            % can be grouped or filtered by, which is what a statistics
            % package wants; the depths a section never reached are left out
            % rather than written as blanks. "sections" is one row per section
            % -- the table beside the profiles, with the peak added to it on
            % the scale the plot is drawn on.

            arguments
                obj
                filename (1,1) string = ""
                options.Layout (1,1) string ...
                    {mustBeMember(options.Layout, ["wide", "long", "sections"])} = "wide"
            end

            file = "";

            if ~obj.canExport()
                return
            end

            if filename == ""
                filename = obj.askForFile(obj.DataFormats, ...
                    "Save " + options.Layout + " data", ...
                    obj.defaultFileName() + " " + options.Layout);

                if filename == ""
                    return
                end
            end

            try
                T = obj.viewTable(options.Layout);
                writetable(T, filename)
            catch ME
                uialert(obj.Fig, ME.message, "Could not save the data");
                return
            end

            file = filename;
            obj.setStatus(sprintf("Saved %d row(s) to %s", height(T), filename));

        end

        function setGroupStyle(obj, field, level, opts)
            %SETGROUPSTYLE Draw one group in a color and line style of your own.
            %   B.setGroupStyle("Treatment", "GM6001", Color = [0.85 0.33 0.10])
            %   B.setGroupStyle("Treatment", "GM6001", LineStyle = "--")
            %
            % What the right-click menu does, reachable from a script. FIELD is
            % the field the group came from -- normally whatever Color by is
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
                    error("ECMBrowser:BadColor", ...
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

            % Offered alphabetically rather than in the table's own column
            % order, so a field is found by name instead of by where it
            % happens to sit in the sheet.
            obj.GroupFields = sort(obj.GroupFields);
            obj.FilterFields = sort(obj.FilterFields);

        end

        function levels = levelsOf(obj, field)
            %LEVELSOF List one field's values in the order they should be drawn.
            % Numbers sort as numbers, so plate 5 comes before plate 27 rather
            % than after it, and cannula distance -3 before -1. A field that is
            % numeric apart from a placeholder -- "n/a" for a value the sheet
            % never held -- still orders its numbers numerically; whatever does
            % not read as a number goes after them, in the text order UNIQUE
            % already put it in.

            levels = reshape(unique(obj.Text.(field)), [], 1);

            asNumber = str2double(levels);
            isNumeric = ~isnan(asNumber);

            if any(isNumeric)
                [~, order] = sort(asNumber(isNumeric));
                numeric = levels(isNumeric);
                levels = [numeric(order); levels(~isNumeric)];
            end

        end

        function buildUI(obj)
            %BUILDUI Lay out the controls beside the plot.

            obj.Fig = uifigure(Name = "ECM Browser", Position = [80 80 1280 780]);

            obj.buildMenus();

            layout = uigridlayout(obj.Fig, [1 2]);
            layout.ColumnWidth = {270, '1x'};
            layout.RowHeight = {'1x'};

            controls = uipanel(layout, Title = "Display");
            obj.PlotPanel = uipanel(layout, BorderType = "none");

            depth = obj.Data.grid.depth;

            grid = uigridlayout(controls, [22 2]);
            grid.ColumnWidth = {90, '1x'};
            grid.RowHeight = [repmat({24}, 1, 9), {300}, {24}, {'1x'}, ...
                repmat({24}, 1, 6), repmat({24}, 1, 3), {40}];
            grid.RowSpacing = 6;

            % The rows below Tile by add up to more than a window of ordinary
            % height can show, so the panel scrolls rather than dropping Config
            % and the status line off the bottom of itself.
            grid.Scrollable = "on";

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
                @() uidropdown(grid, Items = obj.ErrorBands, ...
                    Tooltip = "What the shading around a group mean measures. " + ...
                        "The bootstrap interval makes no assumption about the " + ...
                        "shape of the sections' spread and needs the " + ...
                        "Statistics and Machine Learning Toolbox."));

            obj.SectionsCheckBox = uicheckbox(grid, ...
                Text = "Sections behind the mean", ...
                Value = true, ...
                ValueChangedFcn = @(~,~) obj.refresh());
            obj.SectionsCheckBox.Layout.Column = [1 2];

            obj.GroupDropDown = obj.addRow(grid, "Color by", ...
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

            obj.LegendDropDown = obj.addRow(grid, "Legend", ...
                @() uidropdown(grid, Items = obj.LegendPlacements, ...
                    Tooltip = "One legend per plot, or one for the whole " + ...
                        "figure placed outside the plots."));

            obj.LinkCheckBox = uicheckbox(grid, Text = "Link axes", Value = true, ...
                ValueChangedFcn = @(~,~) obj.refresh());
            obj.LinkCheckBox.Layout.Column = [1 2];

            obj.TransposeCheckBox = uicheckbox(grid, ...
                Text = "Transpose axes", ...
                Value = false, ...
                Tooltip = "Draw depth down the vertical axis, surface at the top.", ...
                ValueChangedFcn = @(~,~) obj.refresh());
            obj.TransposeCheckBox.Layout.Column = [1 2];

            uibutton(grid, Text = "Reset", ButtonPushedFcn = @(~,~) obj.onReset());
            uibutton(grid, Text = "Pop out", ButtonPushedFcn = @(~,~) obj.popOut());

            obj.ConfigDropDown = obj.addRow(grid, "Config", ...
                @() uidropdown(grid, Items = cellstr(obj.NoConfig), ...
                    Tooltip = "Every control on this panel, saved under an " + ...
                        "autogenerated name and kept from one session to the next."), ...
                @(~,~) obj.onConfigSelected());

            uibutton(grid, Text = "Save", ...
                Tooltip = "Save the panel as it is now under a new name.", ...
                ButtonPushedFcn = @(~,~) obj.onSaveConfig());
            uibutton(grid, Text = "Delete", ...
                Tooltip = "Remove the configuration named above.", ...
                ButtonPushedFcn = @(~,~) obj.onDeleteConfig());

            purgeButton = uibutton(grid, Text = "Purge all saved configs", ...
                ButtonPushedFcn = @(~,~) obj.onPurgeConfigs());
            purgeButton.Layout.Column = [1 2];

            obj.StatusLabel = uilabel(grid, Text = "", WordWrap = "on", ...
                VerticalAlignment = "top");
            obj.StatusLabel.Layout.Column = [1 2];

            obj.applyDefaults();
            obj.refreshConfigList();

        end

        function control = addRow(obj, grid, labelText, makeControl, callback)
            %ADDROW Put one labeled control on the next row of the panel.

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

        function s = captureSettings(obj)
            %CAPTURESETTINGS Every control on the panel, as one struct.

            s = struct( ...
                Signal = string(obj.SignalDropDown.Value), ...
                Normalize = string(obj.NormalizeDropDown.Value), ...
                Scope = string(obj.ScopeDropDown.Value), ...
                RefMin = obj.RefMinField.Value, ...
                RefMax = obj.RefMaxField.Value, ...
                Show = string(obj.ShowDropDown.Value), ...
                ErrorBand = string(obj.ErrorDropDown.Value), ...
                SectionsBehind = obj.SectionsCheckBox.Value, ...
                Group = string(obj.GroupDropDown.Value), ...
                Tile = string(obj.TileListBox.Value), ...
                FilterField = string(obj.FilterFieldDropDown.Value), ...
                FilterValues = string(obj.FilterValuesListBox.Value), ...
                DepthMin = obj.DepthMinField.Value, ...
                DepthMax = obj.DepthMaxField.Value, ...
                Legend = string(obj.LegendDropDown.Value), ...
                Link = obj.LinkCheckBox.Value, ...
                Transpose = obj.TransposeCheckBox.Value);

        end

        function applySettings(obj, s)
            %APPLYSETTINGS Put every control on the panel into the state S describes.
            % Color by, Tile by, and Filter by name fields that belong to
            % whatever dataset was open when S was saved. Anything this
            % dataset does not also have is left as it was rather than
            % raising an error over a mismatch.

            obj.SignalDropDown.Value = s.Signal;
            obj.NormalizeDropDown.Value = s.Normalize;
            obj.ScopeDropDown.Value = s.Scope;
            obj.RefMinField.Value = s.RefMin;
            obj.RefMaxField.Value = s.RefMax;
            obj.ShowDropDown.Value = s.Show;
            obj.ErrorDropDown.Value = s.ErrorBand;
            obj.SectionsCheckBox.Value = s.SectionsBehind;

            if ismember(s.Group, string(obj.GroupDropDown.Items))
                obj.GroupDropDown.Value = s.Group;
            end

            tile = s.Tile(ismember(s.Tile, string(obj.TileListBox.Items)));

            if isempty(tile)
                tile = obj.NoField;
            end

            obj.TileListBox.Value = cellstr(tile);

            if ismember(s.FilterField, string(obj.FilterFieldDropDown.Items))
                obj.FilterFieldDropDown.Value = s.FilterField;
            else
                obj.FilterFieldDropDown.Value = obj.AllSections;
            end

            obj.onFilterFieldChanged();

            values = s.FilterValues(ismember(s.FilterValues, string(obj.FilterValuesListBox.Items)));

            if ~isempty(values)
                obj.FilterValuesListBox.Value = cellstr(values);
            end

            obj.DepthMinField.Value = s.DepthMin;
            obj.DepthMaxField.Value = s.DepthMax;
            obj.LegendDropDown.Value = obj.legendPlacement(s.Legend);
            obj.LinkCheckBox.Value = s.Link;

            % Saved before Transpose was a control, a configuration says
            % nothing about the orientation and is drawn the way it was.
            if isfield(s, "Transpose")
                obj.TransposeCheckBox.Value = s.Transpose;
            end

            obj.refresh();

        end

        function placement = legendPlacement(obj, saved)
            %LEGENDPLACEMENT The legend a saved configuration asked for.
            % Configurations saved before the placement dropdown replaced a
            % checkbox hold a logical rather than a name, and are read as the
            % per-tile legend that checkbox drew or as no legend at all.

            if islogical(saved) || isnumeric(saved)
                if saved
                    saved = "per tile";
                else
                    saved = "none";
                end
            end

            placement = string(saved);

            if ~ismember(placement, obj.LegendPlacements)
                placement = obj.LegendPlacements(1);
            end

        end

        function configs = readConfigs(obj)
            %READCONFIGS Every saved configuration, oldest first.

            if ispref(obj.PrefGroup, obj.PrefName)
                configs = getpref(obj.PrefGroup, obj.PrefName);
            else
                configs = struct("Name", {}, "Settings", {});
            end

        end

        function writeConfigs(obj, configs)
            %WRITECONFIGS Persist the configuration list across sessions.

            setpref(obj.PrefGroup, obj.PrefName, configs);

        end

        function refreshConfigList(obj, selected)
            %REFRESHCONFIGLIST Repopulate the dropdown, newest saved first.

            arguments
                obj
                selected (1,1) string = ""
            end

            configs = obj.readConfigs();

            if isempty(configs)
                obj.ConfigDropDown.Items = cellstr(obj.NoConfig);
                obj.ConfigDropDown.Value = obj.NoConfig;
                obj.ConfigDropDown.Enable = "off";
                return
            end

            names = flip(string({configs.Name}));
            obj.ConfigDropDown.Items = cellstr(names);
            obj.ConfigDropDown.Enable = "on";

            if selected ~= "" && ismember(selected, names)
                obj.ConfigDropDown.Value = selected;
            else
                obj.ConfigDropDown.Value = names(1);
            end

        end

        function onConfigSelected(obj)
            %ONCONFIGSELECTED Apply the configuration just picked from the list.

            name = string(obj.ConfigDropDown.Value);

            if name == obj.NoConfig
                return
            end

            configs = obj.readConfigs();
            match = configs(string({configs.Name}) == name);

            if isempty(match)
                return
            end

            obj.applySettings(match(1).Settings);

        end

        function onSaveConfig(obj)
            %ONSAVECONFIG Add the panel's current state to the saved list.

            configs = obj.readConfigs();
            settings = obj.captureSettings();
            name = obj.uniqueConfigName(configs, obj.describeSettings(settings));

            configs(end+1) = struct("Name", name, "Settings", settings);

            obj.writeConfigs(configs);
            obj.refreshConfigList(name);

        end

        function label = describeSettings(obj, s)
            %DESCRIBESETTINGS A name built from the choices that set the view apart:
            % what is shown, what it is colored and tiled by, whether it is
            % filtered, and how it is normalized. Left out entirely are the
            % reference and depth windows, the signal and error-band choice, the
            % legend placement, and the link/sections-behind flags -- fine-tuning
            % that would make every name different rather than saying what the
            % view is.

            label = s.Show;

            if s.Group ~= obj.NoField
                label = label + " by " + s.Group;
            end

            tile = s.Tile(s.Tile ~= obj.NoField);

            if ~isempty(tile)
                label = label + ", tiled " + strjoin(tile, " x ");
            end

            if s.FilterField ~= obj.AllSections
                label = label + ", filtered " + s.FilterField;
            end

            if s.Normalize ~= "none"
                label = label + ", " + s.Normalize;
            end

        end

        function name = uniqueConfigName(~, configs, base)
            %UNIQUECONFIGNAME BASE, or BASE with a counter if that name is taken.

            if isempty(configs)
                name = base;
                return
            end

            existing = string({configs.Name});
            name = base;
            n = 1;

            while ismember(name, existing)
                n = n + 1;
                name = base + " (" + n + ")";
            end

        end

        function onDeleteConfig(obj)
            %ONDELETECONFIG Remove the configuration currently picked from the list.

            name = string(obj.ConfigDropDown.Value);

            if name == obj.NoConfig
                return
            end

            configs = obj.readConfigs();
            configs(string({configs.Name}) == name) = [];

            obj.writeConfigs(configs);
            obj.refreshConfigList();

        end

        function onPurgeConfigs(obj)
            %ONPURGECONFIGS Delete every saved configuration, after asking once.

            if isempty(obj.readConfigs())
                return
            end

            answer = uiconfirm(obj.Fig, ...
                "Delete every saved configuration? This cannot be undone.", ...
                "Purge configurations", ...
                Options = ["Purge all", "Cancel"], ...
                DefaultOption = 2, CancelOption = 2, Icon = "warning");

            if string(answer) ~= "Purge all"
                return
            end

            obj.writeConfigs(struct("Name", {}, "Settings", {}));
            obj.refreshConfigList();

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

            colors = lines(max(numel(groups), 7));
            obj.rememberDefaults(groupField, groups, colors);

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

            placement = string(obj.LegendDropDown.Value);
            firstAx = matlab.graphics.axis.Axes.empty;

            for iTile = 1:numel(tiles)
                if nRows > 1
                    ax = nexttile(t, tiles(iTile).Index);
                else
                    ax = nexttile(t);
                end

                if iTile == 1
                    firstAx = ax;
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
                        groupField, groups(iGroup), colors(iGroup, :));

                    set(artists, 'ContextMenu', groupMenus(char(groups(iGroup))))
                end

                if tiles(iTile).Label ~= ""
                    title(ax, tiles(iTile).Label, Interpreter = "none")
                end

                grid(ax, "on")
                box(ax, "on")
                axis(ax, "tight")

                if obj.TransposeCheckBox.Value
                    % Depth down the vertical axis is read the way a section
                    % is looked at: the surface at the top, deeper below it.
                    ax.YDir = "reverse";
                end

                if placement == "per tile" && numel(groups) > 1
                    legend(ax, Interpreter = "none", Location = "best")
                end
            end

            % One legend for the layout is built after the tiles rather than
            % inside the loop, because it stands for every group in view rather
            % than for the ones one tile happens to hold.
            if ismember(placement, ["one at top", "one at right"]) && numel(groups) > 1
                drawn = ismember(tileOf, [tiles.Index]);
                obj.layoutLegend(firstAx, groupField, groups, colors, ...
                    groupOf(drawn), placement);
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

        function h = drawGroup(obj, ax, x, Y, idx, cols, groupField, groupName, color)
            %DRAWGROUP Draw one group's sections into one tile.
            % Only the first artist of a group carries a DisplayName, so the
            % legend lists groups rather than every section in them.
            %
            % Everything drawn is handed back and marked with the group it
            % belongs to and the part it plays in it, which is what lets a
            % color chosen later find its way to every tile at once.

            sty = obj.effectiveStyle(groupField, groupName);

            h = gobjects(1, 0);
            roles = strings(1, 0);

            switch string(obj.ShowDropDown.Value)

                case "peak summary"
                    rows = idx(cols);
                    [px, py] = obj.orient(obj.Files.PeakX(rows), obj.peakHeights(rows));
                    h(end+1) = scatter(ax, px, py, 42, ...
                        sty.Color, "filled", ...
                        MarkerFaceAlpha = 0.7, ...
                        DisplayName = groupName);
                    roles(end+1) = "marker";

                case "sections"
                    for iCol = 1:numel(cols)
                        [lx, ly] = obj.orient(x, Y(:, cols(iCol)));
                        h(end+1) = line(ax, lx, ly, ...
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
                            [lx, ly] = obj.orient(x, Y(:, cols(iCol)));
                            h(end+1) = line(ax, lx, ly, ...
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
                    [lo, hi] = obj.bandOf(M, n, m);

                    banded = n >= 2 & isfinite(m) & isfinite(lo) & isfinite(hi);

                    if any(banded)
                        xb = x(banded);
                        lob = lo(banded);
                        hib = hi(banded);

                        [bx, by] = obj.orient([xb; flipud(xb)], [lob; flipud(hib)]);
                        h(end+1) = fill(ax, bx, by, ...
                            sty.Color, ...
                            FaceAlpha = 0.2, ...
                            EdgeColor = "none", ...
                            HandleVisibility = "off");
                        roles(end+1) = "band";
                    end

                    [mx, my] = obj.orient(x(n >= 1), m(n >= 1));
                    h(end+1) = line(ax, mx, my, ...
                        Color = sty.Color, ...
                        LineStyle = sty.LineStyle, ...
                        LineWidth = 2, ...
                        DisplayName = sprintf("%s (n=%d)", groupName, numel(cols)));
                    roles(end+1) = "line";
            end

            obj.markStyled(h, roles, groupField, groupName, color);

        end

        function [alongX, alongY] = orient(obj, depthwise, valuewise)
            %ORIENT One pair -- coordinates or labels -- in the order the axes are in.
            % Everything drawn is worked out depth against intensity and put on
            % the axes through here, so Transpose is a swap made in one place
            % rather than a second version of every plot.

            if obj.TransposeCheckBox.Value
                [alongX, alongY] = deal(valuewise, depthwise);
            else
                [alongX, alongY] = deal(depthwise, valuewise);
            end

        end

        function lgd = layoutLegend(obj, ax, groupField, groups, colors, groupOf, placement)
            %LAYOUTLEGEND One legend for the whole layout, outside every axes.
            % The entries are stand-ins drawn at NaN rather than the curves
            % themselves. A curve belongs to one tile and a group need not
            % appear in the first of them, so a legend built from whatever sits
            % under it would list only what that tile happened to hold; drawn
            % at NaN the stand-ins change no limit, and marked with their group
            % they follow a color picked from a right-click menu the way the
            % curves do.
            %
            % MATLAB places a legend outside a tiled layout by naming the side
            % it goes on, so the horizontal band lands between the layout title
            % and the top row of plots, and the column beside the right-hand
            % one. Either way the room every tile was spending on its own copy
            % of the key goes back to the plot.

            proxies = gobjects(1, numel(groups));
            onPeaks = string(obj.ShowDropDown.Value) == "peak summary";

            for k = 1:numel(groups)
                sty = obj.effectiveStyle(groupField, groups(k));
                label = obj.legendEntry(groups(k), nnz(groupOf == groups(k)));

                if onPeaks
                    proxies(k) = scatter(ax, NaN, NaN, 42, sty.Color, "filled", ...
                        MarkerFaceAlpha = 0.7, ...
                        DisplayName = label);
                    role = "marker";
                else
                    proxies(k) = line(ax, NaN, NaN, ...
                        Color = sty.Color, ...
                        LineStyle = sty.LineStyle, ...
                        LineWidth = 2, ...
                        DisplayName = label);
                    role = "line";
                end

                obj.markStyled(proxies(k), role, groupField, groups(k), colors(k, :));
            end

            lgd = legend(proxies);
            lgd.Interpreter = "none";

            if placement == "one at top"
                % Wrapped rather than run out in a single line, so a dozen
                % groups stay inside the figure instead of off the edge of it.
                lgd.NumColumns = min(numel(groups), 6);
                lgd.Layout.Tile = "north";
            else
                lgd.Orientation = "vertical";
                lgd.Layout.Tile = "east";
            end

        end

        function label = legendEntry(obj, groupName, n)
            %LEGENDENTRY What one group is called in a legend for the whole layout.
            % A group mean is named with the sections behind it, as it is in a
            % legend of its own tile, but counted across every tile drawn: one
            % legend stands for all of them.

            if string(obj.ShowDropDown.Value) == "group mean"
                label = sprintf("%s (n=%d)", groupName, n);
            else
                label = groupName;
            end

        end

        function y = peakHeights(obj, rows)
            %PEAKHEIGHTS The section peaks on the scale the profiles are drawn on.
            % A.peaks holds one height per section in the units it was measured
            % in, so the transform that rescaled the profiles has to reach it
            % too; a summary read beside a normalized plot would otherwise be
            % answering a different question from the one on screen.

            center = obj.Norm.center(:);
            scale = obj.Norm.scale(:);

            y = (obj.Files.PeakY(rows) - center(rows)) ./ scale(rows);

        end

        function [lo, hi] = bandOf(obj, M, n, m)
            %BANDOF The edges of one group's error band at each depth.
            % Returned as two edges rather than one half-width because a
            % bootstrap interval need not sit evenly around the mean: a
            % skewed set of sections gives a band with a longer side, and
            % that asymmetry is the reason to have asked for the interval.

            sd = std(M, 0, 2, "omitnan");

            switch string(obj.ErrorDropDown.Value)
                case "sem"
                    e = sd ./ sqrt(n);
                case "std"
                    e = sd;
                case "ci95"
                    e = 1.96 * (sd ./ sqrt(n));
                case "bootstrap 95%"
                    [lo, hi] = obj.bootBand(M);
                    return
                otherwise
                    e = nan(size(sd));
            end

            lo = m - e;
            hi = m + e;

        end

        function [lo, hi] = bootBand(obj, M)
            %BOOTBAND A bootstrap interval for one group's mean at each depth.
            % The sections are what was sampled, so a resample draws whole
            % sections and is read at every depth at once. Resampling depth by
            % depth would put a different pretend group behind each point and
            % return a band narrower and smoother than the sections it came
            % from -- the profiles are one measurement down a section, not a
            % row of independent ones.
            %
            % The interval is the percentile one: it is read straight off the
            % resampled means, so a group whose sections are all alike gives a
            % band of no width rather than an error, where the bias-corrected
            % default has nothing to correct against and returns nothing.
            % BOOTCI belongs to the Statistics and Machine Learning Toolbox,
            % and without it -- or on any other failure -- the band is left
            % out rather than the plot.

            nDepth = size(M, 1);
            [lo, hi] = deal(nan(nDepth, 1));

            if size(M, 2) < 2
                return
            end

            try
                ci = bootci(obj.BootReps, ...
                    {@(sections) mean(sections, 1, "omitnan"), M.'}, ...
                    "type", "percentile");
            catch
                return
            end

            lo = ci(1, :).';
            hi = ci(2, :).';

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

            Y = (Y - obj.Norm.center) ./ obj.Norm.scale;

            inDepth = x >= obj.DepthMinField.Value & x <= obj.DepthMaxField.Value;
            x = x(inDepth);
            Y = Y(inDepth, idx);

        end

        function n = normalizationOf(obj, depth, reference, inView)
            %NORMALIZATIONOF The rescaling the normalization controls describe.
            % Every mode is one affine map -- subtract a center, divide by a
            % scale -- so a mode is a choice of which statistic those two
            % numbers are read from, and a scope is a choice of how many
            % sections are pooled to read it. One pair of vectors then rescales
            % the profile grid and the section peaks alike. REFERENCE is the
            % smoothed grid over the whole depth axis; the reference window and
            % the sections in view are applied here.

            nSections = size(reference, 2);

            center = zeros(1, nSections);
            scale = ones(1, nSections);

            mode = string(obj.NormalizeDropDown.Value);

            if mode == "none"
                n = struct("center", center, "scale", scale, "degenerate", 0);
                return
            end

            inRef = depth >= obj.RefMinField.Value & depth <= obj.RefMaxField.Value;

            if ~any(inRef)
                n = struct("center", center, "scale", scale, "degenerate", nnz(inView));
                return
            end

            xRef = depth(inRef);
            R = reference(inRef, :);

            poolId = obj.poolOf(inView);
            pools = unique(poolId(~isnan(poolId)));

            for iPool = 1:numel(pools)
                inPool = poolId == pools(iPool);

                [poolCenter, poolScale] = pool_stats(mode, xRef, R(:, inPool));

                center(inPool) = poolCenter;
                scale(inPool) = poolScale;
            end

            % A pool the transform cannot be taken from -- one that never
            % reached the reference window, one that is flat inside it, or one
            % whose divisor is not positive because the profiles were already
            % centered on zero upstream -- is left in its own units rather than
            % blown up by a scale near zero, and its sections are counted so
            % that the status line can say it happened.
            usable = isfinite(center) & isfinite(scale) & scale > 0;

            center(~usable) = 0;
            scale(~usable) = 1;

            n = struct("center", center, "scale", scale, ...
                "degenerate", sum(~usable & ~isnan(poolId)));

        end

        function poolId = poolOf(obj, inView)
            %POOLOF Label each section with the sections it shares a scale with.
            % A section that is filtered out is left unlabeled: it is not on
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
                depthLabel = obj.withUnit("peak depth from surface");
                valueLabel = obj.withNormalization(strtrim(obj.peakSource() + " peak intensity"));
            else
                depthLabel = obj.withUnit("depth from cortical surface");
                valueLabel = obj.withNormalization(string(obj.SignalDropDown.Value) + " intensity");
            end

            % The names follow the axes they are on, so a transposed plot is
            % labeled the way it is drawn rather than the way it was worked out.
            [alongX, alongY] = obj.orient(depthLabel, valueLabel);

            xlabel(t, alongX)
            ylabel(t, alongY)

            if groupField == obj.NoField
                title(t, "all sections")
            else
                title(t, "colored by " + groupField, Interpreter = "none")
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
            % The field is part of it so that a color picked for Treatment
            % GM6001 is still there after a look at the same sections split by
            % Hemisphere, rather than following the palette slot it happened to
            % share with a hemisphere.

            key = char(field + "|" + level);

        end

        function rememberDefaults(obj, groupField, groups, colors)
            %REMEMBERDEFAULTS Note the palette color each group started from.
            % The menu needs it to open the color picker on the color actually
            % on screen, and a reset needs it to have somewhere to go back to.

            for k = 1:numel(groups)
                obj.Defaults(obj.styleKey(groupField, groups(k))) = colors(k, :);
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

        function markStyled(obj, h, roles, field, level, color)
            %MARKSTYLED Say which group an artist draws, and what part of it.
            % The palette color is written onto the artist rather than looked
            % up again later, so a popped-out figure keeps the colors it was
            % drawn with even after the panel behind it has been regrouped.

            for k = 1:numel(h)
                h(k).Tag = char(obj.StyleTag);
                h(k).UserData = struct( ...
                    Field = field, ...
                    Group = level, ...
                    Role = roles(k), ...
                    Color = color);
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
            % drawn faintly behind a mean carry their transparency in the color
            % itself, so each part of a group is put back its own way.

            mark = h.UserData;
            key = obj.styleKey(mark.Field, mark.Group);

            color = mark.Color;
            lineStyle = "-";

            if isKey(obj.Styles, key)
                chosen = obj.Styles(key);

                if ~isempty(chosen.Color)
                    color = chosen.Color;
                end

                if chosen.LineStyle ~= ""
                    lineStyle = chosen.LineStyle;
                end
            end

            switch mark.Role
                case "line"
                    h.Color = color;
                    h.LineStyle = lineStyle;

                case "faint"
                    h.Color = [color 0.25];
                    h.LineStyle = lineStyle;

                case "band"
                    h.FaceColor = color;

                case "marker"
                    h.CData = color;
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
            %ADDSTYLEITEMS The color, line style, and reset one group offers.
            % PREFIX names the group in the items when they sit at the top of a
            % menu, and is empty when they sit under a submenu already carrying
            % the name.

            uimenu(parent, Text = prefix + "Color...", ...
                MenuSelectedFcn = @(~, ~) obj.pickColor(groupField, level));

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

        function buildMenus(obj)
            %BUILDMENUS Everything that leaves the browser, sorted by what it
            % makes. The panel beside the plot is for arriving at a figure;
            % these menus are for taking one away, and nothing on them
            % changes what is drawn.

            obj.buildPlotMenu();
            obj.buildDataMenu();
            obj.buildExportOptionsMenu();

        end

        function buildPlotMenu(obj)
            %BUILDPLOTMENU The picture itself: copy it, save it, set it free.

            m = uimenu(obj.Fig, Text = "Plot");

            copyTo = uimenu(m, Text = "Copy");

            uimenu(copyTo, Text = "To the clipboard", ...
                MenuSelectedFcn = @(~,~) obj.copyPlot());
            uimenu(copyTo, Text = "To the clipboard as vector graphics", ...
                MenuSelectedFcn = @(~,~) obj.copyPlot(ContentType = "vector"));

            uimenu(m, Text = "Save plot as...", ...
                MenuSelectedFcn = @(~,~) obj.savePlot());
            uimenu(m, Text = "Pop out to a figure window", Separator = "on", ...
                MenuSelectedFcn = @(~,~) obj.popOut());

        end

        function buildDataMenu(obj)
            %BUILDDATAMENU The numbers behind the picture, on their way out.

            m = uimenu(obj.Fig, Text = "Data");

            copyTo = uimenu(m, Text = "Copy");

            uimenu(copyTo, Text = "The profiles to the clipboard", ...
                MenuSelectedFcn = @(~,~) obj.onCopyData());
            uimenu(copyTo, Text = "A summary of this view to the clipboard", ...
                MenuSelectedFcn = @(~,~) obj.copySummary());

            uimenu(m, Text = "Send this view to the workspace", ...
                MenuSelectedFcn = @(~,~) obj.onSendToWorkspace());

            saveAs = uimenu(m, Text = "Save as...", Separator = "on");

            uimenu(saveAs, Text = "Profiles, one column per section...", ...
                MenuSelectedFcn = @(~,~) obj.saveData(Layout = "wide"));
            uimenu(saveAs, Text = "Profiles, one row per sample...", ...
                MenuSelectedFcn = @(~,~) obj.saveData(Layout = "long"));
            uimenu(saveAs, Text = "The section table...", ...
                MenuSelectedFcn = @(~,~) obj.saveData(Layout = "sections"));

        end

        function buildExportOptionsMenu(obj)
            %BUILDEXPORTOPTIONSMENU How the saved and copied plots come out.

            m = uimenu(obj.Fig, Text = "Export options");

            obj.ResolutionMenu = uimenu(m, Text = "Image resolution");

            for dpi = obj.ExportResolutions
                uimenu(obj.ResolutionMenu, Text = dpi + " dpi", UserData = dpi, ...
                    MenuSelectedFcn = @(src,~) obj.chooseResolution(src.UserData));
            end

            obj.BackgroundMenu = uimenu(m, Text = "Background");

            uimenu(obj.BackgroundMenu, Text = "White", UserData = "white", ...
                MenuSelectedFcn = @(src,~) obj.chooseBackground(src.UserData));
            uimenu(obj.BackgroundMenu, Text = "Transparent (vector formats only)", ...
                UserData = "transparent", ...
                MenuSelectedFcn = @(src,~) obj.chooseBackground(src.UserData));

            obj.tickOption(obj.ResolutionMenu, obj.ExportResolution);
            obj.tickOption(obj.BackgroundMenu, obj.ExportBackground);

        end

        function chooseResolution(obj, dpi)
            %CHOOSERESOLUTION Write the bitmap formats at DPI from here on.

            obj.ExportResolution = dpi;
            obj.tickOption(obj.ResolutionMenu, dpi);

        end

        function chooseBackground(obj, background)
            %CHOOSEBACKGROUND Put white paper behind an export, or none at all.

            obj.ExportBackground = background;
            obj.tickOption(obj.BackgroundMenu, background);

        end

        function tickOption(~, menu, value)
            %TICKOPTION Mark which of a submenu's choices is the one in force.

            items = menu.Children;

            for k = 1:numel(items)
                items(k).Checked = matlab.lang.OnOffSwitchState( ...
                    isequal(items(k).UserData, value));
            end

        end

        function f = exportFigure(obj)
            %EXPORTFIGURE The plot on screen, redrawn into a plain figure of its own.
            % Everything leaves the browser through one of these rather than
            % through the window itself. The panel of controls is half of that
            % window and no part of the figure anyone wants to keep, and a
            % uifigure is not something EXPORTGRAPHICS will give vector output
            % for. The figure is built at the size the plot is on screen and
            % then handed the limits its axes were left at, so a zoom is
            % exported instead of being thrown away by the redraw. Whoever
            % asks for one deletes it.

            f = figure(Visible = "off", Name = "ECM Browser export", ...
                NumberTitle = "off", Color = "w", PaperPositionMode = "auto");

            panelSize = obj.PlotPanel.Position(3:4);

            if all(isfinite(panelSize)) && all(panelSize > 200)
                f.Position(3:4) = panelSize;
            end

            obj.draw(f);
            obj.matchLimits(f);
            obj.stripStyleMenus(f);

        end

        function stripStyleMenus(~, f)
            %STRIPSTYLEMENUS Take the right-click menus back off an export.
            % Every item on them is a callback into this browser, and a .fig
            % saved with one holds everything that callback closes over --
            % which is the browser, and through it the whole analysis struct.
            % An export is a figure rather than a browser, so the menus come
            % off before it goes anywhere: what is left is a plot that can be
            % saved, loaded, and edited on its own.

            set(findall(f, '-property', 'ContextMenu'), 'ContextMenu', [])
            delete(findall(f, 'Type', 'uicontextmenu'))

        end

        function matchLimits(obj, f)
            %MATCHLIMITS Put the export figure on the limits the plot is left at.
            % A redraw opens on the whole depth window, so without this a plot
            % zoomed in by hand would export zoomed out. Both figures come out
            % of the same draw and so list their axes in the same order; if
            % they somehow do not, the export is left on its own limits rather
            % than given the wrong ones.

            onScreen = findobj(obj.PlotPanel, "Type", "axes");
            exported = findobj(f, "Type", "axes");

            if isempty(onScreen) || numel(onScreen) ~= numel(exported)
                return
            end

            for k = 1:numel(exported)
                exported(k).XLim = onScreen(k).XLim;
                exported(k).YLim = onScreen(k).YLim;
            end

        end

        function ok = canExport(obj)
            %CANEXPORT Refuse to export a plot with nothing in it.

            ok = ~isempty(obj.currentView());

            if ~ok
                uialert(obj.Fig, ...
                    "No sections match the current filter, so there is nothing to export.", ...
                    "Nothing to export", Icon = "warning");
            end

        end

        function [color, note] = backgroundArg(obj, ext)
            %BACKGROUNDARG What goes behind the plot in a file of this kind.
            % Transparency is something only the vector formats carry: PNG,
            % TIFF, and JPEG are written on white whatever is asked of them,
            % and MATLAB says so on the console rather than where the choice
            % was made, so it is said here instead and the caller puts it in
            % the status line. A .fig has no paper behind it to argue about,
            % being the figure itself rather than a picture of one.

            arguments
                obj
                ext (1,1) string = "clipboard"
            end

            color = "white";
            note = "";

            if obj.ExportBackground ~= "transparent"
                return
            end

            if ismember(ext, [".pdf", ".eps", ".svg", "clipboard"])
                color = "none";
            elseif ext ~= ".fig"
                note = ", on white -- no bitmap format holds transparency";
            end

        end

        function file = askForFile(obj, filters, dialogTitle, defaultName)
            %ASKFORFILE Ask where a file should go, and give the app the front back.
            % A file dialog is a window of its own, and closing it leaves the
            % window it was opened from behind whatever else is on screen.

            [name, folder] = uiputfile(filters, char(dialogTitle), char(defaultName));
            figure(obj.Fig)

            if isequal(name, 0)
                file = "";
                return
            end

            file = string(fullfile(folder, name));

        end

        function name = defaultFileName(obj)
            %DEFAULTFILENAME A name for the file that says what the view is.
            % The sentence a saved configuration is named with already holds
            % what is shown and what it is split by, so the file is offered
            % under the same one, with the characters a name cannot hold
            % taken back out of it.

            name = "ECM " + obj.describeSettings(obj.captureSettings());
            name = regexprep(name, '[<>:"/\\|?*]', "-");
            name = strtrim(regexprep(name, '\s+', " "));

            if strlength(name) > 96
                name = extractBefore(name, 97);
            end

        end

        function names = sectionNames(obj, rows)
            %SECTIONNAMES What each section is called where a column needs a name.
            % Whatever the sheet called the section if it called it anything,
            % and its row in A.grid.files if it did not; made into valid
            % variable names, and made unique, because a table of one column
            % per section needs them to be both.

            candidates = ["SectionID", "Section", "SectionName", "ImageName", ...
                "FileName", "Filename", "Name", "file_id"];
            available = candidates(ismember(candidates, ...
                string(obj.Files.Properties.VariableNames)));

            if isempty(available)
                names = "section" + string(rows(:));
            else
                names = string(obj.Files.(available(1))(rows));
                names = names(:);

                blank = ismissing(names) | strlength(names) == 0;
                names(blank) = "section" + string(rows(blank));
            end

            names = string(matlab.lang.makeUniqueStrings( ...
                matlab.lang.makeValidName(names)));

        end

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
                    fields = string(fieldnames(obj.Text));

                    for iField = 1:numel(fields)
                        if ismember(fields(iField), string(T.Properties.VariableNames))
                            continue
                        end

                        T.(fields(iField)) = ...
                            repelem(obj.Text.(fields(iField))(v.rows), nDepth, 1);
                    end

                    % A section is interpolated onto the shared depth axis and
                    % holds nothing outside the depths it measured, which in a
                    % row-per-sample table is a row with no measurement in it.
                    T(~isfinite(T.Value), :) = [];

                case "sections"
                    T = writable_columns(v.sections);

                    % The peak on the scale the profiles beside it are drawn
                    % on, which is the one thing this table does not already
                    % hold: PeakY is in the units it was measured in.
                    T.PeakY_drawn = v.peakHeight;

                    named = matlab.lang.makeUniqueStrings( ...
                        ["Section", string(T.Properties.VariableNames)], 1);
                    T = addvars(T, v.sectionNames(:), Before = 1, ...
                        NewVariableNames = named(1));
            end

        end

        function onCopyData(obj)
            %ONCOPYDATA Put the drawn profiles on the clipboard, ready to paste.
            % Tab separated, which is what a spreadsheet and a statistics
            % program both read out of a paste. WRITETABLE is what knows how
            % to turn a table of mixed columns into text, so it writes one to
            % a scratch file and the file is read straight back.

            if ~obj.canExport()
                return
            end

            scratch = string(tempname) + ".txt";
            cleanUp = onCleanup(@() delete_if_present(scratch));

            try
                writetable(obj.viewTable("wide"), scratch, Delimiter = "\t")
                clipboard("copy", fileread(scratch))
            catch ME
                uialert(obj.Fig, ME.message, "Could not copy the profiles");
                return
            end

            obj.setStatus("Profiles copied to the clipboard, one column per section.");

        end

        function onSendToWorkspace(obj)
            %ONSENDTOWORKSPACE Put the numbers behind the plot in the base workspace.
            % Under a name nothing there already holds: an export that quietly
            % replaced someone else's variable would be worse than one that
            % picked a name of its own and said which.

            if ~obj.canExport()
                return
            end

            v = obj.viewData();
            name = string(matlab.lang.makeUniqueStrings( ...
                char(obj.WorkspaceVar), evalin("base", "who")));

            assignin("base", name, v);

            uialert(obj.Fig, sprintf( ...
                "%d section(s) over %d depth(s) is in the base workspace as %s.", ...
                numel(v.rows), numel(v.depth), name), ...
                "Sent to the workspace", Icon = "success");

        end

        function copySummary(obj)
            %COPYSUMMARY Put a written account of the view on the clipboard.
            % Every choice that decides what the plot means -- the scale, how
            % many sections were pooled to set it, what is shown, split, and
            % filtered -- which is what a figure legend or a methods paragraph
            % has to say, and what a picture of the plot does not hold.

            s = obj.captureSettings();

            lines = "ECM Browser view";
            lines(end+1) = "  Signal: " + s.Signal;
            lines(end+1) = "  Normalize: " + s.Normalize;

            if s.Normalize ~= "none"
                lines(end) = lines(end) + " (" + s.Scope + "), reference " + ...
                    s.RefMin + " to " + s.RefMax;
            end

            lines(end+1) = "  Show: " + s.Show;

            if s.Show == "group mean"
                lines(end) = lines(end) + ", error band " + s.ErrorBand;

                if s.ErrorBand == "bootstrap 95%"
                    lines(end) = lines(end) + " (percentile, " + ...
                        obj.BootReps + " resamples of the sections)";
                end

                lines(end) = lines(end) + ...
                    ", sections behind the mean: " + string(logical(s.SectionsBehind));
            end

            lines(end+1) = "  Color by: " + s.Group;
            lines(end+1) = "  Tile by: " + strjoin(s.Tile, " x ");
            lines(end+1) = "  Filter: " + s.FilterField;

            if s.FilterField ~= obj.AllSections
                lines(end) = lines(end) + " = " + strjoin(s.FilterValues, ", ");
            end

            lines(end+1) = "  " + obj.withUnit("Depth") + ": " + ...
                s.DepthMin + " to " + s.DepthMax;
            lines(end+1) = "  " + obj.StatusLabel.Text;

            try
                clipboard("copy", strjoin(lines, newline))
            catch ME
                uialert(obj.Fig, ME.message, "Could not copy the summary");
                return
            end

            obj.setStatus("View summary copied to the clipboard.");

        end

        function pickColor(obj, groupField, level)
            %PICKCOLOR Ask for a color for one group and put it on every plot.
            % UISETCOLOR hands back what it was opened on when it is canceled,
            % so a cancel quietly sets the color the group already had.

            sty = obj.effectiveStyle(groupField, level);
            chosen = uisetcolor(sty.Color, char("Color for " + level));

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

function [center, scale] = pool_stats(mode, x, R)
%POOL_STATS The center and scale one pool of sections is rescaled by.
% R holds every sample the pool contributes inside the reference window, and
% the statistic is taken over the whole block rather than column by column: a
% pool of one section and a pool of a whole plot are then the same arithmetic,
% and pooling keeps the differences between the sections it holds instead of
% flattening them the way rescaling each section separately does.

v = R(:);

center = 0;
scale = 1;

switch mode

    case "z-score"
        center = mean(v, 1, "omitnan");
        scale = std(v, 0, 1, "omitnan");

    case "min-max"
        center = min(v, [], 1, "omitnan");
        scale = max(v, [], 1, "omitnan") - center;

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
        center = median(v, 1, "omitnan");

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

function T = writable_columns(T)
%WRITABLE_COLUMNS Drop the columns WRITETABLE has nothing to write.
% A section table can carry a container per row rather than a value -- the
% profile itself, a list of the value files it was read from -- and one of
% those turns a CSV that would otherwise have been fine into an error.

names = string(T.Properties.VariableNames);
drop = false(1, numel(names));

for k = 1:numel(names)
    col = T.(names(k));
    drop(k) = (iscell(col) && ~all(cellfun(@ischar, col))) || ...
        istable(col) || isstruct(col) || ~ismatrix(col);
end

T(:, drop) = [];

end

function delete_if_present(file)
%DELETE_IF_PRESENT Remove a scratch file, and say nothing if it never appeared.

if isfile(file)
    delete(file)
end

end
