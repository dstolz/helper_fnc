function [Y, events, info] = intan2matlab(RHDroot, options)
%INTAN2MATLAB  Read an Intan recording folder; optionally derive LFP, MUA, and/or spike-band signals.
%   [Y, EVENTS, INFO] = INTAN2MATLAB(RHDroot) reads the Intan recording in
%   folder RHDroot, concatenates it in time, extracts digital line events,
%   and returns the requested continuous signals and metadata.
%
%   This function is a thin wrapper around IntanDataset:
%       ds = IntanDataset(RHDroot);
%       [Y, EVENTS, INFO] = ds.deriveSignals(options...);
%   so reading, processing and file discovery are shared with the rest of the
%   Intan pipeline, and every layout IntanDataset reads is supported:
%   traditional *.rhd files (sorted chronologically by file timestamp),
%   one-file-per-signal and one-file-per-channel.
%
%   Outputs
%   -------
%   Y       struct
%           Signal fields are filled only if requested via options.dataTypeOut
%           (the others are single([])).
%
%           Y.LFP   nSamplesLFP×nChan single
%               LFP-band data obtained by resampling the amplifier data to
%               options.LFP_Fs, then, only if requested, zero-phase
%               Butterworth band-limiting (options.LFP_bpLoHi) and notch
%               (options.LFP_NotchHz / LFP_NotchBW) filters designed and
%               applied at LFP_Fs. With the default options no filtering
%               beyond RESAMPLE's anti-aliasing is applied.
%
%           Y.MUA   nSamplesMUA×nChan single
%               Multiunit envelope derived from the amplifier data using a
%               zero-phase 4th-order Butterworth bandpass defined by
%               options.MUA_bpLoHi (Hz, designed and applied at origFs),
%               followed by rectification (ABS), resampling of the rectified
%               signal to the MUA sampling grid options.MUA_Fs, and
%               moving-mean integration on that grid with window length
%               round(options.MUA_Fs/options.MUA_IntegrationHz) samples.
%
%           Y.SPIKE nSamplesSPIKE×nChan single
%               Spike-band signal obtained by optional resampling to
%               options.SPIKE_Fs (or original sampling if SPIKE_Fs = inf),
%               then zero-phase 4th-order Butterworth bandpass filtering
%               using options.SPIKE_bpLoHi (Hz, designed at SPIKE_Fs, i.e. the
%               rate of the data being filtered).
%
%   EVENTS  struct
%           One field per digital input line. Field names are taken from the
%           Intan digital input channel metadata specified by
%           options.labelField and made valid via MATLAB.LANG.MAKEVALIDNAME.
%           Each field contains an N×2 array [t_on t_off] in seconds on the
%           original amplifier time base (origFs).
%
%   INFO    struct
%           Metadata, including:
%             • INFO.RHDroot, INFO.filenames, INFO.recordingFormat
%             • INFO.labels (amplifier channel labels from options.labelField)
%             • INFO.origFs (amplifier sample rate)
%             • Per-stream sampling and time vectors (seconds):
%                 - INFO.LFP.Fs,   INFO.LFP.bpLoHi, INFO.LFP.NotchHz,
%                   INFO.LFP.NotchBW, INFO.LFP.filter (text description of
%                   the LFP filters applied), INFO.LFP.time
%                 - INFO.MUA.Fs,   INFO.MUA.IntegrationHz, INFO.MUA.bpLoHi, INFO.MUA.time
%                 - INFO.SPIKE.Fs, INFO.SPIKE.time
%             • INFO.importOptions (the OPTIONS struct passed in)
%
%   Syntax
%   ------
%   [Y, EVENTS, INFO] = INTAN2MATLAB(RHDroot)
%   [Y, EVENTS, INFO] = INTAN2MATLAB(RHDroot, options)
%
%   Options (name-value via ARGUMENTS)
%   -------------------------------
%   options.dataTypeOut        string array   "LFP"
%       Select which signals to compute/return. Any subset of:
%       "LFP", "MUA", "SPIKE".
%
%   options.keepAmpChannels    integer vector []
%       Subset of amplifier channels to load/keep (1-based) prior to
%       concatenation and all processing.
%
%   options.channelRemap       integer vector []
%       Optional final channel order (1-based) applied after processing.
%       INFO.labels is reordered identically so labels stay matched to the
%       columns of Y.
%
%   options.badChannels        integer vector or scalar []
%       1-based channel indices to spatially interpolate across columns
%       AFTER concatenation using FILLMISSING(...,'makima',2). Indices refer
%       to the columns after keepAmpChannels and BEFORE channelRemap.
%       If a scalar negative value is provided, channels are auto-flagged as
%       outliers by abs(zscore(rms(LFP))) > abs(value) (heuristic), computed
%       on Y.LFP after any LFP filtering; this requires "LFP" in
%       dataTypeOut. The channels actually interpolated are recorded in
%       INFO.importOptions.badChannels.
%
%   options.LFP_Fs             scalar Hz      1000
%       Target LFP sampling rate for Y.LFP.
%
%   options.LFP_bpLoHi         1×2 double Hz  [0 Inf]
%       LFP band limits [low high]. low = 0 means no high-pass and
%       high = Inf means no low-pass, so the default [0 Inf] applies no
%       filter; [1 Inf] is a high-pass, [0 300] a low-pass and [1 300] a
%       bandpass. Designed with BUTTER(4, ...) ('high' | 'low' | 'bandpass')
%       at LFP_Fs, as second-order sections, and applied with FILTFILT (zero
%       phase) after resampling. Every finite edge must be < LFP_Fs/2.
%       As with any FILTFILT IIR filter, the start and end of the recording
%       carry edge transients: for a 1 Hz high-pass, up to ~2 s at each
%       end, longer for lower cut-offs. The interior is unaffected.
%
%   options.LFP_NotchHz        double vector Hz  []
%       Notch (band-stop) center frequencies, e.g. 60 or [60 120 180];
%       [] = no notch. Each notch is BUTTER(2, [f-BW/2 f+BW/2], 'stop') at
%       LFP_Fs applied with FILTFILT, and needs f-BW/2 > 0 and
%       f+BW/2 < LFP_Fs/2.
%
%   options.LFP_NotchBW        scalar Hz      2
%       Width BW of each notch. The edges f ± BW/2 are the -3 dB points of
%       the designed filter; FILTFILT applies it twice, so they are -6 dB
%       in Y.LFP.
%
%   options.MUA_Fs             scalar Hz      2000
%       Target MUA sampling rate for Y.MUA.
%
%   options.MUA_IntegrationHz  scalar Hz      1000
%       Integration rate used to form the MUA envelope. The moving-mean
%       window length is round(options.MUA_Fs/options.MUA_IntegrationHz).
%
%   options.MUA_bpLoHi         1×2 double Hz  [300 5000]
%       Bandpass edges [low high] for MUA extraction at origFs. Must satisfy
%       low < high < origFs/2.
%
%   options.SPIKE_Fs           scalar Hz      inf
%       Target sampling rate for Y.SPIKE. Use inf to keep the original
%       amplifier sampling (origFs).
%
%   options.SPIKE_bpLoHi       1×2 double Hz  [300 5000]
%       Bandpass edges [low high] for spike-band filtering. Must satisfy
%       low < high < SPIKE_Fs/2.
%
%   options.labelField         string         "custom_channel_name"
%       Intan channel name used to label amplifier and digital input lines:
%       "custom_channel_name" or "native_channel_name".
%
%   options.ProgressFcn        function handle []
%       Optional progress callback, called as
%           ProgressFcn(nDone, nTotal, message)
%       before each step (one step per file read, then one per processing
%       stage) and once more as ProgressFcn(nTotal, nTotal, "Done") at the
%       end. nDone is the number of steps already completed. The callback may
%       throw an error to abort the import. When empty, progress is printed to
%       the command window with PARFOR_PROGRESS. The handle is not stored in
%       INFO.importOptions.
%
%   Notes
%   -----
%   • Traditional *.rhd data are read with READ_INTAN_RHD2000_FILE_MODIFIED;
%     split layouts with IntanDataset's .dat readers (see IntanDataset.readData).
%   • Digital events are identified by labeling contiguous high segments of
%     the concatenated digital input samples; event times are returned in
%     seconds at origFs.
%   • Output signals are stored as SINGLE to reduce memory footprint.
%   • Errors are raised with IntanDataset:deriveSignals:* identifiers.
%
%   Requirements
%   ------------
%   Signal Processing Toolbox (BUTTER, FILTFILT, RESAMPLE). BWLABEL (Image
%   Processing Toolbox) is used for events when available, with an equivalent
%   fallback otherwise.
%
%   See also INTANDATASET, IntanDataset.deriveSignals, IntanDataset.toMat,
%   READ_INTAN_RHD2000_FILE_MODIFIED, RESAMPLE, BUTTER, FILTFILT, FILLMISSING

