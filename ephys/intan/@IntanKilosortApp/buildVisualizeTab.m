function buildVisualizeTab(obj)
%buildVisualizeTab  Controls + axes for fast, display-only time-domain plots.
%   The Plot button reads the selected window once, applies any display-only
%   preprocessing, and caches the result so the view can be panned, zoomed and
%   scaled with the mouse without touching disk. See onPlotVisualization and
%   renderViz.

g = uigridlayout(obj.TabVisualize, [1 2]);
g.ColumnWidth = {320, '1x'};
g.Padding     = [10 10 10 10];

% --- left: controls panel ---
ctrl = uipanel(g, "Title", "Display options (does not modify data)");
ctrl.Layout.Column = 1;

nRows = 20;
cg = uigridlayout(ctrl, [nRows 2]);
cg.RowHeight   = [repmat({'fit'}, 1, nRows - 1), {'1x'}];
cg.ColumnWidth = {'fit', '1x'};

row = 1;
lab(cg, "Dataset:", row);
obj.VizDatasetDropDown = uidropdown(cg, "Items", {'(scan first)'}, ...
    "ValueChangedFcn", @(~,~) obj.populateVizFiles());
obj.VizDatasetDropDown.Layout.Row = row; obj.VizDatasetDropDown.Layout.Column = 2;

row = row + 1;
lab(cg, "File:", row);
obj.VizFileDropDown = uidropdown(cg, "Items", {'(all)'});
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
obj.VizRefDropDown = uidropdown(cg, ...
    "Items", {'None', 'Common average (mean)', 'Common median'}, ...
    "ItemsData", {'none', 'car', 'cmr'}, "Value", 'none');
obj.VizRefDropDown.Layout.Row = row; obj.VizRefDropDown.Layout.Column = 2;

row = row + 1;
obj.VizDetrendCheckBox = uicheckbox(cg, "Text", "Detrend (remove mean)", "Value", true);
obj.VizDetrendCheckBox.Layout.Row = row; obj.VizDetrendCheckBox.Layout.Column = [1 2];

row = row + 1;
lab(cg, "Plot type:", row);
obj.VizModeDropDown = uidropdown(cg, ...
    "Items", {'Traces', 'Heatmap'}, "ItemsData", {'traces', 'heatmap'}, ...
    "Value", 'traces', "ValueChangedFcn", @(~,~) obj.onVizModeChanged());
obj.VizModeDropDown.Layout.Row = row; obj.VizModeDropDown.Layout.Column = 2;

row = row + 1;
lab(cg, "Trace spacing (uV):", row);
obj.VizSpacingField = uieditfield(cg, "numeric", "Value", 200, "Limits", [0 Inf]);
obj.VizSpacingField.Layout.Row = row; obj.VizSpacingField.Layout.Column = 2;

row = row + 1;
lab(cg, "Heatmap colors:", row);
obj.VizColormapDropDown = uidropdown(cg, ...
    "Items", {'turbo', 'parula', 'hot', 'gray', 'jet'}, "Value", 'turbo', ...
    "ValueChangedFcn", @(~,~) obj.onVizColormapChanged());
obj.VizColormapDropDown.Layout.Row = row; obj.VizColormapDropDown.Layout.Column = 2;

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

% --- figure-level mouse / key navigation (guarded to the Visualize tab) ---
obj.Fig.WindowScrollWheelFcn = @(~, evt) obj.onVizScroll(evt);
obj.Fig.WindowButtonDownFcn  = @(~, ~)   obj.onVizButtonDown();
obj.Fig.WindowButtonUpFcn    = @(~, ~)   obj.onVizButtonUp();
obj.Fig.WindowKeyPressFcn    = @(~, evt) obj.onVizKey(evt, true);
obj.Fig.WindowKeyReleaseFcn  = @(~, evt) obj.onVizKey(evt, false);
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
    '  middle-drag .......... pan time (+ amplitude in traces)\n' ...
    '  wheel ................ fine scroll in time\n' ...
    '  Ctrl+wheel ........... jog one window at a time\n' ...
    '  Shift+wheel .......... zoom the time axis at cursor\n' ...
    '  Ctrl+Shift+wheel ..... scale channel amplitude\n' ...
    '  <- / -> .............. step time     r ... reset view\n' ...
    '\n' ...
    'Mark Artifacts (red regions are blanked when the .bin is written):\n' ...
    '  toggle on, then left-drag .. mark a period\n' ...
    '  left-click a region ........ remove it']);
end
