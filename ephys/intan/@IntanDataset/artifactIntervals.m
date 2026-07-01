function iv = artifactIntervals(obj, opts)
%artifactIntervals  Merged artifact periods (seconds) for SI silence_periods.
%   IV = ds.artifactIntervals() returns a [k x 2] matrix of [tStart tEnd] in
%   seconds, recording-relative (file 1 = t0), combining:
%     * every manual period in ds.ManualArtifacts (always included), and
%     * the automatic amplitude-deviation detector's intervals when
%       ds.ArtifactConfig.Enabled (or opts.IncludeAuto) is true.
%   Overlapping / adjacent periods are merged into one. runSpikeInterface passes
%   this list to the generated Python so SpikeInterface's silence_periods zeros
%   exactly these spans in the recording it feeds Kilosort4; the *.rhd files are
%   never modified.
%
%   Auto intervals are found with the same streamPlan + detectArtifacts loop the
%   Artifacts-tab preview uses (analyzeArtifacts), one chunk in memory at a time,
%   so the preview and the actual run agree. Each chunk's intervals are shifted
%   by the running sample offset so they are global (recording-relative).
%
%   Options (auto-detection params; each omitted option falls back to
%   ds.ArtifactConfig)
%   -------------------------------------------------------------------
%     IncludeAuto  logical  run the detector (default = ds.ArtifactConfig.Enabled)
%     Files        (1,:) string  subset/order of files (default: all)
%     Method/Threshold/RmsWindowMs/MergeGapMs/MinChannels/PadMs   detection params
%     Filter/FilterType/FilterCutoff/FilterOrder   detect on a filtered view
%       (default broadband, matching analyzeArtifacts/toBin)
%     ProgressFcn  function handle  ProgressFcn(i, nChunks, chunkName)
%
%   See also IntanDataset.detectArtifacts, IntanDataset.analyzeArtifacts,
%   IntanDataset.runSpikeInterface, IntanDataset.ManualArtifacts.

arguments
    obj (1,1) IntanDataset
    opts.IncludeAuto = []           % [] -> ds.ArtifactConfig.Enabled
    opts.Files (1,:) string = string.empty(1,0)
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

acfg = IntanDataset.normalizeArtifactConfig(obj.ArtifactConfig);

includeAuto = opts.IncludeAuto;
if isempty(includeAuto)
    includeAuto = logical(acfg.Enabled);
else
    includeAuto = logical(includeAuto);
end

% Manual periods are always included (explicit user intent).
manual = obj.ManualArtifacts;
if isempty(manual); manual = zeros(0, 2); end

if ~includeAuto
    iv = mergeIntervals(manual);
    return
end

% --- automatic detection over the whole recording, chunk by chunk ---------
if obj.NumFiles == 0
    obj.discoverFiles();
end
if obj.NumFiles == 0
    iv = mergeIntervals(manual);   % nothing to detect on
    return
end
if isnan(obj.Fs) || isempty(obj.PerFile)
    obj.refreshMetadata();
end

% Resolve detection params (per-call overrides ds.ArtifactConfig).
method   = opts.Method;      if method == "";      method   = acfg.Method;      end
thr      = opts.Threshold;   if isnan(thr);        thr      = acfg.Threshold;   end
rmsWinMs = opts.RmsWindowMs; if isnan(rmsWinMs);   rmsWinMs = acfg.RmsWindowMs; end
mergeGap = opts.MergeGapMs;  if isnan(mergeGap);   mergeGap = acfg.MergeGapMs;  end
minCh    = opts.MinChannels; if isnan(minCh);      minCh    = acfg.MinChannels; end
padMs    = opts.PadMs;       if isnan(padMs);      padMs    = acfg.PadMs;       end

Fs   = obj.Fs;
plan = obj.streamPlan(Files=opts.Files);

auto     = zeros(0, 2);
offsetSamp = 0;               % running recording-global sample offset
nChunks  = numel(plan);
for i = 1:nChunks
    if ~isempty(opts.ProgressFcn)
        opts.ProgressFcn(i, nChunks, plan(i).name);
    end
    X = obj.readChunkUV(plan(i));   % [nSamples x nChan], microvolts
    if isempty(X)
        continue
    end

    if opts.Filter
        X = obj.filterContinuous(X, Type=opts.FilterType, ...
            Cutoff=opts.FilterCutoff, Order=opts.FilterOrder, Fs=Fs);
    end

    [~, chunkIv] = obj.detectArtifacts(X, Method=method, Threshold=thr, ...
        RmsWindowMs=rmsWinMs, MinChannels=minCh, MergeGapMs=mergeGap, ...
        PadMs=padMs, Fs=Fs);

    if ~isempty(chunkIv)
        auto = [auto; chunkIv + offsetSamp / Fs]; %#ok<AGROW> shift to global seconds
    end
    offsetSamp = offsetSamp + size(X, 1);
end

iv = mergeIntervals([manual; auto]);
end


function out = mergeIntervals(iv)
%mergeIntervals  Sort [k x 2] second-intervals and merge overlapping/adjacent.
if isempty(iv)
    out = zeros(0, 2);
    return
end
iv = iv(iv(:, 2) > iv(:, 1), :);           % drop degenerate/empty spans
if isempty(iv)
    out = zeros(0, 2);
    return
end
iv = sortrows(iv, 1);
out = iv(1, :);
for k = 2:size(iv, 1)
    if iv(k, 1) <= out(end, 2)             % overlap or touch -> extend
        out(end, 2) = max(out(end, 2), iv(k, 2));
    else
        out(end+1, :) = iv(k, :); %#ok<AGROW>
    end
end
end
