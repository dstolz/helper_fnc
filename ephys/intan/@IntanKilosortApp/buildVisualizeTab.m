function buildVisualizeTab(obj)
%buildVisualizeTab  Controls + axes for fast, display-only time-domain plots.
%   The Plot button reads the selected window once, applies any display-only
%   preprocessing, and hands the result to a MultiChannelViewer (obj.Viewer),
%   which owns all pan/zoom/scale/channel-scroll navigation from there without
%   touching disk. See onPlotVisualization and plotting/@MultiChannelViewer.

g = uigridlayout(obj.TabVisualize, [1 2]);
g.ColumnWidth = {320, '1x'};
g.Padding     = [10 10 10 10];

% --- left: controls panel ---
ctrl = uipanel(g, "Title", "Display options (does not modify data)");
ctrl.Layout.Column = 1;

nRows = 22;
cg = uigridlayout(ctrl, [nRows 2]);
cg.RowHeight   = [repmat({'fit'}, 1, nRows - 1), {'1x'}];
cg.ColumnWidth = {'fit', '1x'};

row = 1;
lab(cg, "Dataset:", row);
% Read-only mirror of the figure's "Dataset" menu, which owns the selection
% (see buildUI / populateDatasetMenu / selectDataset).
obj.VizDatasetLabel = uilabel(cg, "WordWrap", "on", ...
    "Text", "(none - scan, then pick from the Dataset menu)", ...
    "FontColor", [0.5 0.5 0.5], ...
    "Tooltip", "Choose the dataset from the Dataset menu in the menu bar.");
obj.VizDatasetLabel.Layout.Row = row; obj.VizDatasetLabel.Layout.Column = 2;

row = row + 1;
lab(cg, "File:", row);
obj.VizFileDropDown = uidropdown(cg);
obj.VizFileDropDown.Items = {'(all)'};
obj.VizFileDropDown.Layout.Row = row; obj.VizFileDropDown.Layout.Column = 2;

row = row + 1;
lab(cg, "Channels:", row);
obj.VizChannelsField = uieditfield(cg, "text", "Value", "1:8", ...
    "Placeholder", "e.g. 1:16 or 1 3 5");
obj.VizChannelsField.Layout.Row = row; obj.VizChannelsField.Layout.Column = 2;

row = row + 1;
lab(cg, "Start (s):", row);
obj.VizStartField = uieditfield(cg, "numeric", "Value", 0, "Limits", [0 Inf]);
obj.VizStartField.Layout.Row = row; obj.VizStartField.Layout.Column = 2;

row = row + 1;
lab(cg, "Window (s):", row);
obj.VizDurField = uieditfield(cg, "numeric", "Value", 2, "Limits", [0.01 Inf]);
obj.VizDurField.Layout.Row = row; obj.VizDurField.Layout.Column = 2;

row = row + 1;
lab(cg, "High-pass (Hz):", row);
obj.VizHighpassField = uieditfield(cg, "text", "Value", "300", ...
    "Placeholder", "blank = off");
obj.VizHighpassField.Layout.Row = row; obj.VizHighpassField.Layout.Column = 2;

row = row + 1;
lab(cg, "Low-pass (Hz):", row);
obj.VizLowpassField = uieditfield(cg, "text", "Value", "", ...
    "Placeholder", "blank = off");
obj.VizLowpassField.Layout.Row = row; obj.VizLowpassField.Layout.Column = 2;

row = row + 1;
lab(cg, "Filter order:", row);
obj.VizOrderField = uieditfield(cg, "numeric", "Value", 4, "Limits", [1 8], ...
    "RoundFractionalValues", "on");
obj.VizOrderField.Layout.Row = row; obj.VizOrderField.Layout.Column = 2;

row = row + 1;
lab(cg, "Reference:", row);
obj.VizRefDropDown = uidropdown(cg);
obj.VizRefDropDown.Items = {'None', 'Common average (mean)', 'Common median'};
obj.VizRefDropDown.ItemsData = {'none', 'car', 'cmr'};
obj.VizRefDropDown.Value = 'none';
obj.VizRefDropDown.Layout.Row = row; obj.VizRefDropDown.Layout.Column = 2;

row = row + 1;
obj.VizDetrendCheckBox = uicheckbox(cg, "Text", "Detrend (remove mean)", "Value", true);
obj.VizDetrendCheckBox.Layout.Row = row; obj.VizDetrendCheckBox.Layout.Column = [1 2];

row = row + 1;
lab(cg, "Plot type:", row);
obj.VizModeDropDown = uidropdown(cg);
obj.VizModeDropDown.Items = {'Traces', 'Heatmap'};
obj.VizModeDropDown.ItemsData = {'traces', 'heatmap'};
obj.VizModeDropDown.Value = 'traces';
obj.VizModeDropDown.ValueChangedFcn = @(~,~) obj.onVizModeChanged();
obj.VizModeDropDown.Layout.Row = row; obj.VizModeDropDown.Layout.Column = 2;

row = row + 1;
lab(cg, "Trace spacing (uV):", row);
obj.VizSpacingField = uieditfield(cg, "numeric", "Value", 200, "Limits", [0 Inf]);
obj.VizSpacingField.ValueChangedFcn = @(src,~) setViewerSpacing(obj, src.Value);
obj.VizSpacingField.Layout.Row = row; obj.VizSpacingField.Layout.Column = 2;

row = row + 1;
lab(cg, "Heatmap colors:", row);
obj.VizColormapDropDown = uidropdown(cg);
obj.VizColormapDropDown.Items = {'turbo', 'parula', 'hot', 'gray', 'jet'};
obj.VizColormapDropDown.Value = 'turbo';
obj.VizColormapDropDown.ValueChangedFcn = @(~,~) obj.onVizColormapChanged();
obj.VizColormapDropDown.Layout.Row = row; obj.VizColormapDropDown.Layout.Column = 2;

