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
% The controls are gathered into sections that open and close from the bar
% naming each one -- Signal & scale, Compare, Plot, Split, Filter, Layout,
% and Configurations. Any one figure is settled by three or four controls,
% not by all two dozen, so the panel opens on the sections most figures are
% made of and leaves the rest shut. A shut section says on its own bar what
% it is holding -- the comparison in force, how many filter conditions are
% standing -- so nothing narrows the plot from out of sight, and a count of
% what is drawn runs along the foot of the window under both halves of it.
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
%   Compare     Measures one level of a field against another within the same
%               subject, plate, or whatever else the sections are matched on,
%               and draws the comparison in place of the sections it came
%               from. A difference, a ratio, a log2 ratio, a percent change,
%               or a normalized difference (a - b) / (a + b), which is bounded
%               and is what a laterality index usually means.
%   Compare by  The field whose values are being measured against each other
%               -- Hemisphere, say.
%   Reference   Which of that field's values is b, the one everything else is
%               measured against. A field of three or more values yields one
%               comparison per value against the reference rather than only
%               a pair. Some fields have no such value -- subject is the
%               plain case, one animal being no more the reference than
%               another -- and are asked about within themselves by the two
%               choices at the head of the list instead. Each vs. the rest
%               measures every value against all the sections of the match
%               that hold another value, which is one curve per value and is
%               how an outlying subject shows itself; every pair measures
%               each two values against each other once, which is every
%               comparison there is to make and grows quickly with the number
%               of values.
%   Pair within Which fields have to agree for two sections to be compared.
%               Subject and plate is the usual answer: a left section is
%               measured against the right section of the same plate of the
%               same animal, not against every right section in the study.
%               Where a match holds more than one section on a side, the two
%               sides are averaged first and the comparison taken between the
%               averages, so one section against one and three against two
%               are handled the same way. A match missing the reference value
%               yields nothing and its sections are counted in the status
%               line. Comparisons are taken after the normalization, so a
%               scope that rescales the two sides separately -- per group,
%               with Color by set to the compared field -- would take out the
%               difference before it is measured.
%   Show        Every section, the group mean with an error band, or one point
%               per section: the peak summary in peak depth against peak
%               intensity, or the metric summary in whichever single number
%               of the curve the Metric control names, plotted down the
%               groups. A comparison is drawn in place of the sections, so
%               its curves are what is shown, averaged, and summarized, and
%               its peak is the depth it departs furthest from no difference
%               -- zero, or one for a ratio.
%   Metric      What one point of the metric summary measures, for the metric
%               summary alone: how much signal there is under the curve (its
%               mean, median, or integral), where it is (peak height and
%               depth, the two peaks a double-peaked profile has and the
%               separation between them, the centroid), how wide it is
%               (FWHM), or how much it varies (range, variance, standard
%               deviation, coefficient of variation, slope). Unlike the peak
%               summary, which reads A.peaks as ecm_prepare_analysis_data
%               measured it, these are read off the curve on screen: the
%               depth window, the signal, the normalization, and a comparison
%               all reach them, so the summary and the plot beside it are
%               always answering the same question. Sections are drawn as one
%               point each, spread across their group's place on the axis,
%               with the group's mean ruled through them and the error band
%               drawn as a bar rather than as a band.
%   Error band  What the band around a group mean spans, and what the bar
%               through a metric summary's group spans: the spread of its
%               sections, a normal interval for their mean, or a bootstrap
%               one that resamples the sections instead of assuming a shape
%               for them and may sit unevenly around the mean.
%   Color by   Field whose values become the groups. Legend entries are per
%               group, not per section, so a plot of 85 sections still has a
%               legend that fits. Under a comparison the compared field holds
%               the comparison instead of its own values, so coloring by
%               Hemisphere colors by "Right - Left" rather than by Right and
%               Left, and every other field carries whatever the sections
%               behind a comparison agreed on, or "(mixed)" where they did not.
%   Tile by     Fields whose values each get their own axes. Pick more than
%               one -- plate and subject, say -- and every combination the
%               sections actually hold gets an axes of its own: the last field
%               runs across the columns and the ones before it down the rows,
%               so a column can be read from row to row. Transpose swaps
%               the two.
%   Filter by   Which field is being narrowed, and which of its values to
%               keep -- or, with Values set to drop, to throw out. A field
%               is remembered once it has been narrowed, so moving on to a
%               second field adds a condition beside the first rather than
%               replacing it, and several parameters are filtered on at
%               once. Putting every value of a field back selects nothing
%               and takes its condition off the list again.
%   Combine     Whether a section has to satisfy all of the conditions or
%               any one of them -- an AND across them, or an OR. Offered
%               once there are two conditions to combine, one condition
%               meaning the same thing under either rule.
%   Filters     The conditions standing, one to a line. Picking one puts the
%               two controls above back on the field it names, so it can be
%               widened or narrowed where it is; Remove takes it off and
%               Clear all empties the list. Filters pick sections rather
%               than comparisons, so they are applied before any pairing and
%               narrow what there is to compare.
%   Depth       The depth window drawn, in the profiles' own distance unit.
%   Transpose   Turns the grid of axes on its side: the field that ran
%               across the columns runs down the rows instead, and the ones
%               before it across the columns. It rearranges the axes rather
%               than what is drawn in them, so everything else -- the
%               normalization, the curves, the legend, an export -- is
%               unchanged by it. One tiled field flows across the layout
%               untransposed and stacks into a single column transposed.
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
% Configurations, the last section of the panel, remembers the state of every
% control above -- not a color or line style set from a right-click menu,
% which is
% kept of its own accord. Save adds the state on screen now to the list under
% an autogenerated name; picking a name back out of the list puts the panel
% back the way it was; Delete removes the name showing, and Purge every name
% at once. The list is kept in MATLAB's own preferences rather than a file of
% its own, so it survives from one ECMBrowser to the next, and a config saved
% against a field this dataset does not have -- a color-by, tile-by, or
% filter field from a different one -- is left unset rather than refused.
%
% A toolbar sits over the plot, holding the things reached for over and over
% while a figure is being settled on: copy the plot as an image or as vector
% graphics, save it, copy the numbers under it or the account of the view,
% send them to the workspace, pop the plot out into a figure of its own, and
% Reset, which puts the depth window, the scale, and the filter back. All but
% the last are on the Plot and Data menus as well, spelled out at more length
% there; the toolbar is the short way to the few that get used every time.
%
% Export, on the menu bar, is how anything leaves the browser, and what it
% sends out is the plot alone -- the panel of controls is how a figure was
% arrived at, not part of it. The plot is redrawn into a plain figure for
% each export, at the size it is on screen and on the limits it was left at,
% so a zoom is exported rather than thrown away and a vector format is
% available, which it is not from a uifigure. Copy puts it on the clipboard
% as a PNG or as vector graphics; Save plot writes PNG, TIFF, or JPEG for
% a bitmap, PDF, EPS, or SVG for something that stays sharp at any size, and
% .fig for the figure itself, still open to editing. Data sends the numbers
% under the plot the same way: to the base workspace, to the clipboard, or
% to a CSV -- one column per section for a plotting program, one row per
% sample carrying every field the sections can be split by for a statistics
% package, or one row per section for the peaks and the summary metric in
% force. Under a comparison a column
% is a comparison rather than a section, and the last of the three says what
% was measured against what, how many sections went into each side of it,
% and where it departs furthest from no difference. Image resolution and
% Background set what the bitmap formats are written at and whether the
% paper behind the plot is white or left out altogether, which only the
% vector formats can do; both are kept for the session. Copy view summary writes out every choice that decides what
% the plot means, which is what a methods paragraph needs and a screenshot
% does not hold. Copy code writes the same view out as the commands that
% rebuild it -- setComparison, setTiling, and the rest, one line each --
% which is what belongs in the script that makes the figure for the paper,
% and is the only way a color picked from a right-click menu leaves the
% browser at all.
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
        CompareDropDown matlab.ui.control.DropDown
        CompareFieldDropDown matlab.ui.control.DropDown
        CompareRefDropDown matlab.ui.control.DropDown
        PairListBox matlab.ui.control.ListBox
        ShowDropDown matlab.ui.control.DropDown
        MetricDropDown matlab.ui.control.DropDown
        ErrorDropDown matlab.ui.control.DropDown
        SectionsCheckBox matlab.ui.control.CheckBox
        GroupDropDown matlab.ui.control.DropDown
        TileListBox matlab.ui.control.ListBox
        FilterFieldDropDown matlab.ui.control.DropDown
        FilterValuesListBox matlab.ui.control.ListBox
        FilterSenseDropDown matlab.ui.control.DropDown
        FilterMatchDropDown matlab.ui.control.DropDown
        FilterListBox matlab.ui.control.ListBox
        DepthMinField matlab.ui.control.NumericEditField
        DepthMaxField matlab.ui.control.NumericEditField
        LegendDropDown matlab.ui.control.DropDown
        SpacingDropDown matlab.ui.control.DropDown
        PaddingDropDown matlab.ui.control.DropDown
        TickLabelDropDown matlab.ui.control.DropDown
        LinkCheckBox matlab.ui.control.CheckBox
        TransposeCheckBox matlab.ui.control.CheckBox
        AxisQuantityCheckBox matlab.ui.control.CheckBox
        ConfigDropDown matlab.ui.control.DropDown
        StatusLabel matlab.ui.control.Label
    end

    properties (Access = private)
        % The collapsible groups the controls above are gathered into. One
        % entry per group, in the order they are stacked: the header button
        % that opens and closes it, the dimmed label beside that header
        % saying what a closed group is holding, the grid its controls live
        % in, and how tall that grid has to be when the group is open. The
        % row of SECTIONGRID each one occupies is what actually opens and
        % closes -- a grid row cannot be hidden, so it is set to the height
        % of the header alone and the controls under it are hidden with it.
        SectionGrid matlab.ui.container.GridLayout
        Sections struct = struct("Key", {}, "Title", {}, "Row", {}, ...
            "Header", {}, "Summary", {}, "Body", {}, "Height", {}, "Open", {})
    end

    properties (SetAccess = private)
        % Which sections are being kept, as one condition per field: the
        % values of that field to keep, or -- with KEEP false -- to throw
        % out. Every other control holds its own state, but a list of
        % conditions is more than a control can carry, so the three filter
        % controls are an editor onto this and FILTERMATCHDROPDOWN says
        % whether a section has to satisfy all of them or any one.
        %
        % A field appears here at most once. A condition that constrains
        % nothing -- every value kept, or none thrown out -- is taken off
        % rather than stored, so an empty list means every section is drawn.
        Filters struct = struct("Field", {}, "Values", {}, "Keep", {})
    end

    properties (Access = private)
        % The transform the normalization controls describe: one center and one
        % scale per section, taken once per draw so that the profiles and the
        % peaks drawn beside them are rescaled by the same two numbers.
        Norm struct = struct("center", 0, "scale", 1, "degenerate", 0)

        % What each column of the plot holds. Without a comparison a column
        % is a section, and the roster is A.grid.files itself: a column index
        % is a row of that table, which is what every split, export, and peak
        % has always taken it for. With a comparison a column is two groups of
        % sections measured against each other, and the roster is built for
        % it -- one entry per comparison carrying the same fields a section
        % carries, so nothing downstream has to know which of the two it is
        % looking at. Set once per draw by CURRENTVIEW, beside the transform.
        View struct = struct()

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

        % ALIGNLABELS calls DRAWNOW in a loop while a refresh is under way,
        % which flushes any control callback queued behind it. Running that
        % callback's own refresh right then would delete the panel out from
        % under the label handles the paused call is still holding, so a
        % refresh already in progress is tracked here and a nested one is
        % deferred instead of run.
        IsRefreshing (1,1) logical = false
        RefreshPending (1,1) logical = false
    end

    properties (Constant, Access = private)
        NoField = "(none)"
        AllSections = "(all sections)"
        Mixed = "(mixed)"
        MaxGroupLevels = 25
        MaxFilterLevels = 100
        MaxTiles = 64

        % Whether a filter condition keeps the values picked or throws them
        % out, and how several conditions are combined: a section has to
        % satisfy all of them, or any one of them. Both are written the way
        % they are asked about rather than in the words of the arithmetic,
        % with the operator named after them for whoever thinks in it.
        FilterSenses = ["keep", "drop"]
        FilterMatches = ["all (AND)", "any (OR)"]

        % How many of a condition's values are spelled out where it is
        % listed. A field narrowed to twenty subjects is a line no panel has
        % room for, so the first few are named and the rest counted, the way
        % a comparison's formulas are.
        MaxFilterTerms = 4

        % How many of a comparison's formulas the axis is willing to
        % carry. Several values against one reference, or every pair of
        % them, is more arithmetic than a label has room for, so the
        % first few are written out and the rest counted.
        MaxFormulaTerms = 3

        % What a plot is made of. The first two draw the profiles
        % themselves; the last two draw one point per section instead --
        % the peak summary in peak depth against peak height, taken from
        % A.peaks as ecm_prepare_analysis_data measured it, and the
        % metric summary in whichever single number of the drawn curve
        % the Metric control names, read down the groups.
        ShowModes = ["sections", "group mean", "peak summary", "metric summary"]

        % The single numbers a profile can be summarized by, in the order
        % they are listed: how much signal there is, where it is, how
        % wide and how lopsided the shape holding it is, and how much it
        % varies. All are read off the curve on screen rather than from
        % the analysis, so the depth window, the signal, the
        % normalization, and a comparison all reach them -- which is what
        % makes the summary a summary of the plot beside it.
        SummaryMetrics = ["mean", "median", "integral", ...
            "peak height", "peak depth", ...
            "peak1 - peak2 (height)", "peak1 to peak2 (depth)", ...
            "FWHM", "centroid depth", "range (max - min)", ...
            "variance", "std. dev.", "coeff. of variation", "slope"]

        % How far to either side of a group's position on the axis a
        % metric summary reaches: the half-width the mean is ruled
        % across, and the fraction of it the sections are spread over.
        % Wide enough that a dozen sections do not sit on top of one
        % another, narrow enough that two groups do not run together,
        % and the points kept inside the rule so that the rule reads as
        % spanning the group rather than as one more point in it.
        MetricSpread = 0.3
        MetricJitter = 0.75

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

        % How one level of a field is measured against another. All but the
        % first take two profiles and return one, and each has a value that
        % means no difference -- zero for all of them but the ratio, which
        % has one -- which is what the peak of a comparison is measured from.
        CompareOps = ["none", "difference", "ratio", "log2 ratio", ...
            "% change", "normalized difference"]

        % Two references that are not a value of the compared field. Some
        % fields have one value everything else is measured against -- an
        % untreated hemisphere, a vehicle -- and some, subject among them,
        % have no such value and are asked about within themselves instead:
        % each value against everything else in its match, or each value
        % against each of the others in turn.
        RestOfMatch = "(each vs. the rest)"
        EachPair = "(every pair)"
        Rest = "rest"

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

        % How tightly the tiles are packed and how much room is left around
        % the grid as a whole, in TILEDLAYOUT's own words for it. The first of
        % each is what the browser has always drawn at.
        TileSpacings = ["compact", "tight", "none", "loose"]
        LayoutPaddings = ["compact", "tight", "loose"]

        % Which tiles carry the numbers on their axes. A grid of linked axes
        % repeats one set of numbers in every tile, which is a lot of ink for
        % one scale, so they can be left to the tiles at the edges of the grid
        % or to the one in its bottom left corner. Reading a tile in the middle
        % off the edges is only sound while the axes are linked, which is what
        % the Link axes box is for.
        TickLabelModes = ["every axis", "left and bottom axes", "bottom left axis only"]

        % How the panel's collapsible sections are measured out: the height
        % of one labeled control, of a section's header, the air around and
        % between the controls inside one, and the two markers a header
        % carries to say which way it is. The markers are written as code
        % points rather than as themselves so that the file stays plain
        % ASCII, as the rest of them are.
        SectionRowHeight = 24
        SectionHeaderHeight = 26
        SectionPad = 8
        SectionSpacing = 6
        SectionOpenMark = char(9662)
        SectionShutMark = char(9656)

        % How much a closed section is allowed to say about what it holds.
        % The header it shares the row with is the thing being read, so a
        % summary longer than this is cut short rather than crowding it out.
        MaxSummaryChars = 26

        % A tint for each section's header, in the order they are stacked.
        % Seven headers in a column all painted the same are seven things to
        % read; a hue apiece makes one of them a place on the panel, so that
        % Filter is found by the pink bar rather than by reading down from
        % the top. They are kept pale enough to leave the name on them the
        % thing that carries -- a header is a label to be read, not a signal
        % in its own right -- and dark text is asked for by name so that a
        % window in a dark theme does not put light text on them.
        SectionColors = [ ...
            0.85 0.91 0.97; ... % Signal & scale, blue
            0.91 0.87 0.96; ... % Compare, violet
            0.87 0.94 0.87; ... % Plot, green
            0.98 0.93 0.80; ... % Split, amber
            0.98 0.88 0.88; ... % Filter, rose
            0.85 0.94 0.95; ... % Layout, cyan
            0.91 0.90 0.88]     % Configurations, warm gray

        SectionFontColor = [0.15 0.15 0.15]

        % What marks an artist as belonging to a group, what marks a menu as
        % ours to clear on the next draw, and the line styles on offer.
        % What MATLAB paints an axis label in when it is left to itself. Said
        % here because the blank axes an empty cell is given have no axis color
        % to take it from, and a name in a color of its own on one row of the
        % grid would read as though it meant something.
        LabelColor = [0.15 0.15 0.15]

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

        % Redraw the panel from the current control state.
        refresh(obj)

        function setNotRefreshing(obj)
            %SETNOTREFRESHING Clear the reentrancy guard REFRESH sets.
            % A separate method so ONCLEANUP still clears it if DRAW errors.

            obj.IsRefreshing = false;

        end

        % Narrow FIELD to VALUES, beside whatever else is already narrowed.
        setFilter(obj, field, values, options)

        % Give every combination of FIELDS its own axes.
        setTiling(obj, fields)

        % Rescale each section, and say where from.
        setNormalization(obj, mode, window, options)

        % Measure one value of a field against another.
        setComparison(obj, op, field, options)

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

        % Put the plot on the clipboard, without the panel beside it.
        copyPlot(obj, options)

        % Write the plot to a file, without the panel beside it.
        file = savePlot(obj, filename)

        % The numbers behind the plot, as one struct.
        v = viewData(obj)

        % This view, as the commands that would put a browser back in it.
        code = viewCommands(obj, options)

        % Write the numbers behind the plot to a delimited file.
        file = saveData(obj, filename, options)

        % Draw one group in a color and line style of your own.
        setGroupStyle(obj, field, level, opts)

        % Put groups back to the colors the palette gave them.
        resetGroupStyles(obj, field, level)

    end

    methods (Access = private)

        % Take a string view of every field worth selecting on.
        indexFields(obj)

        % List one field's values in the order they should be drawn.
        levels = levelsOf(obj, field, txt)

        % Lay out the controls beside the plot.
        buildUI(obj)

        % The handful of things done over and over, one click away.
        buildToolbar(obj, parent)

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

        function body = addSection(obj, row, key, titleText, rowHeights, open)
            %ADDSECTION Put one collapsible group of controls on the panel.
            % ROW is the row of SECTIONGRID the group takes, KEY the name
            % SECTIONSUMMARY knows it by, and ROWHEIGHTS one height per
            % labeled row of controls inside it. What comes back is the grid
            % those controls are built into, which is what BUILDUI wants.

            arguments
                obj
                row (1,1) double
                key (1,1) string
                titleText (1,1) string
                rowHeights cell
                open (1,1) logical = true
            end

            panel = uipanel(obj.SectionGrid, BorderType = "line");
            panel.Layout.Row = row;
            panel.Layout.Column = 1;

            frame = uigridlayout(panel, [2 1]);
            frame.ColumnWidth = {'1x'};
            frame.RowHeight = {obj.SectionHeaderHeight, '1x'};
            frame.RowSpacing = 0;
            frame.Padding = [0 0 0 0];

            % The header is a button across the width of the section rather
            % than a title with a chevron beside it: the whole bar is what
            % anyone aims at, and a button is the one thing on the panel
            % that already looks like something to press. The grid behind it
            % is painted the same tint, so the strip the summary sits in
            % carries on the bar rather than cutting it short.
            tint = obj.SectionColors(min(row, size(obj.SectionColors, 1)), :);

            head = uigridlayout(frame, [1 2]);
            head.ColumnWidth = {'1x', 'fit'};
            head.RowHeight = {'1x'};
            head.ColumnSpacing = 4;
            head.Padding = [0 0 8 0];
            head.BackgroundColor = tint;

            header = uibutton(head, ...
                FontWeight = "bold", ...
                HorizontalAlignment = "left", ...
                BackgroundColor = tint, ...
                FontColor = obj.SectionFontColor, ...
                Tooltip = "Show or hide these controls.", ...
                ButtonPushedFcn = @(~,~) obj.toggleSection(key));

            summary = uilabel(head, Text = "", FontAngle = "italic", ...
                FontColor = obj.SectionFontColor, ...
                HorizontalAlignment = "right");

            body = uigridlayout(frame, [numel(rowHeights) 2]);
            body.ColumnWidth = {90, '1x'};
            body.RowHeight = rowHeights;
            body.RowSpacing = obj.SectionSpacing;
            body.Padding = repmat(obj.SectionPad, 1, 4);

            obj.Sections(end+1) = struct( ...
                Key = key, ...
                Title = titleText, ...
                Row = row, ...
                Header = header, ...
                Summary = summary, ...
                Body = body, ...
                Height = sum([rowHeights{:}]) + ...
                    obj.SectionSpacing * (numel(rowHeights) - 1) + ...
                    2 * obj.SectionPad, ...
                Open = open);

            obj.applySectionState(numel(obj.Sections));

        end

        function toggleSection(obj, key)
            %TOGGLESECTION Open the section named, or close it if it is open.

            at = find(string({obj.Sections.Key}) == key, 1);

            if isempty(at)
                return
            end

            obj.Sections(at).Open = ~obj.Sections(at).Open;
            obj.applySectionState(at);
            obj.refreshSectionSummaries();

        end

        function applySectionState(obj, at)
            %APPLYSECTIONSTATE Show or hide one section's controls.
            % The row it occupies is shrunk to its header rather than the
            % section being hidden, so the ones under it move up to meet it.

            section = obj.Sections(at);

            if section.Open
                mark = obj.SectionOpenMark;
                height = obj.SectionHeaderHeight + section.Height;
            else
                mark = obj.SectionShutMark;
                height = obj.SectionHeaderHeight;
            end

            section.Header.Text = mark + "  " + section.Title;
            section.Body.Visible = matlab.lang.OnOffSwitchState(section.Open);
            obj.SectionGrid.RowHeight{section.Row} = height;

        end

        function refreshSectionSummaries(obj)
            %REFRESHSECTIONSUMMARIES Say what each closed section is holding.
            % An open section says it in the controls themselves, and is
            % left to, rather than being told twice on one row.

            for k = 1:numel(obj.Sections)

                if obj.Sections(k).Open
                    obj.Sections(k).Summary.Text = "";
                    continue
                end

                text = obj.sectionSummary(obj.Sections(k).Key);

                if strlength(text) > obj.MaxSummaryChars
                    text = extractBefore(text, obj.MaxSummaryChars) + "...";
                end

                obj.Sections(k).Summary.Text = text;

            end

        end

        function text = sectionSummary(obj, key)
            %SECTIONSUMMARY What one section is holding, in a few words.
            % Said only of what a closed section could be doing to the plot
            % without showing it: a rescaling, a comparison, a filter. A
            % section holding nothing but defaults says nothing at all.

            parts = strings(0, 1);

            switch key

                case "scale"

                    if string(obj.SignalDropDown.Value) ~= "smoothed"
                        parts(end+1) = string(obj.SignalDropDown.Value);
                    end

                    if string(obj.NormalizeDropDown.Value) ~= "none"
                        parts(end+1) = string(obj.NormalizeDropDown.Value);
                    end

                case "compare"

                    if string(obj.CompareDropDown.Value) ~= "none"
                        parts(end+1) = string(obj.CompareDropDown.Value) + ...
                            " by " + string(obj.CompareFieldDropDown.Value);
                    else
                        parts(end+1) = "off";
                    end

                case "plot"
                    parts(end+1) = string(obj.ShowDropDown.Value);

                    % Which summary, said beside it: a closed panel that
                    % only says "metric summary" leaves the one thing the
                    % points on screen actually are unsaid.
                    if string(obj.ShowDropDown.Value) == "metric summary"
                        parts(end) = parts(end) + ": " + ...
                            string(obj.MetricDropDown.Value);
                    end

                case "split"

                    if string(obj.GroupDropDown.Value) ~= obj.NoField
                        parts(end+1) = "color " + string(obj.GroupDropDown.Value);
                    end

                    tiled = string(obj.TileListBox.Value);
                    tiled = tiled(tiled ~= obj.NoField);

                    if ~isempty(tiled)
                        parts(end+1) = "tile " + join(tiled, "+");
                    end

                case "filter"

                    if isempty(obj.Filters)
                        parts(end+1) = "all sections";
                    else
                        parts(end+1) = numel(obj.Filters) + " condition(s)";
                    end

                case "layout"
                    parts(end+1) = "legend " + string(obj.LegendDropDown.Value);

                % Configurations says nothing. The name showing in its list
                % is the one that would be loaded or deleted next, not one
                % the panel is standing on -- a config is applied and then
                % edited out from under its name -- and reporting it on a
                % shut header would claim otherwise.

            end

            if isempty(parts)
                text = "";
                return
            end

            text = join(parts, ", ");

        end

        function buildStatusBar(obj, parent)
            %BUILDSTATUSBAR One line under both halves, saying what is on screen.
            % Under the plot as well as the panel, and out of the scroll
            % region the controls live in, because a count of what is drawn
            % and a note of what was dropped are about the picture and are
            % worth nothing where they cannot be seen.

            bar = uipanel(parent, BorderType = "line");
            bar.Layout.Row = 2;
            bar.Layout.Column = [1 2];

            frame = uigridlayout(bar, [1 1]);
            frame.Padding = [8 2 8 2];

            obj.StatusLabel = uilabel(frame, Text = "", WordWrap = "on", ...
                VerticalAlignment = "center");

        end

        function applyDefaults(obj)
            %APPLYDEFAULTS Open on the split this dataset is most likely wanted in.

            obj.GroupDropDown.Value = obj.preferredField(["Treatment", "Hemisphere", "SubjectID"]);
            obj.TileListBox.Value = cellstr(obj.preferredField(["AtlasPlate", "ROILabel", "SubjectID"]));

            % Nothing is compared until it is asked for, but what a comparison
            % would be paired within is settled now, so that turning one on is
            % one click rather than a click and a guess at what has to match.
            paired = ["SubjectID", "AtlasPlate"];
            paired = paired(ismember(paired, obj.FilterFields));

            if isempty(paired)
                paired = obj.NoField;
            end

            obj.PairListBox.Value = cellstr(paired);
            obj.onCompareFieldChanged(false);

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

        % Offer the new field's values as references.
        onCompareFieldChanged(obj, redraw)

        function onFilterFieldChanged(obj, redraw)
            %ONFILTERFIELDCHANGED Put the editor onto the field just picked.
            % A field already narrowed comes back the way it was left, so
            % returning to one widens the condition standing rather than
            % starting a second beside it; a field never narrowed opens with
            % every value kept, which constrains nothing. Either way this
            % moves the editor rather than the filter, so nothing about what
            % is drawn has changed by the end of it.

            arguments
                obj
                redraw (1,1) logical = true
            end

            field = string(obj.FilterFieldDropDown.Value);

            if field == obj.AllSections
                obj.FilterValuesListBox.Items = {};
                obj.FilterValuesListBox.Enable = "off";
                obj.FilterSenseDropDown.Enable = "off";
            else
                levels = obj.levelsOf(field);
                obj.FilterValuesListBox.Items = cellstr(levels);
                obj.FilterValuesListBox.Enable = "on";
                obj.FilterSenseDropDown.Enable = "on";

                at = obj.filterAt(field);

                if isempty(at)
                    obj.FilterValuesListBox.Value = cellstr(levels);
                    obj.FilterSenseDropDown.Value = obj.FilterSenses(1);
                else
                    obj.FilterValuesListBox.Value = cellstr(obj.Filters(at).Values);
                    obj.FilterSenseDropDown.Value = obj.senseName(obj.Filters(at).Keep);
                end
            end

            if redraw
                obj.refresh();
            end

        end

        function onFilterValuesChanged(obj)
            %ONFILTERVALUESCHANGED Record what the editor now says about its field.
            % The one place a condition is written down from the panel: both
            % the values list and the keep/drop choice land here, either of
            % them being half of the same answer.

            field = string(obj.FilterFieldDropDown.Value);

            if field == obj.AllSections
                return
            end

            values = string(obj.FilterValuesListBox.Value);
            keep = string(obj.FilterSenseDropDown.Value) == obj.FilterSenses(1);

            % Keeping every value, or dropping none, narrows nothing, and is
            % taken off the list rather than left on it saying so at length.
            % Keeping none is a condition all the same: it draws an empty
            % plot, and the status line says how few sections that is.
            if (keep && numel(values) == numel(obj.levelsOf(field))) || ...
                    (~keep && isempty(values))
                obj.dropFilter(field);
            else
                obj.recordFilter(field, values, keep);
            end

            obj.refreshFilterList();
            obj.refresh();

        end

        function onFilterSelected(obj)
            %ONFILTERSELECTED Put the editor back on the condition just picked.

            field = string(obj.FilterListBox.Value);

            if isempty(field) || ~ismember(field, string(obj.FilterFieldDropDown.Items))
                return
            end

            obj.FilterFieldDropDown.Value = field;
            obj.onFilterFieldChanged(false);

        end

        function onRemoveFilter(obj)
            %ONREMOVEFILTER Take the condition now picked off the list.

            field = string(obj.FilterListBox.Value);

            if isempty(field)
                return
            end

            obj.dropFilter(field);
            obj.refreshFilterList();

            % The editor is showing the condition that has just gone, so it
            % is put back to every value kept rather than left displaying a
            % narrowing that is no longer in force.
            if string(obj.FilterFieldDropDown.Value) == field
                obj.onFilterFieldChanged(false);
            end

            obj.refresh();

        end

        function onClearFilters(obj)
            %ONCLEARFILTERS Drop every condition and draw the whole dataset.

            obj.Filters(:) = [];
            obj.refreshFilterList();
            obj.onFilterFieldChanged(false);
            obj.refresh();

        end

        function at = filterAt(obj, field)
            %FILTERAT Where FIELD's condition sits in the list, if it has one.

            at = [];

            if isempty(obj.Filters)
                return
            end

            at = find([obj.Filters.Field] == field, 1);

        end

        function recordFilter(obj, field, values, keep)
            %RECORDFILTER Set FIELD's condition, replacing any it already had.
            % A field is narrowed once: asking a second question of it is
            % changing the answer to the first, not adding to it.

            condition = struct( ...
                Field = string(field), ...
                Values = reshape(string(values), 1, []), ...
                Keep = logical(keep));

            at = obj.filterAt(field);

            if isempty(at)
                obj.Filters(end+1) = condition;
            else
                obj.Filters(at) = condition;
            end

        end

        function dropFilter(obj, field)
            %DROPFILTER Leave FIELD unconstrained.

            at = obj.filterAt(field);

            if ~isempty(at)
                obj.Filters(at) = [];
            end

        end

        function name = senseName(obj, keep)
            %SENSENAME What a condition's direction is called on the panel.

            if keep
                name = obj.FilterSenses(1);
            else
                name = obj.FilterSenses(2);
            end

        end

        function text = describeFilter(obj, condition)
            %DESCRIBEFILTER One condition, as the line that stands for it.
            % Written in the operator rather than in keep and drop, which is
            % shorter and is what a list of them has to be read down.

            values = reshape(condition.Values, 1, []);

            if numel(values) > obj.MaxFilterTerms
                values = [values(1:obj.MaxFilterTerms), ...
                    sprintf("+%d more", numel(values) - obj.MaxFilterTerms)];
            end

            if condition.Keep
                operator = " = ";
            else
                operator = " ~= ";
            end

            text = condition.Field + operator + strjoin(values, ", ");

        end

        function refreshFilterList(obj)
            %REFRESHFILTERLIST Show the conditions now standing.

            obj.FilterListBox.Items = {};
            obj.FilterListBox.ItemsData = {};

            if isempty(obj.Filters)
                obj.FilterListBox.Enable = "off";
                obj.FilterMatchDropDown.Enable = "off";
                return
            end

            labels = arrayfun(@(f) obj.describeFilter(f), obj.Filters);

            obj.FilterListBox.Items = cellstr(reshape(labels, 1, []));
            obj.FilterListBox.ItemsData = cellstr(reshape([obj.Filters.Field], 1, []));
            obj.FilterListBox.Enable = "on";

            % One condition means the same thing under either rule, so the
            % choice between them is offered once there are two to combine.
            obj.FilterMatchDropDown.Enable = ...
                matlab.lang.OnOffSwitchState(numel(obj.Filters) > 1);

        end

        function keep = filterMask(obj)
            %FILTERMASK Which sections the conditions standing let through.
            % Within a condition the values are an OR -- a section holding
            % any of them satisfies it -- and across conditions the Combine
            % rule says whether all of them have to be satisfied or one.

            keep = true(height(obj.Files), 1);

            if isempty(obj.Filters)
                return
            end

            satisfied = false(height(obj.Files), numel(obj.Filters));

            for k = 1:numel(obj.Filters)
                condition = obj.Filters(k);
                hit = ismember(obj.Text.(condition.Field), condition.Values);

                if ~condition.Keep
                    hit = ~hit;
                end

                satisfied(:, k) = hit;
            end

            if string(obj.FilterMatchDropDown.Value) == obj.FilterMatches(2)
                keep = any(satisfied, 2);
            else
                keep = all(satisfied, 2);
            end

        end

        function list = knownFilters(obj, saved)
            %KNOWNFILTERS The conditions of SAVED this dataset can still take.
            % A configuration carries the fields and values of whatever was
            % open when it was saved. One naming a field this dataset has
            % not got, or values it does not hold, is dropped rather than
            % raised as an error -- the same reading APPLYSETTINGS gives a
            % color-by or tile-by field that has gone.

            list = struct("Field", {}, "Values", {}, "Keep", {});

            if isempty(saved) || ~isstruct(saved)
                return
            end

            wanted = ["Field", "Values", "Keep"];

            for k = 1:numel(saved)
                condition = saved(k);

                if ~all(isfield(condition, wanted)) || ...
                        ~ismember(string(condition.Field), obj.FilterFields)
                    continue
                end

                values = reshape(string(condition.Values), 1, []);
                values = values(ismember(values, obj.levelsOf(condition.Field)));

                if isempty(values)
                    continue
                end

                list(end+1) = struct(Field = string(condition.Field), ...
                    Values = values, Keep = logical(condition.Keep)); %#ok<AGROW>
            end

        end

        function onReset(obj)
            %ONRESET Put the depth window, the scale, the comparison, and the
            %filter back.
            % What is left alone is the split -- what the plot is colored and
            % tiled by -- because that is the figure being worked towards
            % rather than a step on the way to it.

            depth = obj.Data.grid.depth;
            obj.DepthMinField.Value = floor(min(depth));
            obj.DepthMaxField.Value = ceil(max(depth));
            obj.NormalizeDropDown.Value = "none";
            obj.ScopeDropDown.Value = "per section";
            obj.RefMinField.Value = floor(min(depth));
            obj.RefMaxField.Value = ceil(max(depth));
            obj.CompareDropDown.Value = "none";
            obj.FilterFieldDropDown.Value = obj.AllSections;
            obj.FilterMatchDropDown.Value = obj.FilterMatches(1);
            obj.Filters(:) = [];
            obj.refreshFilterList();
            obj.onFilterFieldChanged();

        end

        % Every control on the panel, as one struct.
        s = captureSettings(obj)

        % Put every control on the panel into the state S describes.
        applySettings(obj, s)

        function value = oneOf(~, saved, allowed)
            %ONEOF The saved choice, or the first offered when it is not one of them.
            % A configuration written by a version that offered a choice this
            % one has since dropped names something not on the list, which is
            % read as the default rather than raised as an error.

            value = string(saved);

            if ~isscalar(value) || ~ismember(value, allowed)
                value = allowed(1);
            end

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

        % A name built from the choices that set the view apart.
        label = describeSettings(obj, s)

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

        % Build one tiled layout of the sections now in view.
        draw(obj, parent)

        % Draw one group's sections into one tile.
        h = drawGroup(obj, ax, x, Y, idx, cols, groupField, groupName, color, slot)

        % One legend for the whole layout, outside every axes.
        lgd = layoutLegend(obj, ax, groupField, groups, colors, groupOf, placement)

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

        function [m, lo, hi] = metricBand(obj, v)
            %METRICBAND One group's summary values, as a mean and an interval.
            % Taken through BANDOF, which is what the band around a group
            % mean is taken through. A row of one value per section is the
            % same shape as one depth of the profile grid, so the Error band
            % control means at a point exactly what it means along a curve,
            % and a bar and a band read off the same arithmetic.

            M = reshape(v, 1, []);
            n = sum(isfinite(M), 2);
            m = mean(M, 2, "omitnan");

            if n < 2
                [lo, hi] = deal(NaN);
                return
            end

            [lo, hi] = obj.bandOf(M, n, m);

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

        % A bootstrap interval for one group's mean at each depth.
        [lo, hi] = bootBand(obj, M)

        % The sections and depths the controls have selected.
        [idx, Y, x] = currentView(obj)

        function tf = comparing(obj)
            %COMPARING Whether the controls describe a comparison to take.
            % An operation without a field to take it across is nothing to
            % take, so both have to be set before anything is compared.

            tf = string(obj.CompareDropDown.Value) ~= "none" && ...
                string(obj.CompareFieldDropDown.Value) ~= obj.NoField;

        end

        function fields = pairFields(obj)
            %PAIRFIELDS The fields two sections have to agree on to be compared.
            % The compared field is dropped from them however it was selected:
            % matching on it would put the two sides of every comparison in
            % different matches and leave nothing to compare.

            selected = string(obj.PairListBox.Value);
            fields = obj.FilterFields(ismember(obj.FilterFields, selected));
            fields = reshape(fields(fields ~= string(obj.CompareFieldDropDown.Value)), 1, []);

        end

        % The columns to draw, and what each of them holds.
        [idx, Y] = rosterOf(obj, depth, Y, rows)

        % Measure one value of a field against another, in matches.
        [idx, D] = compareWithin(obj, depth, Y, rows)

        % What is measured against what inside one match.
        pairs = pairsInMatch(obj, rows, level, inMatch, levels, reference)

        function key = matchKeys(obj, rows, fields)
            %MATCHKEYS One string per section saying which match it falls in.
            % The values are joined on a character no field can hold rather
            % than on a printable one, so two sections match when every field
            % matches and not because one value ended where the next began.

            if isempty(fields)
                key = repmat("", numel(rows), 1);
                return
            end

            parts = strings(numel(rows), numel(fields));

            for iField = 1:numel(fields)
                parts(:, iField) = obj.Text.(fields(iField))(rows);
            end

            key = join(parts, char(31), 2);

        end

        % Where each comparison departs furthest from no difference.
        [peakX, peakY] = comparisonPeaks(obj, depth, D, op)

        function inRange = peakWindow(obj, depth)
            %PEAKWINDOW The depths A.peaks was searched over.
            % An analysis that did not record one, or one whose window this
            % grid never reached, is searched over the whole depth axis rather
            % than not at all.

            inRange = true(size(depth));

            if ~isfield(obj.Data, "options") || ~isfield(obj.Data.options, "peakRange")
                return
            end

            range = obj.Data.options.peakRange;

            if numel(range) ~= 2 || ~all(isfinite(range))
                return
            end

            window = depth >= range(1) & depth <= range(2);

            if any(window)
                inRange = window;
            end

        end

        function T = comparisonTable(~, txt, labels, sides, peakX, peakY, op)
            %COMPARISONTABLE The section table's counterpart, one row per comparison.
            % A comparison stands for several sections at once, so a numeric
            % column of the section table has no single value to carry and the
            % fields come across as the text every split already reads them as.
            % What is added is the account of the comparison itself: which
            % operation, written out with the two values in it, how many
            % sections went into each side, and the peak of the result.

            fields = string(fieldnames(txt));
            T = table();

            for iField = 1:numel(fields)
                T.(fields(iField)) = txt.(fields(iField));
            end

            nPairs = numel(labels);

            T.Operation = repmat(op, nPairs, 1);
            T.Comparison = reshape(labels, [], 1);
            T.NCompared = sides(:, 1);
            T.NReference = sides(:, 2);
            T.PeakX = peakX;
            T.PeakY = peakY;

        end

        function names = comparisonNames(~, txt, within, slugs)
            %COMPARISONNAMES What each comparison is called where a column needs a name.
            % The match it was taken in and the comparison it is, which
            % together are what tells one column of an export from the next.
            % Spelled out in words rather than in the arithmetic the plot is
            % labeled with: a column header has to survive MAKEVALIDNAME, and
            % that would take a difference and a ratio down to the same name.

            nPairs = numel(slugs);

            if nPairs == 0
                names = strings(0, 1);
                return
            end

            parts = strings(nPairs, numel(within) + 1);

            for iField = 1:numel(within)
                parts(:, iField) = txt.(within(iField));
            end

            parts(:, end) = reshape(slugs, [], 1);

            names = string(matlab.lang.makeUniqueStrings( ...
                matlab.lang.makeValidName(join(parts, "_", 2))));

        end

        % The rescaling the normalization controls describe.
        n = normalizationOf(obj, depth, reference, inView)

        % Label each section with the sections it shares a scale with.
        poolId = poolOf(obj, inView)

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

        % The axes the Tile by selection asks for, and the one each section
        % belongs in.
        [tiles, tileOf, nCols] = tiling(obj, fields, idx)

        function [levels, levelOf] = splitBy(obj, field, idx)
            %SPLITBY Label each column in view with the value it is split on.

            if field == obj.NoField
                levels = "all";
                levelOf = repmat("all", numel(idx), 1);
                return
            end

            levelOf = obj.View.Text.(field)(idx);
            levels = obj.viewLevelsOf(field);
            levels = levels(ismember(levels, levelOf));

        end

        function levels = viewLevelsOf(obj, field)
            %VIEWLEVELSOF One field's values, as the columns being drawn hold them.
            % The same order LEVELSOF puts a field's values in, taken over the
            % roster rather than over the section table: without a comparison
            % the two are the same list, and with one the compared field holds
            % the comparisons instead of the values they were taken between.

            levels = obj.levelsOf(field, obj.View.Text.(field));

        end

        % Thin the tick labels over the grid and name its edges.
        [yLabels, xLabels] = dressGrid(obj, t, tiles, tileAx, nCols, mode, edgeLabels)

        function hideTickLabels(~, axesHandles, which)
            %HIDETICKLABELS Take the numbers off an axis, leaving its ticks.
            % An empty list of labels stays empty however the limits move
            % afterwards, so a zoom or a pan does not bring the numbers back --
            % which is what setting the labels to the ones drawn at the time
            % would do the other way round, and leave them wrong.

            for ax = reshape(axesHandles, 1, [])

                if contains(which, "x")
                    ax.XTickLabel = [];
                end

                if contains(which, "y")
                    ax.YTickLabel = [];
                end

            end

        end

        % Hang the row and column values off the grid's edges.
        [yLabels, xLabels] = labelGridEdges(obj, t, tiles, tileAx, nCols)

        % Put every label at the offset of the one furthest out.
        alignLabels(obj, labels, dim)

        function ax = edgeAxes(~, t, tiles, tileAx, iRow, iCol, nCols)
            %EDGEAXES The axes at one cell of the grid, made blank if it is empty.
            % A combination the dataset never held leaves a hole, and a hole
            % carries no name, so the cell is given an axes holding nothing but
            % the name -- no box, no numbers, no color -- rather than letting
            % the row's name slide inward to the first tile that was drawn.

            index = (iRow - 1) * nCols + iCol;
            at = find([tiles.Index] == index, 1);

            if ~isempty(at)
                ax = tileAx(at);
                return
            end

            ax = nexttile(t, index);
            set(ax, 'Color', 'none', 'XColor', 'none', 'YColor', 'none', ...
                'XTick', [], 'YTick', [], 'PickableParts', 'none')
            box(ax, "off")

        end

        % Name the axes once for the whole layout.
        labelLayout(obj, t, groupField, tileFields, nTiles, edgeLabels)

        function source = peakSource(obj)
            %PEAKSOURCE The trace A.peaks was measured from.

            source = "";

            if isfield(obj.Data, "options") && isfield(obj.Data.options, "peakSource")
                source = string(obj.Data.options.peakSource);
            end

        end

        % Name the scale the intensities are drawn on.
        text = withNormalization(obj, label)

        % Name what one point of a metric summary measures.
        label = metricLabel(obj, metric)

        function text = withComparison(obj, label)
            %WITHCOMPARISON Say what the curves are a comparison of.
            % Which operation across which field. Which value was measured
            % against which is COMPARISONFORMULA's half of the answer, said
            % once on a line of its own rather than once per group here.

            if obj.View.Comparison == ""
                text = label;
                return
            end

            text = label + ", " + obj.View.Comparison;

        end

        function text = comparisonFormula(obj)
            %COMPARISONFORMULA The arithmetic the curves are, in the values it
            %was taken between.
            % "GM6001 - Vehicle" where WITHCOMPARISON says "difference by
            % Treatment": the operation and the field it was taken across say
            % what was done, and this says what it was done to, and in which
            % direction. The compared field holds it once per column, so a plot
            % colored by that field already lists it in the legend -- but only
            % that plot does, and the same curves colored by subject would
            % otherwise leave which side was subtracted from which nowhere on
            % the figure.

            text = "";

            if obj.View.Comparison == ""
                return
            end

            field = string(obj.CompareFieldDropDown.Value);

            if ~isfield(obj.View.Text, field)
                return
            end

            formulas = reshape(obj.viewLevelsOf(field), 1, []);

            if isempty(formulas)
                return
            end

            % A field of many values yields a formula per value, and every
            % pair yields one per pair; past a few they are counted rather
            % than spelled out, an axis being no place for a list of twenty.
            if numel(formulas) > obj.MaxFormulaTerms
                formulas = [formulas(1:obj.MaxFormulaTerms), ...
                    sprintf("+%d more", numel(formulas) - obj.MaxFormulaTerms)];
            end

            text = strjoin(formulas, ",  ");

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

        function note = countNote(obj, nDrawn)
            %COUNTNOTE Say how much of the dataset is on screen.
            % Sections out of all of them, or -- once they have been paired
            % off against each other -- comparisons out of the sections they
            % were taken from, which is the count that says whether the
            % pairing found what it was looking for.

            if obj.View.Comparison == ""
                note = sprintf("%d of %d sections", nDrawn, height(obj.Files));
            else
                note = sprintf("%d comparison(s) from %d section(s)", ...
                    nDrawn, obj.View.Sources);
            end

        end

        function note = compareNote(obj)
            %COMPARENOTE Say what the pairing did not manage to compare.
            % A section with no counterpart to be measured against is left out
            % of the plot silently otherwise, and a pairing that quietly
            % dropped half the dataset is exactly what a reader of the plot
            % needs to be told.

            note = "";

            if obj.View.Comparison == ""
                return
            end

            if obj.View.Unpaired > 0
                note = note + sprintf(" | %d section(s) with no match", obj.View.Unpaired);
            end

            if obj.View.Undefined > 0
                note = note + sprintf(" | %d comparison(s) undefined throughout", ...
                    obj.View.Undefined);
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
            % The bar runs the width of the window and wraps, but a status
            % line naming several notes at once can still outrun it, so the
            % whole of it is put on the tooltip as well.

            obj.StatusLabel.Text = text;
            obj.StatusLabel.Tooltip = text;

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

        % One artist, in whatever its group is drawn in now.
        repaint(obj, h)

        function [axesMenu, groupMenus] = buildStyleMenus(obj, fig, groupField, groups)
            %BUILDSTYLEMENUS One menu per group, and one for the axes behind them.

            axesMenu = obj.buildStyleMenu(fig, groupField, groups, "");
            groupMenus = containers.Map('KeyType', 'char', 'ValueType', 'any');

            for k = 1:numel(groups)
                groupMenus(char(groups(k))) = ...
                    obj.buildStyleMenu(fig, groupField, groups, groups(k));
            end

        end

        % The menu behind one right-click.
        cm = buildStyleMenu(obj, fig, groupField, groups, clicked)

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
            uimenu(copyTo, Text = "The commands that rebuild this view to the clipboard", ...
                MenuSelectedFcn = @(~,~) obj.onCopyCommands());

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

        % Put the plot on the clipboard as a PNG.
        note = copyImage(obj, f)

        % What goes behind the plot in a file of this kind.
        [color, note] = backgroundArg(obj, ext)

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

        % The current view as one table, in the layout asked for.
        T = viewTable(obj, layout)

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

        % Put a written account of the view on the clipboard.
        copySummary(obj)

        function onCopyCommands(obj)
            %ONCOPYCOMMANDS Put the commands for this view on the clipboard.

            code = obj.viewCommands();

            try
                clipboard("copy", strjoin(code, newline))
            catch ME
                uialert(obj.Fig, ME.message, "Could not copy the commands");
                return
            end

            obj.setStatus(sprintf( ...
                "%d line(s) of commands for this view copied to the clipboard.", ...
                numel(code)));

        end

        function name = browserVariable(obj)
            %BROWSERVARIABLE What this browser is called in the base workspace.
            % A browser does not know what it was assigned to, and a command
            % naming the wrong variable is worse than one naming a plausible
            % variable, so the workspace is asked and B used where it has no
            % answer -- which is what the help text calls the browser
            % throughout, and what a browser opened for its side effect has
            % no name at all.

            name = "B";

            try
                vars = string(evalin("base", "who"));

                for k = 1:numel(vars)
                    value = evalin("base", vars(k));

                    if isa(value, "ECMBrowser") && isscalar(value) && value == obj
                        name = vars(k);
                        return
                    end
                end
            catch
                % A workspace that cannot be read is one more reason to
                % fall back on the name the help text uses.
            end

        end

        function code = layoutCommands(obj, s, v)
            %LAYOUTCOMMANDS How the grid is dressed, where it has been changed.
            % Controls that move nothing but ink, each with one value a
            % browser opens on, and each set the same way: there is no method
            % for them because there is nothing to work out, only a value to
            % put in a control.

            dressing = { ...
                "LegendDropDown", s.Legend, obj.LegendPlacements(1); ...
                "SpacingDropDown", s.TileSpacing, obj.TileSpacings(1); ...
                "PaddingDropDown", s.Padding, obj.LayoutPaddings(1); ...
                "TickLabelDropDown", s.TickLabels, obj.TickLabelModes(1)};

            code = strings(1, 0);

            for k = 1:size(dressing, 1)
                if dressing{k, 2} ~= dressing{k, 3}
                    code(end+1) = v + "." + dressing{k, 1} + ".Value = " + ...
                        obj.textLiteral(dressing{k, 2}) + ";"; %#ok<AGROW>
                end
            end

            boxes = { ...
                "LinkCheckBox", s.Link, true; ...
                "TransposeCheckBox", s.Transpose, false; ...
                "AxisQuantityCheckBox", s.AxisQuantity, false};

            for k = 1:size(boxes, 1)
                if logical(boxes{k, 2}) ~= boxes{k, 3}
                    code(end+1) = v + "." + boxes{k, 1} + ".Value = " + ...
                        string(logical(boxes{k, 2})) + ";"; %#ok<AGROW>
                end
            end

        end

        function code = styleCommands(obj, v)
            %STYLECOMMANDS The colors and line styles picked by hand.
            % Kept apart from the panel, and so from a saved configuration,
            % but part of the figure all the same: these are the only way a
            % palette settled on by right-clicking leaves the browser.

            code = strings(1, 0);
            keys = sort(string(obj.Styles.keys));

            for k = 1:numel(keys)
                chosen = obj.Styles(char(keys(k)));
                args = "";

                if ~isempty(chosen.Color)
                    args = args + ", Color = " + obj.numberLiteral(chosen.Color);
                end

                if chosen.LineStyle ~= ""
                    args = args + ", LineStyle = " + obj.textLiteral(chosen.LineStyle);
                end

                if args == ""
                    continue
                end

                code(end+1) = v + ".setGroupStyle(" + ...
                    obj.textLiteral(extractBefore(keys(k), "|")) + ", " + ...
                    obj.textLiteral(extractAfter(keys(k), "|")) + args + ");"; %#ok<AGROW>
            end

        end

        function code = nextCommands(obj, s, v)
            %NEXTCOMMANDS What is usually wanted once the view is back.
            % Commented out rather than run: the commands above are the
            % figure, and these are the handful of things done to it
            % afterwards, spelled out so that the browser's help does not
            % have to be opened to remember which is which.

            calls = [v + ".popOut()", "draws it into a figure of its own"; ...
                v + ".savePlot(""figure.pdf"")", ...
                    "PNG, TIFF, JPEG, PDF, EPS, SVG, or .fig"; ...
                v + ".saveData(""profiles.csv"", Layout = ""long"")", ...
                    "one row per sample, every field beside it"; ...
                "d = " + v + ".viewData()", "the numbers behind the plot"; ...
                v + ".copySummary()", "the account of this view a caption needs"];

            if s.Group ~= obj.NoField
                levels = obj.levelsOf(s.Group);

                calls(end+1, :) = [v + ".setGroupStyle(" + ...
                    obj.textLiteral(s.Group) + ", " + ...
                    obj.textLiteral(levels(1)) + ", Color = [0 0 0])", ...
                    "one group in a color of your own"];
            end

            code = ["", "% And what can then be done with it:", ...
                reshape("%   " + pad(calls(:, 1)) + "   " + calls(:, 2), 1, [])];

        end

        function text = textLiteral(~, values)
            %TEXTLITERAL One value, or several, as they would be typed in.

            values = string(values);
            values = """" + replace(values, """", """""") + """";

            if isscalar(values)
                text = values;
                return
            end

            text = "[" + strjoin(reshape(values, 1, []), " ") + "]";

        end

        function text = numberLiteral(~, values)
            %NUMBERLITERAL One number, or several, at a length that reads back.

            parts = arrayfun(@(x) string(sprintf("%g", x)), double(values(:)'));

            if isscalar(parts)
                text = parts;
                return
            end

            text = "[" + strjoin(parts, " ") + "]";

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
