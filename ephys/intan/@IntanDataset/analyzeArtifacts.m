function summary = analyzeArtifacts(obj, opts)
%analyzeArtifacts  Summarise automatic artifact detection over the recording.
%   SUMMARY = ds.analyzeArtifacts() streams the recording one *.rhd file at a
%   time (the same one-file-in-memory invariant toBin relies on), runs
%   detectArtifacts on each file with the dataset's ArtifactConfig, and
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
%     files          files analysed
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
    error('IntanDataset:analyzeArtifacts:NoFiles', 'No *.rhd files in %s', obj.Folder);
end

% Resolve detection params (per-call overrides ds.ArtifactConfig).
cfg = IntanDataset.normalizeArtifactConfig(obj.ArtifactConfig);
method   = opts.Method;        if method == "";         method   = cfg.Method;       end
thr      = opts.Threshold;     if isnan(thr);           thr      = cfg.Threshold;    end
rmsWinMs = opts.RmsWindowMs;   if isnan(rmsWinMs);      rmsWinMs = cfg.RmsWindowMs;  end
mergeGapMs = opts.MergeGapMs;  if isnan(mergeGapMs);    mergeGapMs = cfg.MergeGapMs; end
minCh    = opts.MinChannels;   if isnan(minCh);         minCh    = cfg.MinChannels;  end
padMs    = opts.PadMs;         if isnan(padMs);         padMs    = cfg.PadMs;        end

% File list (chronological unless overridden)
if isempty(opts.Files)
    fileList = obj.Files;
else
    fileList = opts.Files;
end

Fs = obj.Fs;
nSamples = 0;
nBlanked = 0;
nIntervals = 0;
channelCounts = [];     % [1 x nChan], grown on first file
channelNames  = string.empty(1,0);
rmsWindowMsUsed = NaN;

nFiles = numel(fileList);
for i = 1:nFiles
    if ~isempty(opts.ProgressFcn)
        opts.ProgressFcn(i, nFiles, fileList(i));
    end
    ffn = fullfile(obj.Folder, fileList(i));
    S = read_Intan_RHD2000_file_modified(ffn, Verbosity="silent");
    if ~isfield(S, 'amplifier_data') || isempty(S.amplifier_data)
        continue
    end
    if isnan(Fs)
        Fs = S.frequency_parameters.amplifier_sample_rate;
    end

    X = S.amplifier_data.';   % [nSamples x nChan], microvolts

    % Channel names (first file only), applying any reorder/subset.
    if isempty(channelNames)
        cn = string({S.amplifier_channels.custom_channel_name});
        if ~isempty(opts.ChannelOrder)
            cn = cn(opts.ChannelOrder);
        end
        channelNames = cn;
    end
    clear S

    if ~isempty(opts.ChannelOrder)
        if max(opts.ChannelOrder) > size(X, 2)
            error('IntanDataset:analyzeArtifacts:BadChannelOrder', ...
                'ChannelOrder references channel %d but file has %d.', ...
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
summary.files       = fileList;
end
