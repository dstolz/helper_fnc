function buildConvertTab(obj)
%buildConvertTab  Derived-signal conversions (LFP / MUA / SPIKE -> .mat).
%   The left panel exposes every IntanDataset.deriveSignals option (the
%   intan2matlab options) plus where and how the results are saved; the right
%   panel lists the datasets a run would convert (those ticked on the Datasets
%   tab, or all when none are ticked) with their output file and status, and
%   shows run progress (overall + per-step bars, current step, log). The
%   conversion itself is onRunConvert -> IntanDataset.toMat; the recording
%   files are only read, never modified.
%
%   See also IntanDataset.toMat, IntanDataset.deriveSignals, onRunConvert,
%   gatherConvertConfig, applyConvertConfig.

g = uigridlayout(obj.TabConvert, [1 2]);
g.ColumnWidth = {560, '1x'};
g.Padding     = [10 10 10 10];

% =================== left: signal options ===================
opt = uipanel(g, "Title", "Signal options (IntanDataset.deriveSignals / intan2matlab)");
opt.Layout.Column = 1;

nRows = 26;
cg = uigridlayout(opt, [nRows 5]);
cg.Scrollable  = "on";
cg.RowHeight   = repmat({26}, 1, nRows);
cg.ColumnWidth = {130, '1x', 110, '1x', 30};

changed = @(~,~) obj.onConvertControlsChanged();

% --- Output ---
r = 1;
sep(cg, "Output", r);

r = r + 1;
l = lab(cg, "Output folder:", r);
l.Tooltip = "Folder for the .mat files. Blank = each dataset's own raw data folder.";
obj.ConvOutputDirField = uieditfield(cg, "text", ...
    "Placeholder", "blank = each dataset's raw data folder", ...
    "Tooltip", ["Folder for the .mat files. Leave blank to save next to the raw " ...
                "data (each dataset's folder). A folder given here is created if needed."], ...
    "ValueChangedFcn", changed);
obj.ConvOutputDirField.Layout.Row = r; obj.ConvOutputDirField.Layout.Column = [2 4];
obj.ConvBrowseOutputButton = uibutton(cg, "Text", "...", ...
    "ButtonPushedFcn", @(~,~) obj.onBrowseConvertOutput());
obj.ConvBrowseOutputButton.Layout.Row = r; obj.ConvBrowseOutputButton.Layout.Column = 5;

r = r + 1;
lab(cg, "File suffix:", r);
obj.ConvSuffixField = uieditfield(cg, "text", "Value", "_extract", ...
    "Tooltip", "Output file name is <dataset name><suffix>.mat.", ...
    "ValueChangedFcn", changed);
obj.ConvSuffixField.Layout.Row = r; obj.ConvSuffixField.Layout.Column = 2;
l = lab(cg, "MAT version:", r); l.Layout.Column = 3;
obj.ConvMatVersionDropDown = uidropdown(cg, ...
    "Items", {'-v7.3 (any size)', '-v7 (< 2 GB per variable)'}, ...
    "ItemsData", {'-v7.3', '-v7'}, "Value", '-v7.3', ...
    "Tooltip", ["MAT-file version passed to save(). -v7 cannot hold variables " ...
                "over 2 GB; if save() warns, the output is discarded and reported."], ...
    "ValueChangedFcn", changed);
obj.ConvMatVersionDropDown.Layout.Row = r; obj.ConvMatVersionDropDown.Layout.Column = [4 5];

r = r + 1;
obj.ConvOverwriteCheckBox = uicheckbox(cg, "Text", "Overwrite existing output files", ...
    "Value", false, "Tooltip", ...
    "When off, datasets whose output .mat already exists are skipped (and logged).", ...
    "ValueChangedFcn", changed);
obj.ConvOverwriteCheckBox.Layout.Row = r; obj.ConvOverwriteCheckBox.Layout.Column = [1 5];

% --- dataTypeOut ---
r = r + 1;
sep(cg, "Signals to compute (dataTypeOut)", r);

r = r + 1;
obj.ConvLFPCheckBox = uicheckbox(cg, "Text", "LFP", "Value", true, ...
    "Tooltip", ["Y.LFP: amplifier data resampled to LFP_Fs, then the optional " ...
                "zero-phase high-pass / low-pass / notch filters below."], ...
    "ValueChangedFcn", changed);
