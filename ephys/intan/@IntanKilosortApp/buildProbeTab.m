function buildProbeTab(obj)
%buildProbeTab  Pick a probe .json, channel-count check, assign to datasets.

g = uigridlayout(obj.TabProbe, [5 4]);
g.RowHeight   = {'fit', '1x', 'fit', 'fit', 'fit'};
g.ColumnWidth = {'fit', '1x', 'fit', 'fit'};
g.Padding     = [10 10 10 10];

% Row 1: probe folder
lbl = uilabel(g, "Text", "Probe folder:");
lbl.Layout.Row = 1; lbl.Layout.Column = 1;

obj.ProbeFolderField = uieditfield(g, "text", ...
    "Placeholder", "Folder of Kilosort4 probe .json files");
obj.ProbeFolderField.Layout.Row = 1; obj.ProbeFolderField.Layout.Column = 2;

obj.BrowseProbeFolderButton = uibutton(g, "Text", "Browse...", ...
    "ButtonPushedFcn", @(~,~) obj.onBrowseProbeFolder());
obj.BrowseProbeFolderButton.Layout.Row = 1; obj.BrowseProbeFolderButton.Layout.Column = 3;

obj.RefreshProbesButton = uibutton(g, "Text", "Refresh", ...
    "ButtonPushedFcn", @(~,~) obj.refreshProbeList());
obj.RefreshProbesButton.Layout.Row = 1; obj.RefreshProbesButton.Layout.Column = 4;

% Row 2: table of probes (name + parsed metadata) + info
obj.ProbeTable = uitable(g);
obj.ProbeTable.Layout.Row = 2; obj.ProbeTable.Layout.Column = [1 2];
obj.ProbeTable.ColumnName = {'Probe', 'Ch', 'Shanks', 'Depth (um)', 'Notes'};
obj.ProbeTable.ColumnEditable = [false false false false true];
obj.ProbeTable.ColumnWidth = {'auto', 45, 60, 80, 'auto'};
obj.ProbeTable.CellSelectionCallback = @(~,evt) obj.onProbeRowSelected(evt);
obj.ProbeTable.CellEditCallback = @(~,evt) obj.onProbeNotesEdited(evt);

infoPanel = uipanel(g, "Title", "Probe info");
infoPanel.Layout.Row = 2; infoPanel.Layout.Column = [3 4];
ig = uigridlayout(infoPanel, [3 1]);
ig.RowHeight = {'fit', 'fit', '1x'};
obj.ProbeInfoLabel = uilabel(ig, "Text", "Select a probe.", ...
    "VerticalAlignment", "top", "WordWrap", "on");
obj.ProbeCheckLabel = uilabel(ig, "Text", "", ...
    "VerticalAlignment", "top", "WordWrap", "on", "FontWeight", "bold");
obj.ProbePreviewAxes = uiaxes(ig);
obj.ProbePreviewAxes.Layout.Row = 3;
title(obj.ProbePreviewAxes, "Channel arrangement");
xlabel(obj.ProbePreviewAxes, "x (\mum)");
ylabel(obj.ProbePreviewAxes, "y (\mum)");

% Row 3: import
obj.ImportProbeButton = uibutton(g, "Text", "Import probe .json into folder...", ...
    "ButtonPushedFcn", @(~,~) obj.onImportProbe());
obj.ImportProbeButton.Layout.Row = 3; obj.ImportProbeButton.Layout.Column = [1 2];

% Row 4: per-recording channel exclusions (dropped from KS4 sorting, may
% differ across recordings). Reflects the active dataset; Apply writes it back.
exLbl = uilabel(g, "Text", "Exclude channels:", ...
    "Tooltip", "1-based channels to drop from Kilosort sorting, e.g. 1,5,32-40. May differ per recording.");
exLbl.Layout.Row = 4; exLbl.Layout.Column = 1;

obj.ExcludeChannelsField = uieditfield(g, "text", ...
    "Placeholder", "e.g. 1,5,32-40 (blank = none)", ...
    "ValueChangedFcn", @(~,~) obj.onApplyExclude("selected"));
obj.ExcludeChannelsField.Layout.Row = 4; obj.ExcludeChannelsField.Layout.Column = 2;

obj.ApplyExcludeSelectedButton = uibutton(g, "Text", "Apply to selected", ...
    "ButtonPushedFcn", @(~,~) obj.onApplyExclude("selected"));
obj.ApplyExcludeSelectedButton.Layout.Row = 4; obj.ApplyExcludeSelectedButton.Layout.Column = 3;

obj.ApplyExcludeAllButton = uibutton(g, "Text", "Apply to all", ...
    "ButtonPushedFcn", @(~,~) obj.onApplyExclude("all"));
obj.ApplyExcludeAllButton.Layout.Row = 4; obj.ApplyExcludeAllButton.Layout.Column = 4;

% Row 5: assign
obj.AssignSelectedButton = uibutton(g, "Text", "Assign to selected dataset", ...
    "ButtonPushedFcn", @(~,~) obj.onAssignProbe("selected"));
obj.AssignSelectedButton.Layout.Row = 5; obj.AssignSelectedButton.Layout.Column = 1;

obj.AssignAllButton = uibutton(g, "Text", "Assign to all datasets", ...
    "ButtonPushedFcn", @(~,~) obj.onAssignProbe("all"));
obj.AssignAllButton.Layout.Row = 5; obj.AssignAllButton.Layout.Column = 2;
end