arguments
    RHDroot (1,1) string
    options.channelRemap (1,:) double {mustBeInteger,mustBePositive} = []
    options.badChannels double = []
    options.keepAmpChannels double {mustBeInteger} = []
    options.dataTypeOut (1,:) string = "LFP"; % can be one or more values "LFP","MUA","SPIKE"
    options.LFP_Fs (1,1) double {mustBePositive} = 1000
    options.LFP_bpLoHi (1,2) double {mustBeNonnegative} = [0 Inf] % 0 = no high-pass, Inf = no low-pass
    options.LFP_NotchHz (1,:) double {mustBePositive, mustBeFinite} = [] % [] = no notch
    options.LFP_NotchBW (1,1) double {mustBePositive, mustBeFinite} = 2
    options.MUA_Fs (1,1) double {mustBePositive} = 2000
    options.SPIKE_Fs (1,1) double {mustBePositive} = inf % inf = original
    options.MUA_IntegrationHz (1,1) double {mustBePositive} = 1000
    options.MUA_bpLoHi (1,2) double {mustBePositive} = [300 5000]
    options.SPIKE_bpLoHi (1,2) double {mustBePositive} = [300 5000]
    options.labelField (1,1) string = "custom_channel_name"
    options.ProgressFcn = []
end

ds = IntanDataset(RHDroot);
if ds.NumFiles == 0
    error('INTAN2MATLAB:NoFiles', 'No Intan recording files found in %s', RHDroot);
end

progressFcn = options.ProgressFcn;
if isempty(progressFcn)
    fprintf('Reading %s recording from %d file(s) in %s\n', ...
        ds.RecordingFormat, ds.NumFiles, RHDroot);
    progressFcn = @consoleProgress;
end
args = namedargs2cell(rmfield(options, 'ProgressFcn'));
[Y, events, info] = ds.deriveSignals(args{:}, 'ProgressFcn', progressFcn);

if isscalar(options.badChannels) && options.badChannels < 0
    bc = info.importOptions.badChannels;
    fprintf('%d channels with abs(zscore(rms)) > %g flagged as bad and interpolated: %s\n', ...
        numel(bc), abs(options.badChannels), mat2str(bc));
end
end


function consoleProgress(nDone, nTotal, ~)
%consoleProgress  Command-window progress bar over all steps (PARFOR_PROGRESS).
if nDone == 0
    parfor_progress(nTotal);
elseif nDone >= nTotal
    parfor_progress;
    parfor_progress(0);
else
    parfor_progress;
end
end
