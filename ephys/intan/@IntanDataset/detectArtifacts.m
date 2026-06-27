function [mask, intervals, stats] = detectArtifacts(obj, X, opts)
%detectArtifacts  Flag large transient artifacts across channels.
%   [MASK, INTERVALS, STATS] = ds.detectArtifacts(X) screens the
%   [nSamples x nChan] signal X for artifacts and returns:
%     MASK       [nSamples x 1] logical, true where an artifact is present
%     INTERVALS  [k x 2] artifact intervals in seconds [t_on t_off]
%     STATS      struct with the threshold(s) used and per-channel exceedance
%
%   Options
%   -------
%     Method      "rms" | "mad" | "microvolts" | "commonmode"   (default "rms")
%       "rms"        per-channel running RMS amplitude; a sample is flagged on a
%                    channel when its running RMS rises Threshold robust standard
%                    deviations above that channel's baseline. Polarity-blind
%                    (the signal is squared), so it catches large excursions of
%                    either sign. This is the automatic amplitude-deviation
%                    detector; see RmsWindow.
%       "mad"        per-channel robust z = |x - median| / (1.4826*MAD); a
%                    sample is flagged on a channel when z > Threshold.
%       "microvolts" absolute amplitude threshold in microvolts (|x| > Threshold).
%       "commonmode" flag the across-channel mean when |mean| > Threshold (uV).
%     Threshold   scalar; default 9 (rms, in robust SD), 8 (mad),
%                 1500 (microvolts/commonmode)
%     RmsWindowMs running-RMS window length in milliseconds (Method "rms" only);
%                 default ~1 ms. Converted to samples with Fs.
%     MinChannels minimum channels that must exceed simultaneously (default 2;
%                 ignored for "commonmode")
%     MergeGapMs  milliseconds; gaps of <= MergeGapMs of clean signal between two
%                 flagged runs are filled so they blank as one continuous
%                 artifact block ("stitching"). Applied before PadMs. Default 0.
%     PadMs       expand each flagged region by +/- this many milliseconds
%                 (default 0)
%     Fs          sample rate (Hz); defaults to ds.Fs. All millisecond options
%                 are converted to samples with this rate.
%
%   STATS fields: method, threshold, rmsWindowMs, minChannels, mergeGapMs,
%   padMs, fraction (of samples flagged), numIntervals, and
%   channelExceedCounts [1 x nChan] - the number of samples each channel
%   exceeded its threshold (before the MinChannels combination), used to
%   summarise artifacts per channel.
%
%   See also IntanDataset.blankArtifacts, IntanDataset.toBin, IntanDataset.analyzeArtifacts.

arguments
    obj (1,1) IntanDataset
    X double
    opts.Method (1,1) string {mustBeMember(opts.Method, ...
        ["rms","mad","microvolts","commonmode"])} = "rms"
    opts.Threshold (1,1) double = NaN
    opts.RmsWindowMs (1,1) double = NaN
    opts.MinChannels (1,1) double {mustBeInteger, mustBePositive} = 2
    opts.MergeGapMs (1,1) double {mustBeNonnegative} = 0
    opts.PadMs (1,1) double {mustBeNonnegative} = 0
    opts.Fs (1,1) double = NaN
end

Fs = opts.Fs;
if isnan(Fs); Fs = obj.Fs; end
if isnan(Fs) || Fs <= 0
    error('IntanDataset:detectArtifacts:NoFs', ...
        'Sample rate unknown; pass opts.Fs or run refreshMetadata first.');
end

% Default thresholds per method
thr = opts.Threshold;
if isnan(thr)
    switch opts.Method
        case "rms",        thr = 9;
        case "mad",        thr = 8;
        otherwise,         thr = 1500;  % microvolts / commonmode
    end
end

[nSamples, nChan] = size(X);
rmsWindowMs = NaN;   % reported in stats; only set for the "rms" method

