function [Y, ev, info] = deriveSignals(obj, opts)
%deriveSignals  Read the recording and derive LFP, MUA and/or spike-band signals.
%   [Y, EVENTS, INFO] = ds.deriveSignals(Name=Value) reads the whole recording
%   through IntanDataset.readData -- so every supported layout works
%   (traditional *.rhd, one-file-per-signal, one-file-per-channel) -- then
%   derives the requested continuous signals and the digital-input events.
%   This is the implementation behind INTAN2MATLAB, which is a thin wrapper
%   around it: option names, processing and outputs are the same.
%
%   Outputs
%   -------
%   Y       struct with fields LFP, MUA, SPIKE (nSamples x nChan single). Only
%           the fields requested in dataTypeOut are filled; the others are
%           single([]).
%       Y.LFP   amplifier data resampled to LFP_Fs, then (only if requested)
%               zero-phase Butterworth band-limiting LFP_bpLoHi and notch
%               filters LFP_NotchHz, designed and applied at LFP_Fs. With the
%               defaults no filter beyond RESAMPLE's anti-aliasing is applied.
%       Y.MUA   zero-phase 4th-order Butterworth bandpass MUA_bpLoHi (designed
%               and applied at the original rate), rectified (ABS), resampled
%               to MUA_Fs, then moving-mean integrated on that grid with a
%               window of round(MUA_Fs/MUA_IntegrationHz) samples.
%       Y.SPIKE optionally resampled to SPIKE_Fs (Inf = original rate), then a
%               zero-phase 4th-order Butterworth bandpass SPIKE_bpLoHi
%               designed at SPIKE_Fs.
%   EVENTS  struct, one field per digital input line (named from labelField
%           via matlab.lang.makeValidName), each [k x 2] [t_on t_off] in
%           seconds on the original amplifier time base.
%   INFO    struct: RHDroot, filenames, recordingFormat, labels (amplifier
%           labels from labelField, in the column order of Y), origFs,
%           LFP/MUA/SPIKE sub-structs (Fs, time vector; LFP also bpLoHi,
%           NotchHz, NotchBW and a text description of the filter applied;
%           MUA also IntegrationHz and bpLoHi) for the requested types, and
%           importOptions (the options used; SPIKE_Fs is replaced by origFs
%           when Inf, and badChannels by the channels actually interpolated).
%
%   Options
%   -------
%     dataTypeOut        string array  "LFP"   any of "LFP", "MUA", "SPIKE"
%     keepAmpChannels    integer vector []     1-based amplifier channels to
%                        read, in this order, before all processing
%     channelRemap       integer vector []     final column order (1-based into
%                        the kept channels), applied after processing;
%                        INFO.labels is reordered to match
%     badChannels        integer vector or negative scalar []  columns (after
%                        keepAmpChannels, before channelRemap) replaced by
%                        spatial interpolation, FILLMISSING(...,'makima',2). A
%                        negative scalar flags channels with
%                        abs(zscore(rms(LFP))) > abs(value), computed on
%                        Y.LFP after any LFP filtering; requires "LFP".
%     LFP_Fs             Hz  1000
%     LFP_bpLoHi         [low high] Hz  [0 Inf]  LFP band limits. low = 0 means
%                        no high-pass, high = Inf means no low-pass, so [0 Inf]
%                        (default) applies no filter, [1 Inf] is a high-pass,
%                        [0 300] a low-pass and [1 300] a bandpass. The filter
%                        is BUTTER(4, ...) ('high' | 'low' | 'bandpass'),
%                        applied with FILTFILT (zero phase) at LFP_Fs after
%                        resampling, so every finite edge must be < LFP_Fs/2.
%                        As with any FILTFILT IIR filter, the start and end
%                        of the recording carry edge transients: for a 1 Hz
%                        high-pass, up to ~2 s at each end, longer for lower
%                        cut-offs. The interior is unaffected.
%     LFP_NotchHz        Hz vector  []  notch (band-stop) center frequencies,
%                        e.g. 60 or [60 120 180]; [] = no notch. Each notch is
%                        BUTTER(2, [f-BW/2 f+BW/2], 'stop') applied with
%                        FILTFILT at LFP_Fs; needs f-BW/2 > 0 and
%                        f+BW/2 < LFP_Fs/2.
%     LFP_NotchBW        Hz  2  width of each notch: its edges f +/- BW/2 are
%                        the -3 dB points of the designed filter (FILTFILT
%                        applies it twice, so they are -6 dB in the output).
%     MUA_Fs             Hz  2000
%     MUA_IntegrationHz  Hz  1000
%     MUA_bpLoHi         [low high] Hz  [300 5000]  (high < original rate/2)
%     SPIKE_Fs           Hz  Inf (= original rate)
%     SPIKE_bpLoHi       [low high] Hz  [300 5000]  (high < SPIKE_Fs/2)
%     labelField         "custom_channel_name" | "native_channel_name"
%     ProgressFcn        function handle, called as ProgressFcn(nDone, nTotal,
%                        message) before each step (one per file read, then one
%                        per processing stage) and once more as
%                        ProgressFcn(nTotal, nTotal, "Done"). It may throw to
%                        abort. Not stored in INFO.importOptions.
%
%   Memory: the amplifier data are read as single (see readData Precision),
%   so peak memory is about twice the single-precision recording.
%
%   Requires the Signal Processing Toolbox (BUTTER, FILTFILT, RESAMPLE).
%
%   See also INTAN2MATLAB, IntanDataset.toMat, IntanDataset.readData.

