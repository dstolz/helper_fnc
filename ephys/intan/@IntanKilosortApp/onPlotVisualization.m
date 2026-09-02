function onPlotVisualization(obj)
%onPlotVisualization  Stream the selected data, preprocess it, and cache it.
%   Display-only: data is read fresh, file-by-file, and any filtering/CAR/detrend
%   is applied to the in-memory copy only. The recording on disk is never touched.
%
%   Memory strategy
%   ---------------
%   Rather than loading the whole recording with IntanDataset.readData (which
%   concatenates every file into one big double matrix and then makes several
%   more full-array copies while preprocessing - the source of out-of-memory
%   errors on long recordings), this:
%
%     1. Streams ONE chunk into RAM at a time (a whole *.rhd file for the
%        traditional format, or a bounded sample window over the flat .dat for
%        the split formats - the same one-chunk-in-memory invariant toBin relies
%        on), so peak usage never scales with the whole recording length.
%     2. Works in single precision (half the bytes of double).
%     3. Picks a memory budget for the cached matrix and, when the full-
%        resolution span would exceed it, peak-decimates on load: each bin keeps
%        the most extreme sample per channel (preserving spike amplitude) and the
%        cached sample rate is reduced to match. This bounds RAM regardless of
%        recording length while keeping the whole span navigable.
%
%   The cached matrix is handed to obj.Viewer (a plotting/@MultiChannelViewer),
%   which owns all navigation from there: pan/zoom/scale entirely from the
%   cached copy without ever re-reading or re-filtering. When the data was
%   decimated to fit memory, the effective (reduced) Fs is passed to the
%   viewer instead; true recording time is preserved everywhere because
%   tt = sampleIndex / Fs.

idx = obj.SelectedDatasetIdx;
if idx < 1 || isempty(obj.Project) || idx > obj.Project.NumDatasets
    uialert(obj.Fig, "Scan, then choose a dataset from the Dataset menu.", "Visualize");
    return
end
d = obj.Project.Datasets(idx);

% Parse channel list (1-based)
chans = parseChannels(obj.VizChannelsField.Value);
if isempty(chans)
    uialert(obj.Fig, "Enter channels, e.g. 1:16 or 1 3 5.", "Visualize");
    return
end

% Ensure per-file header metadata (sample counts / Fs) is available; it lets us
% size the cache and choose the decimation factor up front, before reading data.
if isempty(d.PerFile) || ~isfield(d.PerFile, 'numAmplifierSamples') || isnan(d.Fs)
    d.refreshMetadata();
end

% Resolve the streaming plan. For traditional recordings the file dropdown can
% pick one *.rhd file (or "(all)"); the split formats are a single data set, so
% the selection is ignored and the whole recording is streamed in bounded
% sample-window chunks. Either way readChunkUV yields one [m x nChanAll] chunk.
fileSel = string(obj.VizFileDropDown.Value);
if d.RecordingFormat == "traditional" && fileSel ~= "(all)" && fileSel ~= ""
    planFiles = fileSel;
else
    planFiles = string.empty(1,0);
end
plan = d.streamPlan(Files=planFiles);
if isempty(plan)
    uialert(obj.Fig, "No Intan data to read for this dataset.", "Visualize");
    return
end

% Per-chunk amplifier sample counts -> total samples (for cache sizing/decimation).
chunkSamples = [plan.nSamples];
chunkSamples(~isfinite(chunkSamples)) = 0;
Ntot = sum(chunkSamples);
nCh  = numel(chans);
if Ntot <= 0
    uialert(obj.Fig, "Selected data contains no amplifier samples.", "Visualize");
    return
end

% Gather display-only preprocessing parameters once.
pp = struct();
pp.detrend = logical(obj.VizDetrendCheckBox.Value);
pp.ref     = string(obj.VizRefDropDown.Value);
pp.order   = obj.VizOrderField.Value;
hp = parseCutoff(obj.VizHighpassField.Value);
lp = parseCutoff(obj.VizLowpassField.Value);
if ~isempty(hp) && ~isempty(lp)
    pp.type = "bandpass"; pp.cutoff = [hp lp];
elseif ~isempty(lp)
    pp.type = "lowpass";  pp.cutoff = lp;
elseif ~isempty(hp)
    pp.type = "highpass"; pp.cutoff = hp;
else
    pp.type = ""; pp.cutoff = [];
end

% Decide the decimation factor from a memory budget (single precision).
budget = obj.VizMemoryBudget;
if budget <= 0; budget = autoMemoryBudget(); end
decim = max(1, ceil((Ntot * nCh * 4) / budget));   % 4 bytes/single element

obj.VizPlotButton.Enable = "off";
cleanup = onCleanup(@() set(obj.VizPlotButton, "Enable", "on"));
dlg = uiprogressdlg(obj.Fig, "Title", "Loading", ...
    "Message", "Reading data...", "Value", 0);