% Convert the millisecond options to samples with the data sample rate.
mergeGapSamp = round(opts.MergeGapMs * 1e-3 * Fs);
padSamp      = round(opts.PadMs      * 1e-3 * Fs);

switch opts.Method
    case "rms"
        % Per-channel running RMS amplitude, then a robust z-score of that RMS
        % against the channel's own baseline (median / MAD of the RMS). Squaring
        % makes it polarity-blind; the running window smooths single-sample
        % spikes so genuine high-amplitude episodes stand out.
        if isnan(opts.RmsWindowMs) || opts.RmsWindowMs <= 0
            w = max(1, round(Fs * 0.001));   % ~1 ms default
        else
            w = max(1, round(opts.RmsWindowMs * 1e-3 * Fs));
        end
        rmsWindowMs = 1e3 * w / Fs;           % actual window after rounding
        r = sqrt(movmean(X.^2, w, 1));        % [nSamples x nChan]
        med = median(r, 1);
        sd  = median(abs(r - med), 1) * 1.4826;   % robust SD of the RMS
        sd(sd == 0) = eps;
        z = (r - med) ./ sd;                  % positive => elevated amplitude
        exceed = z > thr;
        mask = sum(exceed, 2) >= min(opts.MinChannels, nChan);

    case "mad"
        med = median(X, 1);
        madv = median(abs(X - med), 1) * 1.4826;
        madv(madv == 0) = eps;
        z = abs(X - med) ./ madv;          % [nSamples x nChan]
        exceed = z > thr;
        mask = sum(exceed, 2) >= min(opts.MinChannels, nChan);

    case "microvolts"
        exceed = abs(X) > thr;
        mask = sum(exceed, 2) >= min(opts.MinChannels, nChan);

    case "commonmode"
        cm = mean(X, 2);
        mask = abs(cm) > thr;
        exceed = repmat(mask, 1, nChan);
end

mask = mask(:);

% Stitch flagged epochs separated by short clean gaps into one block.
if mergeGapSamp > 0 && any(mask)
    mask = mergeGaps(mask, mergeGapSamp);
end

% Pad flagged regions
if padSamp > 0 && any(mask)
    mask = padMask(mask, padSamp);
end

intervals = maskToIntervals(mask, Fs);

stats = struct();
stats.method      = opts.Method;
stats.threshold   = thr;
stats.rmsWindowMs = rmsWindowMs;
stats.minChannels = opts.MinChannels;
stats.mergeGapMs  = opts.MergeGapMs;
stats.padMs       = opts.PadMs;
stats.fraction    = nnz(mask) / max(nSamples, 1);
stats.numIntervals = size(intervals, 1);
stats.channelExceedCounts = sum(exceed, 1);
end


function m = mergeGaps(m, gap)
% Fill runs of <= gap consecutive false samples that lie between two true runs,
% so closely spaced artifacts blank as one continuous block.
m = m(:);
d = diff([0; m; 0]);
on  = find(d == 1);          % start indices of true runs
off = find(d == -1) - 1;     % end indices of true runs
for k = 1:numel(on) - 1
    gapLen = on(k+1) - off(k) - 1;
    if gapLen <= gap
        m(off(k)+1 : on(k+1)-1) = true;
    end
end
end


function m = padMask(m, pad)
% Dilate a logical mask by +/- pad samples via cumulative-sum window.
n = numel(m);
idx = find(m);
lo = max(1, idx - pad);
hi = min(n, idx + pad);
delta = zeros(n + 1, 1);
delta(lo)     = delta(lo) + 1;
delta(hi + 1) = delta(hi + 1) - 1;
m = cumsum(delta(1:n)) > 0;
end


function iv = maskToIntervals(mask, Fs)
d = diff([0; mask(:); 0]);
on  = find(d == 1);
off = find(d == -1) - 1;
if isempty(on)
    iv = zeros(0, 2);
else
    iv = [on off] ./ Fs;
end
end