row = row + 1;
obj.VizSortByProbeCheckBox = uicheckbox(cg, "Text", "Sort channels by probe map", ...
    "Value", false, ...
    "Tooltip", ["Display channels in probe shank/depth order (from the " ...
        "dataset's assigned probe .json) instead of the order typed above. " ...
        "Channels not found in the probe map are shown last, unchanged."], ...
    "ValueChangedFcn", @(~,~) obj.applyVizChannelOrder());
obj.VizSortByProbeCheckBox.Layout.Row = row; obj.VizSortByProbeCheckBox.Layout.Column = [1 2];

row = row + 1;
obj.VizColorByShankCheckBox = uicheckbox(cg, "Text", "Color channels by shank", ...
    "Value", false, ...
    "Tooltip", ["Color each trace by its probe shank (from the dataset's " ...
        "assigned probe .json) instead of the default per-channel color " ...
        "cycle. Channels not found in the probe map share a single color."], ...
    "ValueChangedFcn", @(~,~) obj.applyVizChannelColor());
obj.VizColorByShankCheckBox.Layout.Row = row; obj.VizColorByShankCheckBox.Layout.Column = [1 2];

row = row + 1;
obj.VizPlotButton = uibutton(cg, "Text", "Plot", ...
    "ButtonPushedFcn", @(~,~) obj.onPlotVisualization());
obj.VizPlotButton.Layout.Row = row; obj.VizPlotButton.Layout.Column = [1 2];

row = row + 1;
obj.VizStatusLabel = uilabel(cg, "Text", "", "FontColor", [0.4 0.4 0.4]);
obj.VizStatusLabel.Layout.Row = row; obj.VizStatusLabel.Layout.Column = [1 2];

row = row + 1;
obj.VizArtButton = uibutton(cg, "state", "Text", "Mark Artifacts: off", ...
    "Tooltip", ["Toggle artifact marking. When on: drag on the plot to mark a " ...
        "period to blank; click a marked region to remove it. Data on disk is " ...
        "never changed - marked periods are zeroed only when the .bin is written."], ...
    "ValueChangedFcn", @(src,~) obj.onVizArtToggle(src.Value));
obj.VizArtButton.Layout.Row = row; obj.VizArtButton.Layout.Column = [1 2];

row = row + 1;
obj.VizArtClearButton = uibutton(cg, "Text", "Clear Artifacts", ...
    "ButtonPushedFcn", @(~,~) obj.onVizArtClear());
obj.VizArtClearButton.Layout.Row = row; obj.VizArtClearButton.Layout.Column = [1 2];

row = row + 1;
obj.VizArtStatusLabel = uilabel(cg, "Text", "No artifacts defined.", ...
    "FontColor", [0.6 0.2 0.2]);
obj.VizArtStatusLabel.Layout.Row = row; obj.VizArtStatusLabel.Layout.Column = [1 2];

row = row + 1;
obj.VizHelpLabel = uilabel(cg, "WordWrap", "on", "FontColor", [0.3 0.3 0.3], ...
    "VerticalAlignment", "top", "Text", helpText());
obj.VizHelpLabel.Layout.Row = row; obj.VizHelpLabel.Layout.Column = [1 2];

% --- right: axes ---
obj.VizAxes = uiaxes(g);
obj.VizAxes.Layout.Column = 2;
xlabel(obj.VizAxes, "Time (s)");
ylabel(obj.VizAxes, "Channel (stacked, uV offset)");
title(obj.VizAxes, "Time-domain preview  -  press Plot, then navigate with the mouse");

% Mouse wheel/drag and keyboard navigation are owned by obj.Viewer once it is
% constructed (see onPlotVisualization), which self-attaches those figure-level
% callbacks (guarded internally to the Visualize tab via ActiveFcn=vizActive).
% WindowButtonDown/UpFcn are re-asserted there too, so plain-left artifact
% marking keeps taking precedence over the viewer's own pan gesture.
end


function setViewerSpacing(obj, value)
%setViewerSpacing  Apply a Trace-spacing field edit to the live viewer, if any.
if ~isempty(obj.Viewer) && isvalid(obj.Viewer)
    obj.Viewer.setSpacing(value);
end
end


function lab(parent, txt, row)
%lab  Create a column-1 label at the given grid row.
l = uilabel(parent, "Text", txt);
l.Layout.Row = row;
l.Layout.Column = 1;
end


function s = helpText()
%helpText  Mouse / keyboard navigation cheatsheet shown under the controls.
s = sprintf([ ...
    'Mouse over the plot:\n' ...
    '  middle-drag .......... pan time (+ amplitude, or channel scroll\n' ...
    '                         once more channels are loaded than shown)\n' ...
    '  wheel ................ fine scroll in time\n' ...
    '  Ctrl+wheel ........... jog one window at a time\n' ...
    '  Shift+wheel .......... zoom the time axis at cursor\n' ...
    '  Ctrl+Shift+wheel ..... scale channel amplitude\n' ...
    '  Alt+wheel ............ scroll the channel window\n' ...
    '  Alt+Ctrl+wheel ....... page the channel window\n' ...
    '  <- / -> .............. step time\n' ...
    '  up/down, PgUp/PgDn, Home/End .. scroll/page/jump channel window\n' ...
    '  = / - ................ amplitude gain     [ / ] ... channel spacing\n' ...
    '  m .................... toggle traces/heatmap\n' ...
    '  r .................... reset view          F1 ... full shortcut list\n' ...
    '\n' ...
    'Mark Artifacts (red regions are blanked when the .bin is written):\n' ...
    '  toggle on, then left-drag .. mark a period\n' ...
    '  left-click a region ........ remove it']);
end
