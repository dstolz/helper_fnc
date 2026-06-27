function onDetectArtifacts(obj)
%onDetectArtifacts  Run the artifact detector over a dataset and show the summary.
%   Pushes the current detection settings onto every scanned dataset, then
%   streams the selected dataset one *.rhd file at a time
%   (IntanDataset.analyzeArtifacts) and fills the per-channel table and summary
%   label with the number of samples flagged per channel and the percent of the
%   recording that would be blanked. Read-only: nothing is written to disk.
%
%   See also IntanDataset.analyzeArtifacts, buildArtifactsTab.

d = obj.currentArtifactDataset();
if isempty(d)
    uialert(obj.Fig, "Scan, then choose a dataset to analyze.", "Artifacts");
    return
end

% Make sure Fs / per-file counts are known (needed to convert the RMS window
% from ms to samples and to report duration).
if isnan(d.Fs) || isempty(d.PerFile) || ~isfield(d.PerFile, 'numAmplifierSamples')
    d.refreshMetadata();
end

% Persist the current settings onto every dataset so the batch write matches.
obj.applyArtifactConfigToProject();

obj.ArtDetectButton.Enable = "off";
cleanup = onCleanup(@() set(obj.ArtDetectButton, "Enable", "on"));
dlg = uiprogressdlg(obj.Fig, "Title", "Detecting artifacts", ...
    "Message", "Reading data...", "Value", 0, "Cancelable", "off");

try
    useFilter = logical(obj.ArtFilterCheckBox.Value);
    hp = obj.ArtHighpassField.Value;

    progress = @(i, n, name) updateProgress(dlg, i, n, name);
    summary = d.analyzeArtifacts( ...
        Filter=useFilter, FilterType="highpass", FilterCutoff=max(hp, eps), ...
        ProgressFcn=progress);

    if isvalid(dlg); close(dlg); end

    fillArtifactTable(obj, summary);
    obj.ArtSummaryLabel.Text = summaryText(summary, ...
        logical(obj.ArtEnableCheckBox.Value));
    obj.ArtStatusLabel.Text = sprintf("Analyzed %s (%d file(s)).", ...
        d.Name, numel(summary.files));
catch ME
    if isvalid(dlg); close(dlg); end
    uialert(obj.Fig, ME.message, "Detect failed");
end
end


function updateProgress(dlg, i, n, name)
if ~isvalid(dlg); return; end
dlg.Value   = max(0, min(1, (i - 1) / max(n, 1)));
dlg.Message = sprintf("Scanning file %d/%d: %s", i, n, name);
end


function fillArtifactTable(obj, s)
%fillArtifactTable  Per-channel counts -> the Artifacts table.
nCh = s.nChan;
if nCh == 0
    obj.ArtChannelTable.Data = cell(0, 4);
    return
end
ch    = (1:nCh).';
names = s.channelNames;
if numel(names) ~= nCh
    names = "ch" + string(ch);
end
C = cell(nCh, 4);
for k = 1:nCh
    C{k, 1} = ch(k);
    C{k, 2} = char(names(k));
    C{k, 3} = s.channelCounts(k);
    C{k, 4} = sprintf('%.3f', s.channelPct(k));
end
obj.ArtChannelTable.Data = C;
end


function t = summaryText(s, enabled)
%summaryText  Aggregate artifact statistics as a monospaced block.
if s.nChan > 0
    [pkPct, pkCh] = max(s.channelPct);
else
    pkPct = 0; pkCh = 0;
end
if strcmp(char(s.method), 'rms') && ~isnan(s.rmsWindowMs)
    winStr = sprintf('%.2f ms', s.rmsWindowMs);
else
    winStr = 'n/a';
end
lines = {
    sprintf('Method        : %s   threshold %g', char(s.method), s.threshold)
    sprintf('RMS window    : %s', winStr)
    sprintf('Stitch gap    : %g ms     Pad: %g ms     MinCh: %d', ...
        s.mergeGapMs, s.padMs, s.minChannels)
    sprintf('Duration      : %.2f s  (%d samples, fs=%g, %d ch)', ...
        s.durationSec, s.nSamples, s.fs, s.nChan)
    ''
    sprintf('Blanked       : %d samples = %.3f%% of duration', s.nBlanked, s.pctDuration)
    sprintf('Intervals     : %d', s.nIntervals)
    sprintf('Worst channel : %d (%.3f%% flagged)', pkCh, pkPct)
    ''
    sprintf('On .bin write : %s', ternary(enabled, ...
        'BLANKED (every channel zeroed at flagged samples)', ...
        'NOT blanked (tick "Blank artifacts in .bin" on the Kilosort tab to enable)'))
    };
t = strjoin(lines, newline);
end


function out = ternary(c, a, b)
if c; out = a; else; out = b; end
end