obj.ConvLFPCheckBox.Layout.Row = r; obj.ConvLFPCheckBox.Layout.Column = 1;
obj.ConvMUACheckBox = uicheckbox(cg, "Text", "MUA", "Value", false, ...
    "Tooltip", ["Y.MUA: bandpass at the original rate, rectify, resample to MUA_Fs, " ...
                "moving-mean integration."], ...
    "ValueChangedFcn", changed);
obj.ConvMUACheckBox.Layout.Row = r; obj.ConvMUACheckBox.Layout.Column = 2;
obj.ConvSPIKECheckBox = uicheckbox(cg, "Text", "SPIKE", "Value", false, ...
    "Tooltip", "Y.SPIKE: optional resample to SPIKE_Fs, then zero-phase bandpass.", ...
    "ValueChangedFcn", changed);
obj.ConvSPIKECheckBox.Layout.Row = r; obj.ConvSPIKECheckBox.Layout.Column = 3;

% --- LFP ---
r = r + 1;
sep(cg, "LFP", r);

r = r + 1;
lab(cg, "LFP_Fs (Hz):", r);
obj.ConvLFPFsField = numField(cg, 1000, "Target LFP sampling rate (resample).", changed);
obj.ConvLFPFsField.Layout.Row = r; obj.ConvLFPFsField.Layout.Column = 2;

r = r + 1;
obj.ConvLFPHighpassCheckBox = uicheckbox(cg, "Text", "High-pass (Hz):", ...
    "Value", false, "Tooltip", ...
    ["LFP_bpLoHi(1): 4th-order Butterworth high-pass, zero-phase (filtfilt), " ...
     "designed at LFP_Fs after resampling. Off = no high-pass. Expect edge " ...
     "transients in the first/last ~2 s for 1 Hz (longer for lower cut-offs)."], ...
    "ValueChangedFcn", changed);
obj.ConvLFPHighpassCheckBox.Layout.Row = r; obj.ConvLFPHighpassCheckBox.Layout.Column = 1;
obj.ConvLFPHighpassField = numField(cg, 1, ...
    "High-pass cut-off (Hz); must be below LFP_Fs / 2 and the low-pass cut-off.", changed);
obj.ConvLFPHighpassField.Layout.Row = r; obj.ConvLFPHighpassField.Layout.Column = 2;
obj.ConvLFPLowpassCheckBox = uicheckbox(cg, "Text", "Low-pass (Hz):", ...
    "Value", false, "Tooltip", ...
    ["LFP_bpLoHi(2): 4th-order Butterworth low-pass, zero-phase (filtfilt), " ...
     "designed at LFP_Fs after resampling. Off = no low-pass beyond " ...
     "resample's anti-aliasing. With both ticked it is one bandpass."], ...
    "ValueChangedFcn", changed);
obj.ConvLFPLowpassCheckBox.Layout.Row = r; obj.ConvLFPLowpassCheckBox.Layout.Column = 3;
obj.ConvLFPLowpassField = numField(cg, 300, ...
    "Low-pass cut-off (Hz); must be below LFP_Fs / 2.", changed);
obj.ConvLFPLowpassField.Layout.Row = r; obj.ConvLFPLowpassField.Layout.Column = [4 5];

r = r + 1;
obj.ConvLFPNotchCheckBox = uicheckbox(cg, "Text", "Notch (Hz):", ...
    "Value", false, "Tooltip", ...
    ["LFP_NotchHz: zero-phase band-stop (2nd-order Butterworth, filtfilt) at " ...
     "each listed frequency, e.g. line noise 60 or 60, 120, 180."], ...
    "ValueChangedFcn", changed);
obj.ConvLFPNotchCheckBox.Layout.Row = r; obj.ConvLFPNotchCheckBox.Layout.Column = 1;
obj.ConvLFPNotchField = uieditfield(cg, "text", "Value", "60", ...
    "Placeholder", "e.g. 60, 120, 180", "Tooltip", ...
    "Notch center frequencies (Hz), separated by commas or spaces.", ...
    "ValueChangedFcn", changed);
obj.ConvLFPNotchField.Layout.Row = r; obj.ConvLFPNotchField.Layout.Column = 2;
l = lab(cg, "Notch width (Hz):", r); l.Layout.Column = 3;
l.Tooltip = "LFP_NotchBW";
obj.ConvLFPNotchBWField = numField(cg, 2, ...
    ["LFP_NotchBW: each notch removes f +/- width/2 (the -3 dB points of the " ...
     "design; -6 dB after filtfilt)."], changed);