arguments
    obj (1,1) IntanDataset
    opts.channelRemap (1,:) double {mustBeInteger, mustBePositive} = []
    opts.badChannels double = []
    opts.keepAmpChannels double {mustBeInteger, mustBePositive} = []
    opts.dataTypeOut (1,:) string = "LFP"
    opts.LFP_Fs (1,1) double {mustBePositive} = 1000
    opts.LFP_bpLoHi (1,2) double {mustBeNonnegative} = [0 Inf]
    opts.LFP_NotchHz (1,:) double {mustBePositive, mustBeFinite} = []
    opts.LFP_NotchBW (1,1) double {mustBePositive, mustBeFinite} = 2
    opts.MUA_Fs (1,1) double {mustBePositive} = 2000
    opts.SPIKE_Fs (1,1) double {mustBePositive} = inf
    opts.MUA_IntegrationHz (1,1) double {mustBePositive} = 1000
    opts.MUA_bpLoHi (1,2) double {mustBePositive} = [300 5000]
    opts.SPIKE_bpLoHi (1,2) double {mustBePositive} = [300 5000]
    opts.labelField (1,1) string {mustBeMember(opts.labelField, ...
        ["custom_channel_name", "native_channel_name"])} = "custom_channel_name"
    opts.ProgressFcn = []
end

if ~isempty(opts.ProgressFcn) && ~isa(opts.ProgressFcn, 'function_handle')
    error('IntanDataset:deriveSignals:ProgressFcn', ...
        'ProgressFcn must be a function handle or [].');
end
progressFcn = opts.ProgressFcn;
opts = rmfield(opts, 'ProgressFcn');   % never stored in info.importOptions

% --- validate options (before reading anything) ---
badType = setdiff(opts.dataTypeOut, ["LFP" "MUA" "SPIKE"]);
if ~isempty(badType)
    error('IntanDataset:deriveSignals:dataTypeOut', ...
        'Unknown dataTypeOut value(s): %s. Use "LFP", "MUA" and/or "SPIKE".', ...
        strjoin(badType, ', '));
end
if opts.MUA_bpLoHi(1) >= opts.MUA_bpLoHi(2)
    error('IntanDataset:deriveSignals:MUA_bpLoHiOrder', ...
        'MUA_bpLoHi must be [low high] with low < high.');
end
if opts.SPIKE_bpLoHi(1) >= opts.SPIKE_bpLoHi(2)
    error('IntanDataset:deriveSignals:SPIKE_bpLoHiOrder', ...
        'SPIKE_bpLoHi must be [low high] with low < high.');
end
if ~isfinite(opts.LFP_bpLoHi(1)) || opts.LFP_bpLoHi(1) >= opts.LFP_bpLoHi(2)
    error('IntanDataset:deriveSignals:LFP_bpLoHiOrder', ...
        ['LFP_bpLoHi must be [low high] with a finite low < high ' ...
         '(low = 0: no high-pass, high = Inf: no low-pass).']);
end

has.LFP   = any(opts.dataTypeOut == "LFP");
has.MUA   = any(opts.dataTypeOut == "MUA");
has.SPIKE = any(opts.dataTypeOut == "SPIKE");

