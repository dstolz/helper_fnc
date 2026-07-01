function buildArtifactsTab(obj)
%buildArtifactsTab  Controls + per-channel summary for automatic artifact blanking.
%   Configure the automatic amplitude-deviation detector (running-RMS by
%   default, threshold in robust standard deviations) and preview how much of a
%   recording it would zero. The "Detect" button streams the dataset one file at
%   a time (IntanDataset.analyzeArtifacts) and fills the per-channel table and
%   summary. The same settings are stored on every scanned dataset's
%   ArtifactConfig; when "Blank artifacts in .bin" (Kilosort tab) is ticked,
%   zeros the detected samples on every channel as the Kilosort .bin is written
%   (the original *.rhd files are never modified).
%
%   See also IntanDataset.detectArtifacts, IntanDataset.analyzeArtifacts,
%   IntanDataset.toBin, onDetectArtifacts.

g = uigridlayout(obj.TabArtifacts, [1 2]);
g.ColumnWidth = {340, '1x'};
g.Padding     = [10 10 10 10];

% =================== left: controls ===================
ctrl = uipanel(g, "Title", "Automatic artifact detection");
ctrl.Layout.Column = 1;

nRows = 18;
cg = uigridlayout(ctrl, [nRows 2]);
cg.RowHeight   = [repmat({'fit'}, 1, nRows - 1), {'1x'}];
cg.ColumnWidth = {'fit', '1x'};

row = 1;
lab(cg, "Dataset:", row);
obj.ArtDatasetDropDown = uidropdown(cg);
obj.ArtDatasetDropDown.Items = {'(scan first)'};
obj.ArtDatasetDropDown.Layout.Row = row; obj.ArtDatasetDropDown.Layout.Column = 2;

row = row + 1;
lab(cg, "Method:", row);
obj.ArtMethodDropDown = uidropdown(cg);
obj.ArtMethodDropDown.Items = {'Running RMS (per-channel SD)', 'MAD (per-channel SD)', ...
              'Absolute microvolts', 'Common-mode (mean)'};
obj.ArtMethodDropDown.ItemsData = {'rms', 'mad', 'microvolts', 'commonmode'};
obj.ArtMethodDropDown.Value = 'rms';
obj.ArtMethodDropDown.ValueChangedFcn = @(~,~) obj.onArtifactControlsChanged();
obj.ArtMethodDropDown.Layout.Row = row; obj.ArtMethodDropDown.Layout.Column = 2;

row = row + 1;
lab(cg, "Threshold (SD):", row);
obj.ArtThresholdField = uieditfield(cg, "numeric", "Value", 9, ...
    "Limits", [0 Inf], "Tooltip", ...
    "Flag samples this many robust standard deviations above the per-channel baseline.", ...
    "ValueChangedFcn", @(~,~) obj.onArtifactControlsChanged());
obj.ArtThresholdField.Layout.Row = row; obj.ArtThresholdField.Layout.Column = 2;

row = row + 1;
lab(cg, "RMS window (ms):", row);
obj.ArtRmsWindowField = uieditfield(cg, "numeric", "Value", 1, ...
    "Limits", [0 Inf], "Tooltip", ...
    "Running-RMS window length (ms). 0 = auto (~1 ms). Used by the RMS method only.", ...
    "ValueChangedFcn", @(~,~) obj.onArtifactControlsChanged());
obj.ArtRmsWindowField.Layout.Row = row; obj.ArtRmsWindowField.Layout.Column = 2;

row = row + 1;
lab(cg, "Stitch gap (ms):", row);
obj.ArtMergeGapField = uieditfield(cg, "numeric", "Value", 0, ...
    "Limits", [0 Inf], "Tooltip", ...
    ["Merge artifacts separated by at most this many milliseconds of clean " ...
     "signal into one continuous blanked block (stitching)."], ...
    "ValueChangedFcn", @(~,~) obj.onArtifactControlsChanged());