obj.ConvLFPNotchBWField.Layout.Row = r; obj.ConvLFPNotchBWField.Layout.Column = [4 5];

% --- MUA ---
r = r + 1;
sep(cg, "MUA", r);

r = r + 1;
lab(cg, "MUA_Fs (Hz):", r);
obj.ConvMUAFsField = numField(cg, 2000, "Sampling rate of the MUA envelope.", changed);
obj.ConvMUAFsField.Layout.Row = r; obj.ConvMUAFsField.Layout.Column = 2;
l = lab(cg, "Integration (Hz):", r); l.Layout.Column = 3;
l.Tooltip = "MUA_IntegrationHz";
obj.ConvMUAIntegrationField = numField(cg, 1000, ...
    ["MUA_IntegrationHz: moving-mean window = round(MUA_Fs / MUA_IntegrationHz) " ...
     "samples on the MUA_Fs grid."], changed);
obj.ConvMUAIntegrationField.Layout.Row = r; obj.ConvMUAIntegrationField.Layout.Column = [4 5];

r = r + 1;
lab(cg, "Bandpass low (Hz):", r);
obj.ConvMUALoField = numField(cg, 300, ...
    "MUA_bpLoHi(1): 4th-order Butterworth, zero-phase, designed at the original rate.", changed);
obj.ConvMUALoField.Layout.Row = r; obj.ConvMUALoField.Layout.Column = 2;
l = lab(cg, "Bandpass high (Hz):", r); l.Layout.Column = 3;
obj.ConvMUAHiField = numField(cg, 5000, ...
    "MUA_bpLoHi(2): must be below half the original amplifier rate.", changed);
obj.ConvMUAHiField.Layout.Row = r; obj.ConvMUAHiField.Layout.Column = [4 5];

% --- SPIKE ---
r = r + 1;
sep(cg, "SPIKE", r);

r = r + 1;
obj.ConvSpikeOrigCheckBox = uicheckbox(cg, "Text", "Keep original rate (SPIKE_Fs = Inf)", ...
    "Value", true, "Tooltip", "Do not resample the spike band.", ...
    "ValueChangedFcn", changed);
obj.ConvSpikeOrigCheckBox.Layout.Row = r; obj.ConvSpikeOrigCheckBox.Layout.Column = [1 2];
l = lab(cg, "SPIKE_Fs (Hz):", r); l.Layout.Column = 3;
obj.ConvSpikeFsField = numField(cg, 20000, ...
    "Target spike-band sampling rate (used when 'Keep original rate' is off).", changed);
obj.ConvSpikeFsField.Layout.Row = r; obj.ConvSpikeFsField.Layout.Column = [4 5];

r = r + 1;
lab(cg, "Bandpass low (Hz):", r);
obj.ConvSpikeLoField = numField(cg, 300, ...
    "SPIKE_bpLoHi(1): 4th-order Butterworth, zero-phase, designed at SPIKE_Fs.", changed);
obj.ConvSpikeLoField.Layout.Row = r; obj.ConvSpikeLoField.Layout.Column = 2;
l = lab(cg, "Bandpass high (Hz):", r); l.Layout.Column = 3;
obj.ConvSpikeHiField = numField(cg, 5000, ...
    "SPIKE_bpLoHi(2): must be below SPIKE_Fs / 2.", changed);
obj.ConvSpikeHiField.Layout.Row = r; obj.ConvSpikeHiField.Layout.Column = [4 5];

% --- Channels ---
r = r + 1;
sep(cg, "Channels", r);

r = r + 1;
lab(cg, "Label field:", r);
obj.ConvLabelFieldDropDown = uidropdown(cg, ...
    "Items", {'custom_channel_name', 'native_channel_name'}, ...
    "Value", 'custom_channel_name', "Tooltip", ...
    "labelField: Intan channel field used for info.labels and the digital-event names.", ...
    "ValueChangedFcn", changed);
obj.ConvLabelFieldDropDown.Layout.Row = r; obj.ConvLabelFieldDropDown.Layout.Column = [2 5];