% LFP filters are designed at LFP_Fs, which is known before reading.
lfpFilter = has.LFP && (opts.LFP_bpLoHi(1) > 0 || isfinite(opts.LFP_bpLoHi(2)) ...
    || ~isempty(opts.LFP_NotchHz));
if has.LFP
    validateLFPFilter(opts);
end

autoBad = isscalar(opts.badChannels) && opts.badChannels < 0;
if autoBad && ~has.LFP
    error('IntanDataset:deriveSignals:AutoBadChannelsNeedLFP', ...
        ['Automatic bad-channel detection (negative scalar badChannels) is ' ...
         'computed from the LFP; include "LFP" in dataTypeOut.']);
end

if obj.NumFiles == 0
    obj.discoverFiles();
end
if obj.NumFiles == 0
    error('IntanDataset:deriveSignals:NoFiles', 'No Intan files in %s', obj.Folder);
end
if isnan(obj.Fs) || isempty(obj.PerFile)
    obj.refreshMetadata();
end
validateRates(opts, has, obj.Fs);   % header Fs: fail fast, before the long read

% Progress steps: one per file read, then one per processing stage.
nRead  = obj.NumFiles;
nProc  = has.LFP + lfpFilter + has.MUA + has.SPIKE + ~isempty(opts.badChannels) ...
    + ~isempty(opts.channelRemap) + 1;   % +1 = digital events
nSteps = nRead + nProc;

readCb = [];
if ~isempty(progressFcn)
    readCb = @(i, n, name) progressFcn(i - 1, nSteps, ...
        sprintf('Reading file %d/%d: %s', i, n, name));
end

% --- read (any layout), single precision, events keyed by labelField ---
data = obj.readData(KeepChannels=opts.keepAmpChannels(:).', Precision="single", ...
    EventLabelField=opts.labelField, ProgressFcn=readCb);
nDone = nRead;

AMPSIG = data.amplifier;
data.amplifier = [];
if isempty(AMPSIG)
    error('IntanDataset:deriveSignals:NoData', 'No amplifier data read from %s', obj.Folder);
end
origFs = data.Fs;
if origFs ~= obj.Fs
    validateRates(opts, has, origFs);   % header metadata was stale
end

if opts.labelField == "native_channel_name"
    labels = cellstr(data.nativeNames);
else
    labels = cellstr(data.channelNames);
end
ev = data.events;
filenames = cellstr(data.files);
clear data

Y.LFP   = single([]);
Y.MUA   = single([]);
Y.SPIKE = single([]);

% --- filter / resample ---
if has.LFP
    nDone = reportProgress(progressFcn, nDone, nSteps, ...
        sprintf('LFP: resampling to %g Hz', opts.LFP_Fs));
    Y.LFP = resample(AMPSIG, opts.LFP_Fs, origFs);
    if lfpFilter
        nDone = reportProgress(progressFcn, nDone, nSteps, ...
            "LFP: " + describeLFPFilter(opts));
        Y.LFP = filterLFP(Y.LFP, opts);
    end
end
if has.MUA
    % Bandpass at origFs -> rectify -> resample to MUA_Fs -> moving-mean
    % integration on the MUA_Fs grid.
    nDone = reportProgress(progressFcn, nDone, nSteps, ...
        sprintf('MUA: bandpass [%g %g] Hz, rectify, resample to %g Hz, integrate', ...
        opts.MUA_bpLoHi, opts.MUA_Fs));
    Wn = opts.MUA_bpLoHi ./ (origFs/2);
    [b, a] = butter(4, Wn, 'bandpass');
    Y.MUA = abs(filtfilt(b, a, AMPSIG));
    Y.MUA = resample(Y.MUA, opts.MUA_Fs, origFs);
    win = max(1, round(opts.MUA_Fs/opts.MUA_IntegrationHz));
    Y.MUA = single(movmean(Y.MUA, win));   % integrate along time
end
if has.SPIKE
    nDone = reportProgress(progressFcn, nDone, nSteps, ...
        sprintf('SPIKE: bandpass [%g %g] Hz', opts.SPIKE_bpLoHi));
    if isinf(opts.SPIKE_Fs) || opts.SPIKE_Fs == origFs
        opts.SPIKE_Fs = origFs;
        Y.SPIKE = AMPSIG;
    else
        Y.SPIKE = resample(AMPSIG, opts.SPIKE_Fs, origFs);
    end
    Wn = opts.SPIKE_bpLoHi ./ (opts.SPIKE_Fs/2);
    [b, a] = butter(4, Wn, 'bandpass');
    Y.SPIKE = filtfilt(b, a, Y.SPIKE);