obj.ArtMergeGapField.Layout.Row = row; obj.ArtMergeGapField.Layout.Column = 2;

row = row + 1;
lab(cg, "Pad (ms):", row);
obj.ArtPadField = uieditfield(cg, "numeric", "Value", 0, ...
    "Limits", [0 Inf], "Tooltip", ...
    "Expand each flagged region by this many milliseconds on both sides.", ...
    "ValueChangedFcn", @(~,~) obj.onArtifactControlsChanged());
obj.ArtPadField.Layout.Row = row; obj.ArtPadField.Layout.Column = 2;

row = row + 1;
lab(cg, "Min channels:", row);
obj.ArtMinChannelsField = uieditfield(cg, "numeric", "Value", 2, ...
    "Limits", [1 Inf], "RoundFractionalValues", "on", "Tooltip", ...
    ["Minimum channels that must exceed the threshold at the same sample for it " ...
     "to be blanked (ignored for common-mode)."], ...
    "ValueChangedFcn", @(~,~) obj.onArtifactControlsChanged());
obj.ArtMinChannelsField.Layout.Row = row; obj.ArtMinChannelsField.Layout.Column = 2;

row = row + 1;
obj.ArtFilterCheckBox = uicheckbox(cg, "Text", "High-pass before detecting", ...
    "Value", false, "Tooltip", ...
    ["Detect on the high-pass-filtered signal instead of broadband. The .bin " ...
     "itself is still written broadband unless filtering is enabled there."], ...
    "ValueChangedFcn", @(~,~) obj.onArtifactControlsChanged());
obj.ArtFilterCheckBox.Layout.Row = row; obj.ArtFilterCheckBox.Layout.Column = [1 2];

row = row + 1;
lab(cg, "High-pass (Hz):", row);
obj.ArtHighpassField = uieditfield(cg, "numeric", "Value", 300, ...
    "Limits", [0 Inf], "Enable", "off", ...
    "ValueChangedFcn", @(~,~) obj.onArtifactControlsChanged());
obj.ArtHighpassField.Layout.Row = row; obj.ArtHighpassField.Layout.Column = 2;

row = row + 1;
obj.ArtDetectButton = uibutton(cg, "Text", "Detect / Preview", ...
    "ButtonPushedFcn", @(~,~) obj.onDetectArtifacts());
obj.ArtDetectButton.Layout.Row = row; obj.ArtDetectButton.Layout.Column = [1 2];

row = row + 1;
obj.ArtStatusLabel = uilabel(cg, "Text", "", "FontColor", [0.4 0.4 0.4], ...
    "WordWrap", "on");
obj.ArtStatusLabel.Layout.Row = row; obj.ArtStatusLabel.Layout.Column = [1 2];

% =================== right: summary + per-channel table ===================
right = uigridlayout(g, [3 1]);
right.Layout.Column = 2;
right.RowHeight = {'fit', 130, '1x'};
right.RowSpacing = 8;

uilabel(right, "Text", "Summary", "FontWeight", "bold");

summaryPanel = uipanel(right);
sg = uigridlayout(summaryPanel, [1 1]);
sg.Padding = [8 6 8 6];
obj.ArtSummaryLabel = uilabel(sg, ...
    "Text", "Pick a dataset and press Detect / Preview.", ...
    "VerticalAlignment", "top", "WordWrap", "on", ...
    "FontName", "monospaced", "FontColor", [0.2 0.2 0.2]);

obj.ArtChannelTable = uitable(right, ...
    "ColumnName", {'Ch', 'Name', '#Samples', '% of duration'}, ...
    "ColumnWidth", {44, '1x', 100, 110}, ...
    "RowName", {});
obj.ArtChannelTable.Layout.Row = 3;
end


function lab(parent, txt, row)
%lab  Create a column-1 label at the given grid row.
l = uilabel(parent, "Text", txt);
l.Layout.Row = row;
l.Layout.Column = 1;
end
