function info = toBin(obj, opts)
%toBin  Stream the recording to a Kilosort4 int16 .bin file, one file in RAM.
%   INFO = ds.toBin() writes raw broadband data, scaled to int16, to ds.BinFile
%   in the layout Kilosort4 expects (no header, little-endian, channel index
%   varying fastest on disk). Only one *.rhd file is held in memory at a time:
%   each file is read, optionally filtered/blanked, scaled, cast to int16, and
%   appended to the open binary file before the next file is read.
%
%   By default the broadband signal is written unfiltered (Kilosort4 filters and
%   whitens internally). The scale 1/0.195 restores the native ADC int16
%   resolution from the microvolt values produced by the Intan reader, mirroring
%   MATRIX2KILOSORT so that the streamed file is byte-identical to the in-memory
%   writer for the same data.
%
%   Options
%   -------
%     Files          (1,:) string  subset/order of files (default: all, chronological)
%     ChannelOrder   (1,:) double  1-based reorder/subset of amplifier channels
%     Scale          (1,1) double  multiplier before cast (default ds.Scale)
%     Offset         (1,1) double  added after scaling (default 0)
%     Dtype          string        on-disk class (default ds.Dtype)
%     Filter         (1,1) logical  high/band-pass before writing (default false)
%     FilterType     "highpass"|"lowpass"|"bandpass" (default "highpass")
%     FilterCutoff   scalar or [lo hi] Hz  (default 300)
%     FilterOrder    (1,1) double          (default 4)
%     FilterEdgeMode "independent"|"overlap" (default "independent")
%     OverlapSamples (1,1) double  samples carried across file edges (overlap mode)
%     Blank          (1,1) logical  force automatic artifact detect + blank.
%                    When false, blanking still runs if ds.ArtifactConfig.Enabled.
%     ArtifactMethod / ArtifactThreshold / ArtifactRmsWindowMs / ArtifactMergeGapMs /
%     ArtifactMinChannels / ArtifactPadMs   detection params; each falls back to
%                    ds.ArtifactConfig when left at its default. See
%                    detectArtifacts (RmsWindow/MergeGap/Pad are in milliseconds).
%     WriteMeta      (1,1) logical  write JSON sidecar (default true)
%     BinFile        (1,1) string   override output path (default ds.BinFile)
%
%   Output INFO struct: filename, dtype, nChan, nSamples, fs, scale, offset,
%   nClipped, nBytes, metaFile (if written), nManualBlanked, nAutoBlanked, and
%   autoArtifact (struct: enabled, method, threshold, rmsWindowMs, mergeGapMs,
%   minChannels, padMs, nBlanked, fraction, pctDuration, nIntervals, channelCounts).
%
%   GUARD: every file must have the same amplifier channel count as the first;
%   a flat int16 .bin cannot represent a mid-dataset channel-count change.
%
%   See also MATRIX2KILOSORT, IntanDataset.matrixToBin, IntanDataset.filterContinuous.

