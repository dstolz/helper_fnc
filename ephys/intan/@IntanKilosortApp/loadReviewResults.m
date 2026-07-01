function loadReviewResults(obj)
%loadReviewResults  Parse a Kilosort4 results folder and populate the Review tab.
%   Reads the phy/Kilosort4 .npy + .tsv outputs once, derives per-unit summary
%   statistics (spike counts, firing rates, peak channel, shank, amplitude,
%   contamination, mean waveform), caches them in obj.ReviewData, fills the
%   summary label and units table, and draws the plots. Selecting a unit later
%   only re-renders from the cache (see renderReviewPlots).
%
%   .npy files are read with a small built-in reader (readNPY, below); no
%   external toolbox is required. Numeric arrays are assumed little-endian,
%   which is what Kilosort4 writes on x86.

folder = strtrim(obj.ReviewFolderField.Value);
if isempty(folder)
    uialert(obj.Fig, "Select a Kilosort4 results folder first.", "Review");
    return
end
% Tolerate pointing at the dataset folder or the kilosort4 run folder instead of
% the exact results dir. The SpikeInterface engine nests the phy output under
% kilosort4/si/sorter_output; the legacy engine writes it into kilosort4/
% directly. Probe a few candidate subpaths for params.py.
if ~isfile(fullfile(folder, 'params.py'))
    candidates = { ...
        fullfile(folder, 'kilosort4', 'si', 'sorter_output'), ...
        fullfile(folder, 'si', 'sorter_output'), ...
        fullfile(folder, 'sorter_output'), ...
        fullfile(folder, 'kilosort4') };
    for ci = 1:numel(candidates)
        if isfile(fullfile(candidates{ci}, 'params.py'))
            folder = candidates{ci};
            obj.ReviewFolderField.Value = folder;
            break
        end
    end
end
if ~isfolder(folder)
    uialert(obj.Fig, sprintf("Not a folder:\n%s", folder), "Review");
    return
end
need = fullfile(folder, 'spike_clusters.npy');
if ~isfile(need)
    uialert(obj.Fig, sprintf(['No Kilosort4 output here (missing spike_clusters.npy):' ...
        newline '%s'], folder), "Review");
    return
end

dlg = uiprogressdlg(obj.Fig, "Title", "Review", ...
    "Message", "Reading Kilosort4 output...", "Indeterminate", "on");
drawnow;
cleanup = onCleanup(@() closeIfValid(dlg));

