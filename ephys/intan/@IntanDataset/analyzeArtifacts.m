function summary = analyzeArtifacts(obj, opts)
%analyzeArtifacts  Summarize automatic artifact detection over the recording.
%   SUMMARY = ds.analyzeArtifacts() streams the recording one chunk at a time
%   (per *.rhd file for the traditional format, or bounded sample windows for the
%   split formats - the same one-chunk-in-memory invariant toBin relies on), runs
%   detectArtifacts on each chunk with the dataset's ArtifactConfig, and
%   accumulates statistics WITHOUT writing anything to disk. It is the read-only
%   counterpart to toBin's blanking step, used by the Artifacts tab to preview
%   how much of the recording would be zeroed.
%
%   Options (any omitted option falls back to ds.ArtifactConfig)
%   -----------------------------------------------------------
%     Files          (1,:) string  subset/order of files (default: all)
%     ChannelOrder   (1,:) double  1-based reorder/subset of amplifier channels
%     Method/Threshold/RmsWindowMs/MergeGapMs/MinChannels/PadMs  detection params
%       (see detectArtifacts; RmsWindowMs/MergeGapMs/PadMs in milliseconds)
%     Filter         (1,1) logical  high/band-pass before detecting (default false,
%                    matching toBin's default broadband write)
%     FilterType/FilterCutoff/FilterOrder   filter params (see toBin)
%     ProgressFcn    function handle  ProgressFcn(i, nFiles, fileName)
%
%   Output SUMMARY struct
%   ---------------------
%     method, threshold, rmsWindowMs, mergeGapMs, minChannels, padMs
%     fs, nSamples, durationSec, nChan, channelNames
%     channelCounts  [1 x nChan]  samples each channel exceeded its threshold
%     channelPct     [1 x nChan]  channelCounts as percent of nSamples
%     nBlanked       combined samples flagged (would be zeroed on every channel)
%     fraction       nBlanked / nSamples
%     pctDuration    100 * fraction
%     nIntervals     number of contiguous artifact intervals (summed per file)
%     files          files analyzed
%
%   See also IntanDataset.detectArtifacts, IntanDataset.toBin.

arguments
    obj (1,1) IntanDataset
    opts.Files (1,:) string = string.empty(1,0)
    opts.ChannelOrder (1,:) double {mustBeInteger, mustBePositive} = []
    opts.Method (1,1) string = ""
    opts.Threshold (1,1) double = NaN
    opts.RmsWindowMs (1,1) double = NaN
    opts.MergeGapMs (1,1) double = NaN
    opts.MinChannels (1,1) double = NaN
    opts.PadMs (1,1) double = NaN
    opts.Filter (1,1) logical = false
    opts.FilterType (1,1) string {mustBeMember(opts.FilterType, ["highpass","lowpass","bandpass"])} = "highpass"
    opts.FilterCutoff (1,:) double {mustBePositive} = 300
    opts.FilterOrder (1,1) double {mustBeInteger, mustBePositive} = 4
    opts.ProgressFcn = []
end

if obj.NumFiles == 0
    obj.discoverFiles();
end
if obj.NumFiles == 0
    error('IntanDataset:analyzeArtifacts:NoFiles', 'No Intan files in %s', obj.Folder);
end
if isnan(obj.Fs) || isempty(obj.PerFile)
    obj.refreshMetadata();
end

% Resolve detection params (per-call overrides ds.ArtifactConfig).
cfg = IntanDataset.normalizeArtifactConfig(obj.ArtifactConfig);
method   = opts.Method;        if method == "";         method   = cfg.Method;       end
thr      = opts.Threshold;     if isnan(thr);           thr      = cfg.Threshold;    end
rmsWinMs = opts.RmsWindowMs;   if isnan(rmsWinMs);      rmsWinMs = cfg.RmsWindowMs;  end
mergeGapMs = opts.MergeGapMs;  if isnan(mergeGapMs);    mergeGapMs = cfg.MergeGapMs; end
minCh    = opts.MinChannels;   if isnan(minCh);         minCh    = cfg.MinChannels;  end
padMs    = opts.PadMs;         if isnan(padMs);         padMs    = cfg.PadMs;        end

% Streaming plan (per *.rhd file for traditional; bounded sample windows for the
% split formats). The loop body is format-agnostic via readChunkUV.
plan = obj.streamPlan(Files=opts.Files);

% Channel names from the parsed header (applying any reorder/subset), independent
% of which chunk we are on - identical for every supported format.
channelNames = obj.ChannelNames;
if ~isempty(opts.ChannelOrder)
    if isempty(channelNames) || max(opts.ChannelOrder) > numel(channelNames)
        channelNames = string.empty(1,0);   % resolved against data width below
    else
        channelNames = channelNames(opts.ChannelOrder);
    end
end

Fs = obj.Fs;
nSamples = 0;
nBlanked = 0;
nIntervals = 0;
channelCounts = [];     % [1 x nChan], grown on first chunk
rmsWindowMsUsed = NaN;

nChunks = numel(plan);
for i = 1:nChunks
    if ~isempty(opts.ProgressFcn)
        opts.ProgressFcn(i, nChunks, plan(i).name);
    end
    X = obj.readChunkUV(plan(i));   % [nSamples x nChan], microvolts (all channels)
    if isempty(X)
        continue
    end

    if ~isempty(opts.ChannelOrder)
        if max(opts.ChannelOrder) > size(X, 2)
            error('IntanDataset:analyzeArtifacts:BadChannelOrder', ...
                'ChannelOrder references channel %d but recording has %d.', ...
                max(opts.ChannelOrder), size(X, 2));
        end
        X = X(:, opts.ChannelOrder);
    end

    if opts.Filter
        X = obj.filterContinuous(X, Type=opts.FilterType, ...
            Cutoff=opts.FilterCutoff, Order=opts.FilterOrder, Fs=Fs);
    end

    [mask, ~, st] = obj.detectArtifacts(X, Method=method, Threshold=thr, ...
        RmsWindowMs=rmsWinMs, MinChannels=minCh, MergeGapMs=mergeGapMs, ...
        PadMs=padMs, Fs=Fs);

    if isempty(channelCounts)
        channelCounts = st.channelExceedCounts;
    else
        channelCounts = channelCounts + st.channelExceedCounts;
    end
    nBlanked   = nBlanked + nnz(mask);
    nIntervals = nIntervals + st.numIntervals;
    nSamples   = nSamples + size(X, 1);
    if isnan(rmsWindowMsUsed); rmsWindowMsUsed = st.rmsWindowMs; end
end

if isempty(channelCounts); channelCounts = zeros(1, 0); end

summary = struct();
summary.method      = method;
summary.threshold   = thr;
summary.rmsWindowMs = rmsWindowMsUsed;
summary.mergeGapMs  = mergeGapMs;
summary.minChannels = minCh;
summary.padMs       = padMs;
summary.fs          = Fs;
summary.nSamples    = nSamples;
summary.durationSec = nSamples / max(Fs, 1);
summary.nChan       = numel(channelCounts);
summary.channelNames = channelNames;
summary.channelCounts = channelCounts;
summary.channelPct  = 100 * channelCounts / max(nSamples, 1);
summary.nBlanked    = nBlanked;
summary.fraction    = nBlanked / max(nSamples, 1);
summary.pctDuration = 100 * nBlanked / max(nSamples, 1);
summary.nIntervals  = nIntervals;
summary.files       = string({plan.name});
end