end
clear AMPSIG

% --- interpolate bad channels (spatial), after processing, before remap ---
if ~isempty(opts.badChannels)
    nDone = reportProgress(progressFcn, nDone, nSteps, ...
        'Interpolating bad channels (fillmissing makima)');
    if autoBad
        r = rms(Y.LFP, 1);
        zr = abs(zscore(r));
        opts.badChannels = find(zr > abs(opts.badChannels));
    end
    badCh = opts.badChannels;
    if has.LFP
        Y.LFP(:, badCh) = NaN;
        Y.LFP = fillmissing(Y.LFP, 'makima', 2);
    end
    if has.MUA
        Y.MUA(:, badCh) = NaN;
        Y.MUA = fillmissing(Y.MUA, 'makima', 2);
    end
    if has.SPIKE
        Y.SPIKE(:, badCh) = NaN;
        Y.SPIKE = fillmissing(Y.SPIKE, 'makima', 2);
    end
end

% --- final channel order ---
if ~isempty(opts.channelRemap)
    nDone = reportProgress(progressFcn, nDone, nSteps, 'Applying channel remap');
    if has.LFP,   Y.LFP   = Y.LFP(:, opts.channelRemap);   end
    if has.MUA,   Y.MUA   = Y.MUA(:, opts.channelRemap);   end
    if has.SPIKE, Y.SPIKE = Y.SPIKE(:, opts.channelRemap); end
    labels = labels(opts.channelRemap);   % keep labels matched to Y columns
end

% Digital events were extracted by readData (bwlabel convention, seconds on
% the original amplifier grid); this step only reports it.
nDone = reportProgress(progressFcn, nDone, nSteps, 'Extracting digital events');

% --- package info ---
info = struct();
info.RHDroot         = char(obj.Folder);
info.filenames       = filenames;
info.recordingFormat = obj.RecordingFormat;
info.labels          = labels(:);
info.origFs          = origFs;
if has.LFP
    info.LFP.Fs      = opts.LFP_Fs;
    info.LFP.bpLoHi  = opts.LFP_bpLoHi;
    info.LFP.NotchHz = opts.LFP_NotchHz;
    info.LFP.NotchBW = opts.LFP_NotchBW;
    info.LFP.filter  = describeLFPFilter(opts);
    info.LFP.time    = (0:size(Y.LFP, 1)-1)' / opts.LFP_Fs;
end
if has.SPIKE
    info.SPIKE.Fs   = opts.SPIKE_Fs;
    info.SPIKE.time = (0:size(Y.SPIKE, 1)-1)' / opts.SPIKE_Fs;
end
if has.MUA
    info.MUA.Fs            = opts.MUA_Fs;
    info.MUA.IntegrationHz = opts.MUA_IntegrationHz;
    info.MUA.bpLoHi        = opts.MUA_bpLoHi;
    info.MUA.time          = (0:size(Y.MUA, 1)-1)' / opts.MUA_Fs;
end
info.importOptions = opts;

reportProgress(progressFcn, nDone, nSteps, 'Done');   % nDone == nSteps here
end


function nDone = reportProgress(fcn, nDone, nTotal, msg)
%reportProgress  Invoke the optional ProgressFcn and advance the step count.
if ~isempty(fcn)
    fcn(nDone, nTotal, msg);
end
nDone = nDone + 1;
end


function validateLFPFilter(opts)
%validateLFPFilter  Check the LFP filter edges against LFP_Fs/2, the Nyquist
%   rate of the resampled LFP they are designed and applied at.
nyq = opts.LFP_Fs / 2;
lo = opts.LFP_bpLoHi(1);
hi = opts.LFP_bpLoHi(2);
if lo >= nyq
    error('IntanDataset:deriveSignals:LFP_bpNyquist', ...
        'LFP_bpLoHi low edge (%g Hz) must be below LFP_Fs/2 (%g Hz).', lo, nyq);
end
if isfinite(hi) && hi >= nyq
    error('IntanDataset:deriveSignals:LFP_bpNyquist', ...
        ['LFP_bpLoHi high edge (%g Hz) must be below LFP_Fs/2 (%g Hz); ' ...
         'use Inf for no low-pass.'], hi, nyq);