try
    fs = readSampleRate(folder);

    spikeClu = double(readNPY(fullfile(folder, 'spike_clusters.npy')));
    spikeSamp = double(readNPY(fullfile(folder, 'spike_times.npy')));
    spikeSec  = spikeSamp / fs;
    spikeAmp  = double(readNPY(fullfile(folder, 'amplitudes.npy')));
    templates = double(readNPY(fullfile(folder, 'templates.npy')));   % [nT nS nC]
    spikeTmpl = readOptionalNPY(fullfile(folder, 'spike_templates.npy'), spikeClu);

    nT   = size(templates, 1);
    nS   = size(templates, 2);
    nCh  = size(templates, 3);

    chanShanks = readOptionalNPY(fullfile(folder, 'channel_shanks.npy'), zeros(nCh, 1));
    chanShanks = double(chanShanks(:));
    if numel(chanShanks) < nCh; chanShanks(end+1:nCh) = 0; end
    chanPos = readOptionalNPY(fullfile(folder, 'channel_positions.npy'), []);
    Winv = readOptionalNPY(fullfile(folder, 'whitening_mat_inv.npy'), []);
    canUnwhiten = ~isempty(Winv) && size(Winv, 1) == nCh && size(Winv, 2) == nCh;

    durSec = max(spikeSec, [], 'omitnan');
    if isempty(durSec) || durSec <= 0; durSec = NaN; end

    % --- per-unit aggregation over the clusters actually present in spikes ---
    clusterID = unique(spikeClu);
    clusterID = clusterID(:);
    U = numel(clusterID);

    % phy/KS tsv side tables (aligned to clusterID order).
    labels = lookupByID(folder, 'cluster_KSLabel.tsv', clusterID, true);
    if all(labels == "")
        labels = lookupByID(folder, 'cluster_group.tsv', clusterID, true);
    end
    labels(labels == "") = "unsorted";
    ampTsv    = lookupByID(folder, 'cluster_Amplitude.tsv', clusterID, false);
    contamTsv = lookupByID(folder, 'cluster_ContamPct.tsv', clusterID, false);

    [~, spikeUnitIdx] = ismember(spikeClu, clusterID);   % spike -> row in clusterID

    nSpikes   = accumarray(spikeUnitIdx, 1, [U 1]);
    firingRate = nSpikes / durSec;

    peakChan = zeros(U, 1);
    shank    = zeros(U, 1);
    ampUnit  = zeros(U, 1);
    tms      = (0:nS-1) / fs * 1000;   % waveform time axis (ms)
    wfPeak   = zeros(nS, U);
    wfFull   = zeros(nS, nCh, U);

    for u = 1:U
        sel = spikeUnitIdx == u;
        % Representative template for this cluster (robust to KS reindexing).
        tIdx = mode(spikeTmpl(sel)) + 1;
        if ~(tIdx >= 1 && tIdx <= nT)
            tIdx = min(max(clusterID(u) + 1, 1), nT);
        end
        wf = squeeze(templates(tIdx, :, :));   % [nS x nC]
        if canUnwhiten; wf = wf * Winv; end
        medAmp = median(spikeAmp(sel), 'omitnan');
        if ~isfinite(medAmp) || medAmp == 0; medAmp = 1; end
        wf = wf * medAmp;                       % scale to this unit's amplitude

        wfFull(:, :, u) = wf;
        p2p = max(wf, [], 1) - min(wf, [], 1);
        [~, pk] = max(p2p);
        peakChan(u) = pk;
        shank(u) = chanShanks(min(pk, numel(chanShanks)));
        wfPeak(:, u) = wf(:, pk);
        if isfinite(ampTsv(u)); ampUnit(u) = ampTsv(u); else; ampUnit(u) = medAmp; end
    end

    R = struct();
    R.folder   = folder;
    R.fs       = fs;
    R.durSec   = durSec;
    R.nChan    = nCh;
    R.chanShanks = chanShanks;
    R.chanPos  = chanPos;
    R.shankIDs = unique(chanShanks);
    R.nShank   = numel(R.shankIDs);
    R.clusterID = clusterID;
    R.label    = labels;
    R.nSpikes  = nSpikes;
    R.firingRate = firingRate;
    R.peakChan = peakChan;
    R.shank    = shank;
    R.ampUnit  = ampUnit;
    R.contam   = contamTsv;
    R.tms      = tms;
    R.wfPeak   = wfPeak;
    R.wfFull   = wfFull;
    R.spikeSec = spikeSec;
    R.spikeAmp = spikeAmp;
    R.spikeUnitIdx = spikeUnitIdx;
    R.nGood    = sum(labels == "good");
    R.nMua     = sum(labels == "mua");

    obj.ReviewData = R;
    obj.ReviewSelectedUnit = 0;

    fillSummary(obj, R);
    fillUnitsTable(obj, R);
    obj.renderReviewPlots();

    obj.setStatus(sprintf("Loaded results: %d unit(s) (good %d, mua %d).", ...
        numel(R.clusterID), R.nGood, R.nMua), ...
        "Click a unit row to focus its waveform and stats.");
catch ME
    closeIfValid(dlg);
    uialert(obj.Fig, sprintf("Failed to load results:\n%s", ME.message), "Review");
    rethrow(ME);
end
end


%% ---------------------------------------------------------------------------
function fillSummary(obj, R)
%fillSummary  Compose the aggregate-stats text block.
U = numel(R.clusterID);
lines = strings(0, 1);
[~, fname] = fileparts(fileparts(R.folder));
lines(end+1) = "Dataset : " + string(fname);
lines(end+1) = sprintf("Fs      : %g kHz", R.fs / 1000);
if isfinite(R.durSec)
    lines(end+1) = sprintf("Duration: %s (%.1f s)", durStr(R.durSec), R.durSec);
end
lines(end+1) = sprintf("Channels: %d   Shanks: %d", R.nChan, R.nShank);
lines(end+1) = "";
lines(end+1) = sprintf("Total units : %d", U);
lines(end+1) = sprintf("  good=%d  mua=%d  other=%d", R.nGood, R.nMua, U - R.nGood - R.nMua);
lines(end+1) = sprintf("Total spikes: %s", commaSep(sum(R.nSpikes)));
if isfinite(R.durSec)
    lines(end+1) = sprintf("Mean rate   : %.1f Hz/unit", mean(R.firingRate, 'omitnan'));
end
lines(end+1) = "";
lines(end+1) = "Units per shank:";
for s = 1:R.nShank
    sid = R.shankIDs(s);
    m = R.shank == sid;
    lines(end+1) = sprintf("  shank %g : %d  (good %d)", sid, sum(m), ...
        sum(m & R.label == "good"));   %#ok<AGROW>
end
obj.ReviewSummaryLabel.Text = lines;
end


function fillUnitsTable(obj, R)
%fillUnitsTable  Fill the per-unit table (one row per cluster).
U = numel(R.clusterID);
C = cell(U, 8);
for u = 1:U
    C{u, 1} = R.clusterID(u);
    C{u, 2} = char(R.label(u));
    C{u, 3} = R.shank(u);
    C{u, 4} = R.peakChan(u);
    C{u, 5} = R.nSpikes(u);
    C{u, 6} = round(R.firingRate(u), 2);
    C{u, 7} = round(R.ampUnit(u), 1);
    C{u, 8} = round(R.contam(u), 1);