r = r + 1;
lab(cg, "Keep amp channels:", r);
obj.ConvKeepChannelsField = uieditfield(cg, "text", ...
    "Placeholder", "blank = all (e.g. 1-32, 40)", "Tooltip", ...
    ["keepAmpChannels: 1-based amplifier channels to load, in the order given " ...
     "(e.g. 1-16, 20, 32-17). Blank = all."], ...
    "ValueChangedFcn", changed);
obj.ConvKeepChannelsField.Layout.Row = r; obj.ConvKeepChannelsField.Layout.Column = [2 5];

r = r + 1;
lab(cg, "Bad channels:", r);
obj.ConvBadModeDropDown = uidropdown(cg, ...
    "Items", {'None', 'Manual list (below)', 'Auto: |zscore(RMS of LFP)| > threshold'}, ...
    "ItemsData", {'none', 'manual', 'auto'}, "Value", 'none', "Tooltip", ...
    ["badChannels: channels replaced by spatial interpolation across neighboring " ...
     "columns (fillmissing 'makima'). Auto flags channels with |zscore(RMS of LFP)| " ...
     "above the threshold and requires LFP."], ...
    "ValueChangedFcn", changed);
obj.ConvBadModeDropDown.Layout.Row = r; obj.ConvBadModeDropDown.Layout.Column = [2 5];

r = r + 1;
lab(cg, "Auto threshold:", r);
obj.ConvBadThresholdField = numField(cg, 3, ...
    "Auto mode: flag channels whose |zscore(RMS of LFP)| exceeds this value.", changed);
obj.ConvBadThresholdField.Layout.Row = r; obj.ConvBadThresholdField.Layout.Column = 2;

r = r + 1;
lab(cg, "Bad channel list:", r);
obj.ConvBadListField = uieditfield(cg, "text", ...
    "Placeholder", "e.g. 3, 17-18", "Tooltip", ...
    ["Manual mode: 1-based column indices AFTER 'Keep amp channels' and BEFORE " ...
     "'Channel remap'. These channels are interpolated, not dropped."], ...
    "ValueChangedFcn", changed);
obj.ConvBadListField.Layout.Row = r; obj.ConvBadListField.Layout.Column = [2 5];

r = r + 1;
lab(cg, "Channel remap:", r);
obj.ConvRemapField = uieditfield(cg, "text", ...
    "Placeholder", "blank = none (e.g. 32-1)", "Tooltip", ...
    ["channelRemap: final column order applied after processing (1-based, " ...
     "into the kept channels). info.labels is reordered to match."], ...
    "ValueChangedFcn", changed);
obj.ConvRemapField.Layout.Row = r; obj.ConvRemapField.Layout.Column = [2 5];

r = r + 1;
note = uilabel(cg, "WordWrap", "on", "FontColor", [0.4 0.4 0.4], "Text", ...
    ["Order: keep channels -> LFP (resample, then filters) / MUA / SPIKE -> " ...
     "interpolate bad channels -> " ...
     "remap. Lists accept 1-based indices and ranges (1-16, 20, 32-17); order is kept."]);
note.Layout.Row = r; note.Layout.Column = [1 5];
cg.RowHeight{r} = 40;

r = r + 1;
obj.ConvResetButton = uibutton(cg, "Text", "Reset to defaults", ...
    "Tooltip", "Restore the default signal options (and a blank output folder).", ...
    "ButtonPushedFcn", @(~,~) obj.onResetConvertConfig());
obj.ConvResetButton.Layout.Row = r; obj.ConvResetButton.Layout.Column = 2;

% =================== right: targets + progress + log ===================
runPanel = uipanel(g, "Title", "Run");
runPanel.Layout.Column = 2;
rg = uigridlayout(runPanel, [8 3]);
rg.RowHeight   = {'fit', '1x', 'fit', 20, 20, 'fit', 'fit', '1x'};
rg.ColumnWidth = {'fit', '1x', 110};

hint = uilabel(rg, "WordWrap", "on", "FontColor", [0.4 0.4 0.4], "Text", ...
    ["Converts the datasets ticked on the Datasets tab (none ticked = all). " ...
     "Each dataset reads its own recording through IntanDataset, so " ...
     "traditional *.rhd, one-file-per-signal and one-file-per-channel " ...
     "folders are all supported."]);
hint.Layout.Row = 1; hint.Layout.Column = [1 3];

obj.ConvTargetsTable = uitable(rg, ...
    "ColumnName", {'Dataset', 'Format', 'Output file', 'Status'}, ...
    "ColumnWidth", {130, 125, '1x', 200}, "RowName", {});