end
bw = opts.LFP_NotchBW;
for f = opts.LFP_NotchHz
    if f - bw/2 <= 0 || f + bw/2 >= nyq
        error('IntanDataset:deriveSignals:LFP_Notch', ...
            ['LFP notch %g Hz with width %g Hz spans [%g %g] Hz, which must lie ' ...
             'inside (0, LFP_Fs/2 = %g Hz).'], f, bw, f - bw/2, f + bw/2, nyq);
    end
end
end


function s = describeLFPFilter(opts)
%describeLFPFilter  One-line text description of the LFP filters requested.
lo = opts.LFP_bpLoHi(1);
hi = opts.LFP_bpLoHi(2);
parts = strings(1, 0);
if lo > 0 && isfinite(hi)
    parts(end+1) = sprintf("bandpass [%g %g] Hz (butter order 4)", lo, hi);
elseif lo > 0
    parts(end+1) = sprintf("high-pass %g Hz (butter order 4)", lo);
elseif isfinite(hi)
    parts(end+1) = sprintf("low-pass %g Hz (butter order 4)", hi);
end
if ~isempty(opts.LFP_NotchHz)
    parts(end+1) = sprintf("notch %s Hz, width %g Hz (butter order 2 band-stop)", ...
        strjoin(compose("%g", opts.LFP_NotchHz), "/"), opts.LFP_NotchBW);
end
if isempty(parts)
    s = "none (resample anti-aliasing only)";
else
    s = "zero-phase (filtfilt) at " + sprintf("%g", opts.LFP_Fs) + " Hz: " ...
        + strjoin(parts, "; ");
end
end


function X = filterLFP(X, opts)
%filterLFP  Apply the requested LFP band-limit and notch filters at LFP_Fs.
%   Each filter is a Butterworth design converted to second-order sections
%   (numerically stable for cut-offs that are small relative to LFP_Fs) and
%   applied with FILTFILT. Channels are filtered one at a time in double
%   precision and stored back in X's class, bounding the extra memory to one
%   double-precision channel.
nyq = opts.LFP_Fs / 2;
lo = opts.LFP_bpLoHi(1);
hi = opts.LFP_bpLoHi(2);
filt = struct('sos', {}, 'g', {});
if lo > 0 && isfinite(hi)
    filt(end+1) = butterSOS(4, [lo hi] / nyq, 'bandpass');
elseif lo > 0
    filt(end+1) = butterSOS(4, lo / nyq, 'high');
elseif isfinite(hi)
    filt(end+1) = butterSOS(4, hi / nyq, 'low');
end
bw = opts.LFP_NotchBW;
for f = opts.LFP_NotchHz
    filt(end+1) = butterSOS(2, [f - bw/2, f + bw/2] / nyq, 'stop'); %#ok<AGROW>
end
for c = 1:size(X, 2)
    x = double(X(:, c));
    for s = 1:numel(filt)
        x = filtfilt(filt(s).sos, filt(s).g, x);
    end
    X(:, c) = x;
end
end


function f = butterSOS(n, Wn, type)
%butterSOS  BUTTER design as second-order sections + gain (for FILTFILT).
[z, p, k] = butter(n, Wn, type);
[f.sos, f.g] = zp2sos(z, p, k);
end


function validateRates(opts, has, origFs)
%validateRates  Check band edges against the Nyquist rate of the data they
%   are applied to.
if has.MUA && opts.MUA_bpLoHi(2) >= origFs/2
    error('IntanDataset:deriveSignals:MUA_bpNyquist', ...
        'MUA_bpLoHi high edge (%g Hz) must be below origFs/2 (%g Hz).', ...
        opts.MUA_bpLoHi(2), origFs/2);
end
if has.SPIKE
    spikeFs = opts.SPIKE_Fs;
    if isinf(spikeFs), spikeFs = origFs; end
    if opts.SPIKE_bpLoHi(2) >= spikeFs/2
        error('IntanDataset:deriveSignals:SPIKE_bpNyquist', ...
            'SPIKE_bpLoHi high edge (%g Hz) must be below SPIKE_Fs/2 (%g Hz).', ...
            opts.SPIKE_bpLoHi(2), spikeFs/2);
    end
end
end
