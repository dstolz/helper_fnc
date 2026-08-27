classdef MultiChannelViewer < handle
    % MultiChannelViewer  Fast, interactive multichannel time-series viewer.
    %   Displays a [nSamples x nChannels] signal matrix as stacked traces or a
    %   heatmap, with mouse/keyboard pan, time zoom, amplitude gain, channel
    %   spacing, and channel-window scrolling (when more channels are loaded
    %   than fit on screen at once). Optional synchronized digital/event and
    %   auxiliary analog tracks can be attached above/below the main view.
    %
    %   Only the visible time window and visible channel window are ever
    %   sliced/decimated, and existing graphics objects are updated in place
    %   (XData/YData/CData) rather than recreated, so panning/zooming stays
    %   fast regardless of how many channels or samples are loaded.
    %
    %   Construction
    %   ------------
    %     v = MultiChannelViewer(X, Fs);
    %     v = MultiChannelViewer(X, Fs, VisibleChannels=16, Mode="heatmap");
    %     v = MultiChannelViewer(X, Fs, Parent=ax);   % embed in a caller's axes
    %
    %   Mouse: wheel = fine time scroll; Ctrl+wheel = jog one window; Shift+wheel
    %   = zoom time at cursor; Ctrl+Shift+wheel = amplitude gain; Alt+wheel =
    %   scroll channel window; Alt+Ctrl+wheel = page channel window; middle-drag
    %   (or Shift+Left) = pan time (+ amplitude baseline, or channel-window
    %   scroll once the channel axis is windowed).
    %
    %   Keyboard (press F1 in the figure for the full list): Left/Right = step
    %   time, Up/Down/PageUp/PageDown/Home/End = channel window navigation,
    %   =/- = amplitude gain, [/] = channel spacing, m = toggle mode, r = reset.
    %
    %   Channels are shown in raw column order by default; setChannelOrder()
    %   remaps display position -> data column (e.g. to sort by probe depth)
    %   without touching the cached data. setChannelGroups() + setColorByGroup()
    %   color traces by an arbitrary per-channel group (e.g. probe shank)
    %   instead of the default per-line color cycle.
    %
    %   See also GUI.KEYMAP, GUI.KEYBINDING.

    properties (SetAccess = private)
        NumSamples   (1,1) double = 0             % samples in the cached data
        NumChannels  (1,1) double = 0              % channels in the cached data
        ChannelNames (1,:) string = string.empty(1,0)
        Units        (1,1) string = ""             % axis/colorbar unit label
    end

    properties
        Mode (1,1) string {mustBeMember(Mode, ["traces","heatmap"])} = "traces"
        TimeWindowStart    (1,1) double = 0        % seconds
        TimeWindowDuration (1,1) double = 5        % seconds
        AmpGain      (1,1) double {mustBePositive} = 1
        TraceSpacing (1,1) double {mustBeNonnegative} = 0   % 0 = auto from Clim0
        YOffset      (1,1) double = 0
        % Not constrained to positive/integer here: scrollChannels/jumpToChannel/
        % onButtonMotion intentionally assign transient out-of-range values that
        % render() then rounds and clamps back into bounds on every redraw.
        FirstVisibleChannel (1,1) double = 1
        NumVisibleChannels  (1,1) double {mustBePositive, mustBeInteger} = 1
        PixelBudget  (1,1) double {mustBePositive} = 2500
        Colormap     (1,1) string = "parula"

        % Interactive-gesture gate: checked at the top of onScroll/onButtonDown
        % and every KeyMap-registered shortcut. Lets a host embedding this
        % viewer in a multi-tab figure restrict interaction to "my tab is
        % selected" (e.g. ActiveFcn = @() app.Tabs.SelectedTab==app.MyTab).
        % Standalone use never needs to touch this (default always-true).
        ActiveFcn (1,1) function_handle = @() true

        % Called at the end of every render(), after this class's own drawing,
        % so a host can layer its own overlays (e.g. artifact regions) without
        % subclassing.
        PostRenderFcn function_handle = function_handle.empty

        % When true and ChannelGroups has one entry per channel, traces mode
        % colors each line by its group (e.g. probe shank) instead of cycling
        % through the default per-line palette. Set via setColorByGroup();
        % has no effect in heatmap mode, which already uses color for
        % amplitude. See also ChannelGroups, setChannelGroups().
        ColorByGroup (1,1) logical = false
    end

    properties (SetAccess = private)
        Axes    = gobjects(0)   % main (scrollable) view
        Figure  = gobjects(0)
        DigitalAxes = gobjects(0)   % empty when no digital tracks are attached
        AuxAxes     = gobjects(0)   % empty when no auxiliary tracks are attached
        KeyMapObj = []
    end

    properties (Dependent)
        HasDigitalTracks
        HasAuxTracks
    end

    properties (SetAccess = private)
        % Permutation of 1:NumChannels mapping display position -> data-column
        % (raw channel) index, e.g. to display channels in probe-depth order
        % instead of their raw column order. Empty = natural order (display
        % position k == data column k). Set via setChannelOrder(); reset to
        % empty by loadData() since a new channel count invalidates it.
        ChannelOrder (1,:) double = double.empty(1,0)

        % Group id (e.g. probe shank number) per data-column (raw channel),
        % same indexing convention as ChannelOrder -- i.e. ChannelGroups(c) is
        % the group of raw channel c, independent of display order/position.
        % Empty = ungrouped. Set via setChannelGroups(); reset to empty by
        % loadData() since a new channel count invalidates it. Only consumed
        % when ColorByGroup is true.
        ChannelGroups (1,:) double = double.empty(1,0)
    end

    properties (SetAccess = private)
        % Read-only handles to the underlying graphics objects, exposed so
        % callers can inspect/customize them directly (e.g. h.Lines(3).Color)
        % and so tests can verify the in-place-graphics-reuse contract.
        Lines = gobjects(0,1)
        Image = gobjects(0)
        Colorbar = gobjects(0)
        DigitalLines = gobjects(0,1)
        AuxLines = gobjects(0,1)

        % Modifier keys currently held, per onKeyPress/onKeyRelease. Read-only
        % externally; exposed (rather than fully private) so callers/tests can
        % confirm the KeyMap modifier-tracking chain is working.
        Mods (1,:) string = string.empty(1,0)
    end

    properties (Access = private)
        Data = struct([])        % X [nSamp x nCh] single, Fs, nSamp, nCh, Clim0
        Digital = struct([])     % X [nSamp x nDig], nCh, Names
        Aux = struct([])         % X [nSamp x nAux], nCh, Names, Clim0 [1 x nAux]
        InitView = struct([])    % constructor-time view snapshot, for resetView

        DrawnMode string = ""
        DrawnChannelWindow (1,2) double = [0 0]

        Pan = struct('active', false)             % middle-drag pan bookkeeping

        OwnsFigure (1,1) logical = false           % true if this class created Figure
        Initializing (1,1) logical = false         % suppresses render() during construction
    end

    methods
        % --- methods defined in separate files in this @-folder ---
        render(obj)
        show(obj)
        setMode(obj, m)
        resetView(obj)
        panTime(obj, dtSeconds)
        zoomTime(obj, factor, anchorSeconds)
        setGain(obj, factor)
        setSpacing(obj, value)
        scrollChannels(obj, deltaChannels)
        setVisibleChannelCount(obj, n)
        jumpToChannel(obj, idx, opts)
        setChannelOrder(obj, order)
        setChannelGroups(obj, groups)
        setColorByGroup(obj, tf)
        loadData(obj, data, Fs, opts)
        setDigitalData(obj, data, names)
        setAuxData(obj, data, names)
        km = buildKeyMap(obj)
        onScroll(obj, evt)
        onButtonDown(obj)
        onButtonMotion(obj)
        onButtonUp(obj)
        onKeyPress(obj, evt)
        onKeyRelease(obj, evt)
        delete(obj)

        function obj = MultiChannelViewer(data, Fs, opts)
            arguments
                data (:,:) {mustBeNumeric}
                Fs (1,1) double {mustBePositive}
                opts.ChannelNames (1,:) string = string.empty(1,0)
                opts.Units (1,1) string = ""
                opts.Parent = []
                opts.Mode (1,1) string {mustBeMember(opts.Mode, ["traces","heatmap"])} = "traces"
                opts.WindowDuration (1,1) double {mustBePositive} = 5
                opts.VisibleChannels (1,1) double {mustBePositive, mustBeInteger} = 16
                opts.PixelBudget (1,1) double {mustBePositive} = 2500
                opts.Colormap (1,1) string = "parula"
                opts.TraceSpacing (1,1) double {mustBeNonnegative} = 0
                opts.ActiveFcn (1,1) function_handle = @() true
                opts.PostRenderFcn function_handle = function_handle.empty
                opts.AttachCallbacks (1,1) logical = true
                opts.EnableKeyMap (1,1) logical = true
                opts.DigitalData (:,:) {mustBeNumericOrLogical} = []
                opts.DigitalNames (1,:) string = string.empty(1,0)
                opts.AuxData (:,:) double = []
                opts.AuxNames (1,:) string = string.empty(1,0)
            end

            if isempty(data) || size(data, 1) < 1
                error('MultiChannelViewer:EmptyData', 'data must have at least one sample.');
            end

            obj.Initializing = true;
            obj.PixelBudget = opts.PixelBudget;
            obj.Colormap    = opts.Colormap;
            obj.ActiveFcn   = opts.ActiveFcn;
            obj.PostRenderFcn = opts.PostRenderFcn;
            obj.TraceSpacing  = opts.TraceSpacing;

            hasDigital = ~isempty(opts.DigitalData);
            hasAux     = ~isempty(opts.AuxData);
            obj.buildLayout(opts.Parent, hasDigital, hasAux);

            obj.Mode = opts.Mode;
            obj.NumVisibleChannels = max(1, round(opts.VisibleChannels));
            obj.TimeWindowDuration = opts.WindowDuration;

            obj.loadData(data, Fs, ChannelNames=opts.ChannelNames, Units=opts.Units);
            if hasDigital
                obj.setDigitalData(opts.DigitalData, opts.DigitalNames);
            end
            if hasAux
                obj.setAuxData(opts.AuxData, opts.AuxNames);
            end

            % Snapshot the settled initial view (post-clamp) for resetView().
            obj.InitView = struct( ...
                'Mode', obj.Mode, ...
                'TimeWindowStart', obj.TimeWindowStart, ...
                'TimeWindowDuration', obj.TimeWindowDuration, ...
                'AmpGain', obj.AmpGain, ...
                'YOffset', obj.YOffset, ...
                'FirstVisibleChannel', obj.FirstVisibleChannel, ...
                'NumVisibleChannels', obj.NumVisibleChannels);

            if opts.AttachCallbacks
                obj.attachCallbacks();
            end
            if opts.EnableKeyMap
                km = obj.buildKeyMap();
                km.attach();
            end

            obj.Initializing = false;
            obj.render();
        end

        function tf = get.HasDigitalTracks(obj)
            tf = ~isempty(obj.Digital) && isfield(obj.Digital, 'X') && ~isempty(obj.Digital.X);
        end

        function tf = get.HasAuxTracks(obj)
            tf = ~isempty(obj.Aux) && isfield(obj.Aux, 'X') && ~isempty(obj.Aux.X);
        end
    end

    methods (Static)
        [te, Ye] = decimateMinMax(tt, seg, nPix)
        C = binColumnsMean(seg, nPix)
    end

    methods (Access = private)
        buildLayout(obj, parent, hasDigital, hasAux)
        renderTraces(obj, seg, tt, chIdx)
        renderHeatmap(obj, seg, tt, chIdx)
        renderDigital(obj, tt, i0, i1)
        renderAux(obj, tt, i0, i1)
        attachCallbacks(obj)
        tf = cursorOverAxes(obj)
        guardedCall(obj, fcn)
    end
end