obj.ConvTargetsTable.Layout.Row = 2; obj.ConvTargetsTable.Layout.Column = [1 3];

bg = uigridlayout(rg, [1 4]);
bg.Layout.Row = 3; bg.Layout.Column = [1 3];
bg.ColumnWidth = {'fit', 'fit', '1x', 'fit'};
bg.Padding = [0 0 0 0];
obj.ConvRunButton = uibutton(bg, "Text", "Convert selected", ...
    "FontWeight", "bold", "ButtonPushedFcn", @(~,~) obj.onRunConvert());
obj.ConvRunButton.Layout.Column = 1;
obj.ConvCancelButton = uibutton(bg, "Text", "Cancel", "Enable", "off", ...
    "Tooltip", "Stop at the next step boundary (between files / processing stages).", ...
    "ButtonPushedFcn", @(~,~) obj.onCancelConvert());
obj.ConvCancelButton.Layout.Column = 2;
obj.ConvRefreshButton = uibutton(bg, "Text", "Refresh list", ...
    "Tooltip", "Re-read the ticked datasets and check which outputs already exist.", ...
    "ButtonPushedFcn", @(~,~) obj.refreshConvertTargets());
obj.ConvRefreshButton.Layout.Column = 4;

l = uilabel(rg, "Text", "Overall:"); l.Layout.Row = 4; l.Layout.Column = 1;
obj.ConvOverallBar = makeBar(rg, 4);
obj.ConvOverallText = uilabel(rg, "Text", "", "FontColor", [0.3 0.3 0.3]);
obj.ConvOverallText.Layout.Row = 4; obj.ConvOverallText.Layout.Column = 3;

l = uilabel(rg, "Text", "Current:"); l.Layout.Row = 5; l.Layout.Column = 1;
obj.ConvStepBar = makeBar(rg, 5);
obj.ConvStepText = uilabel(rg, "Text", "", "FontColor", [0.3 0.3 0.3]);
obj.ConvStepText.Layout.Row = 5; obj.ConvStepText.Layout.Column = 3;

obj.ConvStepLabel = uilabel(rg, "Text", "Idle.", "FontColor", [0.4 0.4 0.4]);
obj.ConvStepLabel.Layout.Row = 6; obj.ConvStepLabel.Layout.Column = [1 3];

l = uilabel(rg, "Text", "Log", "FontWeight", "bold");
l.Layout.Row = 7; l.Layout.Column = [1 3];

obj.ConvLogArea = uitextarea(rg, "Editable", "off");
obj.ConvLogArea.Layout.Row = 8; obj.ConvLogArea.Layout.Column = [1 3];

obj.syncConvertEnableStates();
end


function bar = makeBar(parent, row)
%makeBar  Simple horizontal progress bar in column 2 of PARENT at ROW.
%   Returns the inner 1x2 grid; setConvertBar sets the fraction by weighting
%   its two columns (filled panel | empty), so the bar tracks resizes.
bgc = [0.92 0.92 0.94];
p = uipanel(parent, "BorderType", "line", "BackgroundColor", bgc);
p.Layout.Row = row; p.Layout.Column = 2;
bar = uigridlayout(p, [1 2], "Padding", [0 0 0 0], "ColumnSpacing", 0, ...
    "RowSpacing", 0, "BackgroundColor", bgc);
bar.RowHeight   = {'1x'};
bar.ColumnWidth = {0, '1x'};
fill = uipanel(bar, "BorderType", "none", "BackgroundColor", [0.25 0.55 0.85]);
fill.Layout.Row = 1; fill.Layout.Column = 1;
end


function f = numField(parent, value, tip, cb)
%numField  Strictly positive numeric edit field.
f = uieditfield(parent, "numeric", "Value", value, "Limits", [0 Inf], ...
    "LowerLimitInclusive", "off", "ValueDisplayFormat", "%.10g", ...
    "Tooltip", tip, "ValueChangedFcn", cb);
end


function l = lab(parent, txt, row)
%lab  Create a column-1 label at the given grid row.
l = uilabel(parent, "Text", txt);
l.Layout.Row = row;
l.Layout.Column = 1;
end


function sep(parent, txt, row)
%sep  Create a bold full-width section header at the given grid row.
l = uilabel(parent, "Text", txt, "FontWeight", "bold");
l.Layout.Row = row;
l.Layout.Column = [1 5];
end