try
    FsTrue = d.Fs;
    nChunks = numel(plan);

    % Preallocate the cache at the decimated length (capacity from header
    % counts; trimmed to the actual filled length afterwards). No concatenation.
    outLen = sum(floor(chunkSamples / decim));
    outLen = max(outLen, 1);
    X = zeros(outLen, nCh, 'single');

    row = 0;                 % rows filled so far
    for i = 1:nChunks
        if isvalid(dlg)
            dlg.Value   = (i - 1) / nChunks;
            dlg.Message = sprintf("Reading & preprocessing chunk %d/%d: %s", ...
                i, nChunks, plan(i).name);
        end

        Xi = d.readChunkUV(plan(i));        % [m x nChanAll], microvolts (double)
        if isempty(Xi)
            continue
        end
        if max(chans) > size(Xi, 2)
            error('IntanKilosortApp:Visualize:BadChannels', ...
                'Channel %d requested but %s has %d amplifier channels.', ...
                max(chans), plan(i).name, size(Xi, 2));
        end
        Xi = Xi(:, chans);                  % keep only requested channels

        % Preprocess this file's chunk (single precision); filter per-file
        % (independent edges, matching toBin's default streaming behavior).
        Xi = preprocessChunk(d, Xi, pp, FsTrue);

        if decim > 1
            Xi = peakDecimate(Xi, decim);   % [floor(m/decim) x nCh] single
        end

        m = size(Xi, 1);
        if m == 0; continue; end
        if row + m > size(X, 1)             % grow defensively (partial blocks)
            X(row + m, nCh) = single(0);
        end
        X(row + (1:m), :) = Xi;
        row = row + m;
    end

    X = X(1:row, :);                        % trim unused capacity
    if isempty(X)
        error('IntanKilosortApp:Visualize:Empty', 'No samples were read.');
    end

    Fs    = FsTrue / decim;                 % effective (cached) sample rate
    nSamp = size(X, 1);

    if isvalid(dlg); close(dlg); end

    % Time offset of this window within the whole recording (s), recording-
    % relative (matching toBin) so artifacts marked here map correctly. Uses the
    % TRUE sample rate. "(all)" -> 0; a single file -> duration of files before it.
    tOffset = 0;
    if d.RecordingFormat == "traditional" && fileSel ~= "(all)" && fileSel ~= "" ...
            && ~isempty(d.Files)
        fi = find(d.Files == fileSel, 1);
        if ~isempty(fi) && fi > 1 && ~isempty(d.PerFile) ...
                && isfield(d.PerFile, 'numAmplifierSamples')
            tOffset = sum([d.PerFile(1:fi-1).numAmplifierSamples]) / FsTrue;
        end
    end

    % App-specific bookkeeping the generic MultiChannelViewer doesn't need to
    % know about: automatically detected artifacts for this window (display
    % overlay only; uses the same detector as the Artifacts tab/.bin write,
    % window-relative seconds) and the recording-relative time offset. Drawn
    % by drawVizArtifacts, which the Viewer calls after every render via
    % PostRenderFcn.
    obj.VizDetectedIntervals = computeDetectedIntervals(d, X, Fs);
    obj.VizTimeOffset = tOffset;
    obj.VizDatasetIndex = idx;
    obj.VizChannels = chans;

    chanNames = compose("ch%d", chans(:).');
    tWin  = min(obj.VizDurField.Value, nSamp / Fs);
    tLeft = min(obj.VizStartField.Value, max(0, nSamp / Fs - tWin));

    if isempty(obj.Viewer) || ~isvalid(obj.Viewer)
        % First plot: construct the viewer once, parented to the Visualize
        % axes. It self-attaches its own scroll/drag/keyboard callbacks; the
        % app then re-asserts WindowButtonDown/UpFcn so plain-left artifact
        % marking still takes precedence over the viewer's pan gesture.
        obj.Viewer = MultiChannelViewer(X, Fs, Parent=obj.VizAxes, ...
            ChannelNames=chanNames, Units="uV", ...
            Mode=string(obj.VizModeDropDown.Value), ...
            VisibleChannels=min(16, nCh), ...
            TraceSpacing=obj.VizSpacingField.Value, ...
            Colormap=string(obj.VizColormapDropDown.Value), ...
            ActiveFcn=@() obj.vizActive(), ...
            PostRenderFcn=@() obj.drawVizArtifacts());
        obj.Fig.WindowButtonDownFcn = @(~, ~) obj.onVizButtonDown();
        obj.Fig.WindowButtonUpFcn   = @(~, ~) obj.onVizButtonUp();
    else
        % Subsequent plots: reuse the same instance (and its callback/KeyMap
        % wiring) with the newly streamed data.
        obj.Viewer.loadData(X, Fs, ChannelNames=chanNames, Units="uV");
    end

    % Apply the Start/Window fields and reset gain/offset fresh on every plot,
    % matching the previous behavior.
    obj.Viewer.TimeWindowDuration = tWin;
    obj.Viewer.TimeWindowStart = tLeft;
    obj.Viewer.AmpGain = 1;
    obj.Viewer.YOffset = 0;
    obj.applyVizChannelOrder();   % also renders, reflecting the settings just above
    obj.applyVizChannelColor();   % also renders, reflecting the settings just above

    obj.updateVizArtStatus();

    if decim > 1
        obj.VizStatusLabel.Text = sprintf( ...
            ['Cached %d ch x %d samples (%.2f s). Decimated %dx to fit memory ' ...
             '(eff. Fs %.0f Hz) - zoom shows reduced detail.'], ...
            nCh, nSamp, nSamp / Fs, decim, Fs);
    else
        obj.VizStatusLabel.Text = sprintf( ...
            "Cached %d ch x %d samples (%.2f s). Navigate with the mouse.", ...
            nCh, nSamp, nSamp / Fs);
    end

    nDet = size(obj.VizDetectedIntervals, 1);
    obj.setStatus(sprintf("Plotted %s: %d ch, %.2f s (%d artifact interval(s) detected).", ...
        d.Name, nCh, nSamp / Fs, nDet), ...
        "Scroll/drag to navigate; toggle 'Mark Artifacts' to add manual periods.");
catch ME
    if isvalid(dlg); close(dlg); end
    uialert(obj.Fig, ME.message, "Visualize failed");
    obj.setStatus("Visualize failed: " + string(ME.message));
end
end


function iv = computeDetectedIntervals(d, X, Fs)
%computeDetectedIntervals  Run the automatic artifact detector on the loaded
%   window and return its intervals [k x 2] in window-relative seconds. Uses the
%   dataset's current ArtifactConfig (the same settings the Artifacts tab and
%   the .bin write use). Returns 0x2 on any failure or when nothing is flagged.
iv = zeros(0, 2); %#ok<PREALL>  default when detection fails or flags nothing
try
    cfg = IntanDataset.normalizeArtifactConfig(d.ArtifactConfig);
    [~, iv] = d.detectArtifacts(double(X), Method=cfg.Method, ...
        Threshold=cfg.Threshold, RmsWindowMs=cfg.RmsWindowMs, ...
        MinChannels=cfg.MinChannels, MergeGapMs=cfg.MergeGapMs, ...
        PadMs=cfg.PadMs, Fs=Fs);
catch
    iv = zeros(0, 2);
end
end


function Xc = preprocessChunk(d, Xc, pp, Fs)
%preprocessChunk  Display-only preprocessing of one file's [m x nCh] chunk.
%   Returns single precision. Order matches the previous whole-span path:
%   detrend -> CAR/CMR -> optional high/low/band-pass filter.
Xc = single(Xc);
if pp.detrend
    Xc = Xc - mean(Xc, 1);
end
if size(Xc, 2) > 1
    switch pp.ref
        case "car"
            Xc = Xc - mean(Xc, 2);
        case "cmr"
            Xc = Xc - median(Xc, 2);
    end
end
if pp.type ~= ""
    % filterContinuous casts to double internally; bounded here to one file.
    Xc = single(d.filterContinuous(Xc, Type=pp.type, Cutoff=pp.cutoff, ...
        Order=pp.order, Fs=Fs));
end
end


function Y = peakDecimate(Xc, decim)
%peakDecimate  Reduce [m x nCh] by keeping the most extreme sample per bin.
%   Each output sample is, per channel, the bin value with the largest absolute
%   magnitude (signed). This preserves spike amplitude in the overview far better
%   than averaging, while keeping a uniform reduced sample rate (one row per bin)
%   so the cached array stays [N x nCh] and downstream code is unchanged.
[m, nCh] = size(Xc);
nb = floor(m / decim);
if nb < 1
    Y = Xc;     % chunk shorter than one bin; keep as-is
    return
end
use = nb * decim;
R   = reshape(Xc(1:use, :), decim, nb, nCh);
mx  = max(R, [], 1);                 % [1 x nb x nCh]
mn  = min(R, [], 1);
keepMax = abs(mx) >= abs(mn);
Y = reshape(mx .* keepMax + mn .* ~keepMax, nb, nCh);
end


function b = autoMemoryBudget()
%autoMemoryBudget  Bytes allowed for the cached single-precision matrix.
%   Defaults to ~1 GB, raised toward a third of currently-available array
%   memory when MATLAB can report it (PC only), and floored so very small
%   machines still get a usable cache.
b = 1.0e9;
try
    m = memory;   % PC only; errors elsewhere
    b = min(2.0e9, 0.33 * m.MemAvailableAllArrays);
catch
end
b = max(b, 2.5e8);
end


function ch = parseChannels(s)
%parseChannels  Parse "1:16" / "1 3 5" / "1,3,5" into a row vector of indices.
s = strrep(char(string(s)), ',', ' ');
ch = str2num(s); %#ok<ST2NM>  % str2num supports colon ranges like 1:16
if isempty(ch); return; end
ch = round(ch(:).');
ch = ch(ch >= 1);
end


function c = parseCutoff(s)
%parseCutoff  First numeric value in a text field ([] if blank/non-numeric).
c = [];
v = sscanf(char(string(s)), '%g');
if ~isempty(v); c = v(1); end
end