arguments
    obj (1,1) IntanDataset
    opts.Files (1,:) string = string.empty(1,0)
    opts.ChannelOrder (1,:) double {mustBeInteger, mustBePositive} = []
    opts.Scale (1,1) double = NaN
    opts.Offset (1,1) double {mustBeFinite} = 0
    opts.Dtype (1,1) string = ""
    opts.Filter (1,1) logical = false
    opts.FilterType (1,1) string {mustBeMember(opts.FilterType, ["highpass","lowpass","bandpass"])} = "highpass"
    opts.FilterCutoff (1,:) double {mustBePositive} = 300
    opts.FilterOrder (1,1) double {mustBeInteger, mustBePositive} = 4
    opts.FilterEdgeMode (1,1) string {mustBeMember(opts.FilterEdgeMode, ["independent","overlap"])} = "independent"
    opts.OverlapSamples (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    opts.Blank (1,1) logical = false
    opts.ArtifactMethod (1,1) string = ""
    opts.ArtifactThreshold (1,1) double = NaN
    opts.ArtifactRmsWindowMs (1,1) double = NaN
    opts.ArtifactMergeGapMs (1,1) double = NaN
    opts.ArtifactMinChannels (1,1) double = NaN
    opts.ArtifactPadMs (1,1) double = NaN
    opts.WriteMeta (1,1) logical = true
    opts.BinFile (1,1) string = ""
end

if obj.NumFiles == 0
    obj.discoverFiles();
end
if obj.NumFiles == 0
    error('IntanDataset:toBin:NoFiles', 'No Intan files in %s', obj.Folder);
end
% Header metadata (Fs, sample counts) drives the stream plan and is needed up
% front for the .bin sidecar; parse it now if it has not been parsed yet.
if isnan(obj.Fs) || isempty(obj.PerFile)
    obj.refreshMetadata();
end

% Resolve config (per-call -> dataset defaults)
scale = opts.Scale;  if isnan(scale); scale = obj.Scale; end
dtype = opts.Dtype;  if dtype == "";  dtype = obj.Dtype; end
binFile = opts.BinFile; if binFile == ""; binFile = obj.BinFile; end

% Resolve automatic artifact-blanking config (per-call -> ds.ArtifactConfig).
% Blanking runs when the Blank option is set OR the dataset config is enabled.
acfg = IntanDataset.normalizeArtifactConfig(obj.ArtifactConfig);
doBlank   = opts.Blank || acfg.Enabled;
artMethod = opts.ArtifactMethod;        if artMethod == "";       artMethod = acfg.Method;      end
artThr    = opts.ArtifactThreshold;     if isnan(artThr);         artThr    = acfg.Threshold;   end
artWinMs  = opts.ArtifactRmsWindowMs;   if isnan(artWinMs);       artWinMs  = acfg.RmsWindowMs;  end
artGapMs  = opts.ArtifactMergeGapMs;    if isnan(artGapMs);       artGapMs  = acfg.MergeGapMs;   end
artMinCh  = opts.ArtifactMinChannels;   if isnan(artMinCh);       artMinCh  = acfg.MinChannels;  end
artPadMs  = opts.ArtifactPadMs;         if isnan(artPadMs);       artPadMs  = acfg.PadMs;        end

% Resolve the streaming plan (one chunk per *.rhd file for traditional; bounded
% sample windows over the flat .dat for split formats). The downstream loop is
% identical for every format because each chunk yields a [nSamp x nChan]
% microvolt matrix from readChunkUV.
plan = obj.streamPlan(Files=opts.Files);
if isempty(plan)
    error('IntanDataset:toBin:NoFiles', 'No readable Intan data in %s', obj.Folder);
end

% Ensure output folder exists
outDir = fileparts(char(binFile));
if outDir == ""
    outDir = char(obj.outputFolder());
    binFile = fullfile(outDir, binFile);
end
if ~isfolder(outDir)
    mkdir(outDir);
end

% dtype -> class + saturation range (mirrors matrix2kilosort)
[targetClass, isFloat, lo, hi] = resolveDtype(dtype);

% Overlap mode needs filtering on
useOverlap = opts.Filter && opts.FilterEdgeMode == "overlap" && opts.OverlapSamples > 0;

fid = fopen(binFile, 'w', 'ieee-le');
if fid < 0
    error('IntanDataset:toBin:OpenFailed', 'Could not open %s for writing.', binFile);
end
cleaner = onCleanup(@() closeIfOpen(fid));

firstNumChan = NaN;
nChanOut  = NaN;
nSamples  = 0;
nClipped  = 0;
nManualBlanked = 0;   % samples zeroed by manual artifact periods
nAutoBlanked   = 0;   % samples zeroed by automatic artifact detection
nAutoIntervals = 0;   % contiguous auto-artifact intervals (summed per file)
autoChanCounts = [];  % [1 x nChanOut] per-channel exceedance counts
artWinMsUsed   = NaN; % resolved running-RMS window (ms), for reporting
Fs        = obj.Fs;
tailRaw   = [];  % carried raw samples for overlap edge mode

fprintf('Streaming %d chunk(s) -> %s\n', numel(plan), binFile);
for i = 1:numel(plan)
    X = obj.readChunkUV(plan(i));  % [nSamples x nChan], microvolts (all channels)

    if isempty(X)
        warning('IntanDataset:toBin:NoData', 'No amplifier data in %s; skipping.', plan(i).name);
        continue
    end

    thisNumChan = size(X, 2);

    % Channel-count guard (flat bin cannot tolerate a change)
    if isnan(firstNumChan)
        firstNumChan = thisNumChan;
    elseif thisNumChan ~= firstNumChan
        error('IntanDataset:toBin:ChannelMismatch', ...
            ['Amplifier channel count changed mid-dataset (%d -> %d) at %s. ', ...
             'A flat int16 .bin cannot represent this.'], ...
            firstNumChan, thisNumChan, plan(i).name);
    end

    % Channel reorder/subset
    if ~isempty(opts.ChannelOrder)
        if max(opts.ChannelOrder) > thisNumChan
            error('IntanDataset:toBin:BadChannelOrder', ...
                'ChannelOrder references channel %d but file has %d.', ...
                max(opts.ChannelOrder), thisNumChan);
        end
        X = X(:, opts.ChannelOrder);
    end
    if isnan(nChanOut)
        nChanOut = size(X, 2);
    end

    % Filtering (optionally with overlap across file boundaries)
    if opts.Filter
        if useOverlap && ~isempty(tailRaw)
            nPad = size(tailRaw, 1);
            Xf = obj.filterContinuous([tailRaw; X], Type=opts.FilterType, ...
                Cutoff=opts.FilterCutoff, Order=opts.FilterOrder, Fs=Fs);
            Xf = Xf(nPad+1:end, :);
        else
            Xf = obj.filterContinuous(X, Type=opts.FilterType, ...
                Cutoff=opts.FilterCutoff, Order=opts.FilterOrder, Fs=Fs);
        end
        if useOverlap
            k = min(opts.OverlapSamples, size(X, 1));
            tailRaw = X(end-k+1:end, :);  % carry RAW (pre-filter) tail
        end
        X = Xf;
    end

    % Automatic artifact detection + blanking (per-channel amplitude deviation).
    if doBlank
        [mask, ~, astats] = obj.detectArtifacts(X, Method=artMethod, ...
            Threshold=artThr, RmsWindowMs=artWinMs, MinChannels=artMinCh, ...
            MergeGapMs=artGapMs, PadMs=artPadMs, Fs=Fs);
        X = obj.blankArtifacts(X, mask, Fill="zero");
        nAutoBlanked   = nAutoBlanked + nnz(mask);
        nAutoIntervals = nAutoIntervals + astats.numIntervals;
        if isempty(autoChanCounts)
            autoChanCounts = astats.channelExceedCounts;
        else
            autoChanCounts = autoChanCounts + astats.channelExceedCounts;
        end
        if isnan(artWinMsUsed); artWinMsUsed = astats.rmsWindowMs; end
    end

    % Manually defined artifact periods (Visualize tab). Recording-relative,
    % so map them into this file using the running sample offset (nSamples =
    % samples written from earlier files).
    if ~isempty(obj.ManualArtifacts)
        mmask = obj.manualArtifactMask(size(X, 1), nSamples, Fs);
        if any(mmask)
            X = obj.blankArtifacts(X, mmask, Fill="zero");
            nManualBlanked = nManualBlanked + nnz(mmask);
        end
    end

    % Scale -> [nChan x nSamples] (channel fastest) -> cast -> write
    blk = X.';                                   % [nChan x nSamplesThisFile]
    blk = scale .* double(blk) + opts.Offset;
    if ~isFloat
        nClipped = nClipped + nnz(blk < lo | blk > hi);
    end
    blk = cast(blk, targetClass);
    fwrite(fid, blk, targetClass);

    nSamples = nSamples + size(X, 1);
end

clear cleaner;  % closes fid

if isnan(nChanOut)
    error('IntanDataset:toBin:NoDataWritten', 'No data was written (all files empty?).');
end

d = dir(binFile);
info = struct();
info.filename  = char(binFile);
info.dtype     = char(dtype);
info.nChan     = nChanOut;
info.nSamples  = nSamples;
info.fs        = Fs;
info.scale     = scale;
info.offset    = opts.Offset;
info.byteOrder = 'little-endian';
info.nClipped  = nClipped;
info.nManualArtifacts = size(obj.ManualArtifacts, 1);
info.nManualBlanked   = nManualBlanked;
info.nAutoBlanked     = nAutoBlanked;
if isempty(autoChanCounts); autoChanCounts = zeros(1, nChanOut); end
info.autoArtifact = struct( ...
    'enabled',       doBlank, ...
    'method',        char(artMethod), ...
    'threshold',     artThr, ...
    'rmsWindowMs',   artWinMsUsed, ...
    'mergeGapMs',    artGapMs, ...
    'minChannels',   artMinCh, ...
    'padMs',         artPadMs, ...
    'nBlanked',      nAutoBlanked, ...
    'fraction',      nAutoBlanked / max(nSamples, 1), ...
    'pctDuration',   100 * nAutoBlanked / max(nSamples, 1), ...
    'nIntervals',    nAutoIntervals, ...
    'channelCounts', autoChanCounts);
info.nBytes    = d.bytes;

if doBlank
    fprintf(['Auto artifacts (%s, thr=%g): %d samples (%.3f s, %.2f%%) zeroed ' ...
        'in %d interval(s).\n'], artMethod, artThr, nAutoBlanked, ...
        nAutoBlanked / max(Fs, 1), info.autoArtifact.pctDuration, nAutoIntervals);
end

if nManualBlanked > 0
    fprintf('Blanked %d manual artifact period(s): %d samples (%.3f s) zeroed.\n', ...
        info.nManualArtifacts, nManualBlanked, nManualBlanked / max(Fs, 1));
end

if nClipped > 0
    warning('IntanDataset:toBin:Clipping', ...
        '%d sample(s) (%.4f%%) saturated the %s range and were clipped.', ...
        nClipped, 100*nClipped/(nChanOut*max(nSamples,1)), dtype);
end

% JSON sidecar (bookkeeping; Kilosort4 does not read it)
if opts.WriteMeta
    [mDir, mName] = fileparts(binFile);
    meta = struct('n_chan_bin', nChanOut, 'fs', Fs, 'dtype', char(dtype), ...
        'n_samples', nSamples, 'byte_order', 'little-endian', 'scale', scale, ...
        'offset', opts.Offset, 'bin_file', char(binFile), ...
        'source_folder', char(obj.Folder), ...
        'manual_artifacts', obj.ManualArtifacts, ...
        'n_manual_blanked', nManualBlanked, ...
        'auto_artifacts', info.autoArtifact, ...
        'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    metaFile = fullfile(mDir, mName + ".json");
    writeJson(meta, metaFile);
    info.metaFile = char(metaFile);
end

if ~isempty(obj.Manifest) && isa(obj.Manifest, 'Manifest')
    obj.Manifest.add("toBin", "Wrote Kilosort4 .bin", ...
        struct('binFile', info.filename, 'nChan', info.nChan, ...
        'nSamples', info.nSamples, 'fs', info.fs, ...
        'filtered', opts.Filter, 'blanked', doBlank, ...
        'autoBlanked', nAutoBlanked, ...
        'manualArtifacts', info.nManualArtifacts, ...
        'manualBlanked', nManualBlanked));
end

fprintf('Done. %.2f MB written (%s, little-endian); n_chan_bin=%d, fs=%g\n', ...
    info.nBytes/1e6, info.dtype, info.nChan, info.fs);
end


function [targetClass, isFloat, lo, hi] = resolveDtype(dtype)
switch dtype
    case "int16"
        targetClass = 'int16';  isFloat = false; lo = -32768;      hi = 32767;
    case "uint16"
        targetClass = 'uint16'; isFloat = false; lo = 0;           hi = 65535;
    case "int32"
        targetClass = 'int32';  isFloat = false; lo = -2147483648; hi = 2147483647;
    case {"single","float32"}
        targetClass = 'single'; isFloat = true;  lo = -inf;        hi = inf;
    otherwise
        error('IntanDataset:toBin:BadDtype', 'Unsupported dtype "%s".', dtype);
end
end


function writeJson(s, file)
try
    txt = jsonencode(s, 'PrettyPrint', true);
catch
    txt = jsonencode(s);
end
fid = fopen(file, 'w');
if fid < 0
    warning('IntanDataset:toBin:MetaWriteFailed', 'Could not write %s', file);
    return
end
fwrite(fid, txt, 'char');
fclose(fid);
end


function closeIfOpen(fid)
if ~isempty(fopen(fid))
    fclose(fid);
end
end
