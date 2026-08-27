function buildUI(obj)
%buildUI  Create the figure and the five tabs.

pos = [120 90 1180 760];   % default; overridden by saved pref in loadPreferences
obj.Fig = uifigure("Name", "Intan -> Kilosort4", "Position", pos);
obj.Fig.CloseRequestFcn = @(~,~) obj.onClose();

% App-wide single-dataset picker. The items are filled in by
% populateDatasetMenu once a scan has found datasets; selectDataset ticks the
% active one and drives the Visualize tab (see updateDatasetMenuCheck).
obj.DatasetMenu = uimenu(obj.Fig, "Text", "Dataset");
obj.DatasetMenuItems = uimenu(obj.DatasetMenu, "Text", "(scan first)", "Enable", "off");

% Two-row layout: the tab group fills the figure, with a thin status bar strip
% pinned along the bottom (see buildStatusBar / setStatus).
outer = uigridlayout(obj.Fig, [2 1]);
outer.RowHeight   = {'1x', 24};
outer.ColumnWidth = {'1x'};
outer.RowSpacing  = 0;
outer.Padding     = [0 0 0 0];

obj.Tabs = uitabgroup(outer);
obj.Tabs.Layout.Row = 1; obj.Tabs.Layout.Column = 1;
% Update the status bar's contextual hint whenever the active tab changes.
obj.Tabs.SelectionChangedFcn = @(~,~) obj.onTabChanged();

buildStatusBar(obj, outer);

% Tab order (left to right): Datasets, Probe, Artifacts, Visualize, Kilosort,
% Review. Probe sits next to Datasets; Visualize sits to the right of Artifacts.
obj.TabDatasets  = uitab(obj.Tabs, "Title", "Datasets");
obj.TabProbe     = uitab(obj.Tabs, "Title", "Probe");
obj.TabArtifacts = uitab(obj.Tabs, "Title", "Artifacts");
obj.TabVisualize = uitab(obj.Tabs, "Title", "Visualize");
obj.TabKilosort  = uitab(obj.Tabs, "Title", "Kilosort");
obj.TabReview    = uitab(obj.Tabs, "Title", "Review");

obj.buildDatasetsTab();
obj.buildVisualizeTab();
obj.buildArtifactsTab();
obj.buildProbeTab();
obj.buildKilosortTab();
obj.buildReviewTab();

obj.onTabChanged();   % seed the status bar for the initially-shown tab
end


function buildStatusBar(obj, parent)
%buildStatusBar  Status strip along the bottom of the figure.
%   Left label reports the last action / current state; the right label offers a
%   suggested next step (updated by setStatus / suggestNextStep). The two are
%   colour-coded so the "what happened" and "what to do next" read distinctly.
panel = uipanel(parent, "BorderType", "line", ...
    "BackgroundColor", [0.96 0.96 0.98]);
panel.Layout.Row = 2; panel.Layout.Column = 1;

sg = uigridlayout(panel, [1 2]);
sg.ColumnWidth  = {'1x', 'fit'};
sg.RowHeight    = {'1x'};
sg.Padding      = [8 0 8 0];
sg.ColumnSpacing = 16;

obj.StatusBar = uilabel(sg, "Text", "Ready.", ...
    "FontColor", [0.15 0.15 0.15], "VerticalAlignment", "center");
obj.StatusBar.Layout.Row = 1; obj.StatusBar.Layout.Column = 1;

obj.StatusHint = uilabel(sg, "Text", "", "FontAngle", "italic", ...
    "FontColor", [0.15 0.45 0.75], "HorizontalAlignment", "right", ...
    "VerticalAlignment", "center");
obj.StatusHint.Layout.Row = 1; obj.StatusHint.Layout.Column = 2;
end
