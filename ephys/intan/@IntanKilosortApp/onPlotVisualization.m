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
%     1. Streams ONE *.rhd file into RAM at a time (the same one-file-in-memory
%        invariant toBin relies on), so peak usage never scales with the whole
%        recording length.
%     2. Works in single precision (half the bytes of double).
%     3. Picks a memory budget for the cached matrix and, when the full-
%        resolution span would exceed it, peak-decimates on load: each bin keeps
%        the most extreme sample per channel (preserving spike amplitude) and the
%        cached sample rate is reduced to match. This bounds RAM regardless of
%        recording length while keeping the whole span navigable.
%
%   The cache (obj.VizData) keeps the same fields as before, so renderViz and the
%   mouse/key handlers are unchanged: navigation still pans/zooms/scales entirely
%   from the cached copy without ever re-reading or re-filtering. When the data
%   was decimated to fit memory, VizData.Fs is the (reduced) effective rate; true
%   recording time is preserved everywhere because tt = sampleIndex / Fs.

idx = obj.VizDatasetDropDown.Value;
if isempty(idx) || ~isnumeric(idx) || isempty(obj.Project) || idx > obj.Project.NumDatasets
    uialert(obj.Fig, "Scan, then choose a dataset to visualize.", "Visualize");
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

% Resolve which file(s) to read (chronological order preserved).
fileSel = string(obj.VizFileDropDown.Value);
if fileSel == "(all)" || fileSel == ""
    fileList = d.Files;
else
    fileList = fileSel;
end
if isempty(fileList)
    uialert(obj.Fig, "No *.rhd files to read for this dataset.", "Visualize");
    return
end

% Per-file amplifier sample counts (for the selected files) -> total samples.
fileSamples = perFileSampleCounts(d, fileList);
Ntot = sum(fileSamples);
nCh  = numel(chans);
if Ntot <= 0
    uialert(obj.Fig, "Selected file(s) contain no amplifier samples.", "Visualize");
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
    nFiles = numel(fileList);

    % Preallocate the cache at the decimated length (capacity from header
    % counts; trimmed to the actual filled length afterwards). No concatenation.
    outLen = sum(floor(fileSamples / decim));
    outLen = max(outLen, 1);
    X = zeros(outLen, nCh, 'single');

    row = 0;                 % rows filled so far
    climSamp = cell(1, nFiles);   % small per-file subsample for the colour limit
    for i = 1:nFiles
        if isvalid(dlg)
            dlg.Value   = (i - 1) / nFiles;
            dlg.Message = sprintf("Reading & preprocessing file %d/%d: %s", ...
                i, nFiles, fileList(i));
        end

        ffn = fullfile(d.Folder, fileList(i));
        S = read_Intan_RHD2000_file_modified(ffn, Verbosity="silent");
        if ~isfield(S, 'amplifier_data') || isempty(S.amplifier_data)
            continue
        end
        Xi = S.amplifier_data.';            % [m x nChanAll], microvolts (double)
        clear S                              % release the rest of the file
        if max(chans) > size(Xi, 2)
            error('IntanKilosortApp:Visualize:BadChannels', ...
                'Channel %d requested but %s has %d amplifier channels.', ...
                max(chans), fileList(i), size(Xi, 2));
        end
        Xi = Xi(:, chans);                  % keep only requested channels

        % Preprocess this file's chunk (single precision); filter per-file
        % (independent edges, matching toBin's default streaming behaviour).
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

        % Keep a thin subsample for a robust amplitude scale without ever
        % materialising the full matrix again.
        step = max(1, floor(m / 2000));
        climSamp{i} = Xi(1:step:end, :);
    end

    X = X(1:row, :);                        % trim unused capacity
    if isempty(X)
        error('IntanKilosortApp:Visualize:Empty', 'No samples were read.');
    end

    Fs    = FsTrue / decim;                 % effective (cached) sample rate
    nSamp = size(X, 1);

    % Robust per-recording amplitude scale (~5 sigma via the MAD) from the
    % subsample; guarded against all-zero/flat input.
    cs    = cat(1, climSamp{:});
    cs    = cs(:);
    med   = median(cs);
    clim0 = 5 * median(abs(cs - med));
    if ~isfinite(clim0) || clim0 <= 0
        clim0 = max(1, max(abs(cs)));
    end
    if ~isfinite(clim0) || clim0 <= 0; clim0 = 1; end

    if isvalid(dlg); close(dlg); end

    % Time offset of this window within the whole recording (s), recording-
    % relative (matching toBin) so artifacts marked here map correctly. Uses the
    % TRUE sample rate. "(all)" -> 0; a single file -> duration of files before it.
    tOffset = 0;
    if fileSel ~= "(all)" && fileSel ~= "" && ~isempty(d.Files)
        fi = find(d.Files == fileSel, 1);
        if ~isempty(fi) && fi > 1 && ~isempty(d.PerFile) ...
                && isfield(d.PerFile, 'numAmplifierSamples')
            tOffset = sum([d.PerFile(1:fi-1).numAmplifierSamples]) / FsTrue;
        end
    end

    % Cache everything needed to navigate without re-reading (same fields as
    % before; Fs is the effective rate when decimated).
    obj.VizData = struct( ...
        'X', X, 'Fs', Fs, 'nSamp', nSamp, 'nCh', nCh, ...
        'chans', chans(:).', 'name', d.Name, 'clim0', clim0, ...
        'dsIndex', idx, 'tOffset', tOffset);

    % Initial viewport from the Start/Window fields.
    tWin  = min(obj.VizDurField.Value, nSamp / Fs);
    tLeft = min(obj.VizStartField.Value, max(0, nSamp / Fs - tWin));
    obj.VizView = struct( ...
        'mode', string(obj.VizModeDropDown.Value), ...
        'tLeft', tLeft, 'tWin', tWin, 'ampGain', 1, 'yOffset', 0);

    % Force a clean rebuild of the graphics objects for the new data.
    obj.VizDrawnMode = "";
    obj.VizLines = [];
    obj.VizImage = [];
    if ~isempty(obj.VizColorbar) && isvalid(obj.VizColorbar)
        delete(obj.VizColorbar);
    end
    obj.VizColorbar = [];

    obj.renderViz();
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
catch ME
    if isvalid(dlg); close(dlg); end
    uialert(obj.Fig, ME.message, "Visualize failed");
end
end


function n = perFileSampleCounts(d, fileList)
%perFileSampleCounts  Amplifier sample count for each name in fileList.
%   Looked up from the parsed PerFile header summary (no data read). Files with
%   no header entry contribute 0 (they are skipped while streaming too).
n = zeros(1, numel(fileList));
if isempty(d.PerFile) || ~isfield(d.PerFile, 'name'); return; end
pfNames = string({d.PerFile.name});
for k = 1:numel(fileList)
    j = find(pfNames == fileList(k), 1);
    if ~isempty(j)
        n(k) = d.PerFile(j).numAmplifierSamples;
    end
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
