function buildDatasetsTab(obj)
%buildDatasetsTab  Parent-dir picker + recursive scan + metadata table.

g = uigridlayout(obj.TabDatasets, [3 6]);
g.RowHeight    = {'fit', 'fit', '1x'};
g.ColumnWidth  = {'fit', '1x', 'fit', 'fit', 'fit', 'fit'};
g.Padding      = [10 10 10 10];

% Row 1: parent directory
lbl = uilabel(g, "Text", "Parent directory:");
lbl.Layout.Row = 1; lbl.Layout.Column = 1;

obj.RootPathField = uieditfield(g, "text", ...
    "Placeholder", "Folder scanned recursively for *.rhd recordings");
obj.RootPathField.Layout.Row = 1; obj.RootPathField.Layout.Column = 2;

obj.BrowseRootButton = uibutton(g, "Text", "Browse...", ...
    "ButtonPushedFcn", @(~,~) obj.onBrowseRoot());
obj.BrowseRootButton.Layout.Row = 1; obj.BrowseRootButton.Layout.Column = 3;

obj.ScanButton = uibutton(g, "Text", "Scan", ...
    "ButtonPushedFcn", @(~,~) obj.onScan());
obj.ScanButton.Layout.Row = 1; obj.ScanButton.Layout.Column = 4;

obj.RefreshMetaButton = uibutton(g, "Text", "Refresh metadata", ...
    "ButtonPushedFcn", @(~,~) obj.onRefreshMetadata());
obj.RefreshMetaButton.Layout.Row = 1; obj.RefreshMetaButton.Layout.Column = 5;

% "Open in phy" acts on the row selected below; disabled until a dataset with
% Kilosort4 output is selected (see updatePhyButtonState / onLaunchPhy).
obj.LaunchPhyButton = uibutton(g, "Text", "Open in phy", ...
    "ButtonPushedFcn", @(~,~) obj.onLaunchPhy(), "Enable", "off", ...
    "Tooltip", "Launch phy template-gui on the selected dataset's kilosort4 results.");
obj.LaunchPhyButton.Layout.Row = 1; obj.LaunchPhyButton.Layout.Column = 6;

% Row 2: status
obj.ScanStatusLabel = uilabel(g, "Text", "No datasets scanned yet.", ...
    "FontColor", [0.4 0.4 0.4]);
obj.ScanStatusLabel.Layout.Row = 2; obj.ScanStatusLabel.Layout.Column = [1 6];

% Row 3: datasets table
obj.DatasetsTable = uitable(g);
obj.DatasetsTable.Layout.Row = 3; obj.DatasetsTable.Layout.Column = [1 6];
obj.DatasetsTable.ColumnName = {'Select', 'Name', 'Acq date', '# files', ...
    '# chan', 'Fs (Hz)', 'Duration (min)', 'Format', 'Probe', 'Exclude', 'Kilosort'};
obj.DatasetsTable.ColumnEditable = ...
    [true false false false false false false false false false false];
obj.DatasetsTable.CellSelectionCallback = @(~,evt) obj.onDatasetCellSelection(evt);
obj.DatasetsTable.ColumnWidth = {50, 'auto', 130, 60, 60, 80, 100, 130, 60, 90, 90};
end
