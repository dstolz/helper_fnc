function buildReviewTab(obj)
%buildReviewTab  Summary stats + plots for a Kilosort4 results folder.
%   Pick a kilosort4/ output folder (or a scanned dataset), then load(); the
%   left column shows aggregate stats and a per-unit table, the right column
%   shows units-per-shank, mean waveforms, spike amplitudes over time, and
%   per-unit firing rates. Selecting a table row focuses the waveform and
%   amplitude plots on that single unit; "Show all units" clears the focus.
%   All parsing happens once in loadReviewResults; selection only re-renders
%   from the cached ReviewData. See loadReviewResults / renderReviewPlots.

g = uigridlayout(obj.TabReview, [1 2]);
g.ColumnWidth = {380, '1x'};
g.Padding     = [10 10 10 10];

% =================== left column: source + stats + table ===================
left = uigridlayout(g, [8 1]);
left.Layout.Column = 1;
left.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', 220, '1x', 'fit'};
left.Padding   = [0 0 0 0];
left.RowSpacing = 6;

uilabel(left, "Text", "Kilosort4 results folder:", "FontWeight", "bold");

fr = uigridlayout(left, [1 2]);
fr.ColumnWidth = {'1x', 'fit'};
fr.Padding = [0 0 0 0];
obj.ReviewFolderField = uieditfield(fr, "text", ...
    "Placeholder", "...\<dataset>\kilosort4");
obj.BrowseReviewButton = uibutton(fr, "Text", "Browse...", ...
    "ButtonPushedFcn", @(~,~) obj.onBrowseReviewFolder());

dr = uigridlayout(left, [1 2]);
dr.ColumnWidth = {'1x', 'fit'};
dr.Padding = [0 0 0 0];
obj.ReviewDatasetDropDown = uidropdown(dr, ...
    "Items", {'(pick folder, or scan first)'}, ...
    "ValueChangedFcn", @(~,~) obj.onReviewDatasetChanged());
obj.LoadReviewButton = uibutton(dr, "Text", "Load", ...
    "ButtonPushedFcn", @(~,~) obj.loadReviewResults());

obj.OpenReviewFolderButton = uibutton(left, "Text", "Open folder in explorer", ...
    "ButtonPushedFcn", @(~,~) obj.onOpenReviewFolder());

uilabel(left, "Text", "Summary", "FontWeight", "bold");

summaryPanel = uipanel(left);
sg = uigridlayout(summaryPanel, [1 1]);
sg.Padding = [8 6 8 6];
obj.ReviewSummaryLabel = uilabel(sg, ...
    "Text", "Pick a Kilosort4 results folder and press Load.", ...
    "VerticalAlignment", "top", "WordWrap", "on", ...
    "FontName", "monospaced", "FontColor", [0.2 0.2 0.2]);

obj.ReviewUnitsTable = uitable(left, ...
    "ColumnName", {'Unit', 'Label', 'Shank', 'PkCh', '#Spk', 'FR(Hz)', 'Amp', 'Cont%'}, ...
    "ColumnWidth", {44, 44, 46, 42, 60, 56, 48, 52}, ...
    "RowName", {}, ...
    "ColumnSortable", true, ...
    "SelectionType", "row", ...
    "CellSelectionCallback", @(~, evt) obj.onReviewUnitSelected(evt));
obj.ReviewUnitsTable.Layout.Row = 7;

obj.ReviewAllUnitsButton = uibutton(left, "Text", "Show all units", ...
    "ButtonPushedFcn", @(~,~) obj.onReviewAllUnits());

% =================== right column: 2x2 axes ===================
right = uigridlayout(g, [2 2]);
right.Layout.Column = 2;
right.RowSpacing = 14;
right.ColumnSpacing = 14;

obj.ReviewShankAxes = uiaxes(right);
obj.ReviewShankAxes.Layout.Row = 1; obj.ReviewShankAxes.Layout.Column = 1;
title(obj.ReviewShankAxes, "Units per shank");

obj.ReviewWaveAxes = uiaxes(right);
obj.ReviewWaveAxes.Layout.Row = 1; obj.ReviewWaveAxes.Layout.Column = 2;
title(obj.ReviewWaveAxes, "Mean waveforms");

obj.ReviewAmpAxes = uiaxes(right);
obj.ReviewAmpAxes.Layout.Row = 2; obj.ReviewAmpAxes.Layout.Column = 1;
title(obj.ReviewAmpAxes, "Amplitudes over time");

obj.ReviewRateAxes = uiaxes(right);
obj.ReviewRateAxes.Layout.Row = 2; obj.ReviewRateAxes.Layout.Column = 2;
title(obj.ReviewRateAxes, "Firing rate per unit");
end