end
obj.ReviewUnitsTable.Data = C;
obj.ReviewUnitsTable.Selection = [];
end


%% --- small helpers ---------------------------------------------------------
function fs = readSampleRate(folder)
%readSampleRate  Read sample_rate from params.py, falling back to settings.json.
fs = 30000;
pp = fullfile(folder, 'params.py');
if isfile(pp)
    txt = fileread(pp);
    tok = regexp(txt, 'sample_rate\s*=\s*([\d.eE+]+)', 'tokens', 'once');
    if ~isempty(tok); fs = str2double(tok{1}); return; end
end
sj = fullfile(folder, 'settings.json');
if isfile(sj)
    try
        s = jsondecode(fileread(sj));
        if isfield(s, 'fs'); fs = double(s.fs); end
    catch
    end
end
end


function v = lookupByID(folder, fname, clusterID, isText)
%lookupByID  Read a 2-column phy .tsv and align column 2 to clusterID order.
n = numel(clusterID);
if isText; v = strings(n, 1); else; v = nan(n, 1); end
fp = fullfile(folder, fname);
if ~isfile(fp); return; end
try
    T = readtable(fp, 'FileType', 'text', 'Delimiter', '\t');
catch
    return
end
if width(T) < 2 || height(T) == 0; return; end
ids = double(T{:, 1});
[tf, loc] = ismember(clusterID, ids);
if isText
    vals = string(T{:, 2});
    v(tf) = vals(loc(tf));
else
    vals = double(T{:, 2});
    v(tf) = vals(loc(tf));
end
end


function out = readOptionalNPY(fn, fallback)
%readOptionalNPY  readNPY if the file exists, else return the fallback value.
if isfile(fn)
    out = double(readNPY(fn));
else
    out = fallback;
end
end


function s = durStr(sec)
s = char(string(seconds(sec), 'hh:mm:ss'));
end


function s = commaSep(n)
s = regexprep(sprintf('%d', round(n)), '\d(?=(\d{3})+$)', '$0,');
end


function closeIfValid(dlg)
if ~isempty(dlg) && isvalid(dlg); close(dlg); end
end


%% --- minimal NumPy .npy reader --------------------------------------------
function [data, shape] = readNPY(filename)
%readNPY  Read a little-endian NumPy .npy array (numeric or bool).
%   Supports the common KS4 dtypes (int/uint 8..64, float32/64, bool) in either
%   C or Fortran order and returns a MATLAB array of matching shape.
fid = fopen(filename, 'r', 'l');
if fid < 0; error('readNPY:open', 'Cannot open %s', filename); end
closer = onCleanup(@() fclose(fid));

magic = fread(fid, 6, '*uint8')';
if ~isequal(magic, uint8([147 78 85 77 80 89]))   % \x93NUMPY
    error('readNPY:magic', 'Not a .npy file: %s', filename);
end
verMajor = fread(fid, 1, 'uint8');
fread(fid, 1, 'uint8');   % minor version (unused)
if verMajor >= 2
    headerLen = fread(fid, 1, 'uint32');
else
    headerLen = fread(fid, 1, 'uint16');
end
header = fread(fid, headerLen, '*char')';

descrTok = regexp(header, '''descr''\s*:\s*''([^'']+)''', 'tokens', 'once');
descr = descrTok{1};
fortran = ~isempty(regexp(header, '''fortran_order''\s*:\s*True', 'once'));
shapeTok = regexp(header, '''shape''\s*:\s*\(([^)]*)\)', 'tokens', 'once');
shape = sscanf(strrep(shapeTok{1}, ',', ' '), '%g')';
if isempty(shape)
    shape = [1 1];
elseif isscalar(shape)
    shape = [shape 1];
end

mtype = npyType(descr);
data = fread(fid, prod(shape), ['*' mtype]);
if descr(2) == 'b'; data = logical(data); end

if fortran
    data = reshape(data, shape);
else
    data = reshape(data, fliplr(shape));
    data = permute(data, numel(shape):-1:1);
end
end


function mtype = npyType(descr)
%npyType  Map a NumPy dtype string (e.g. '<f4', '|b1') to a MATLAB class name.
kind  = descr(2);
bytes = str2double(descr(3:end));
switch kind
    case 'f'
        if bytes == 8; mtype = 'double'; else; mtype = 'single'; end
    case 'i'
        mtype = sprintf('int%d', bytes * 8);
    case 'u'
        mtype = sprintf('uint%d', bytes * 8);
    case 'b'
        mtype = 'uint8';   % bool stored as one byte; caller casts to logical
    otherwise
        error('readNPY:dtype', 'Unsupported NumPy dtype: %s', descr);
end
end
