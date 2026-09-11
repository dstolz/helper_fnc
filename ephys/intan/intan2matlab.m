function [Y, events, info] = intan2matlab(RHDroot, options)
%INTAN2MATLAB  Read and concatenate Intan *.rhd files; optionally derive LFP, MUA, and/or spike-band signals.
%   [Y, EVENTS, INFO] = INTAN2MATLAB(RHDroot) discovers all *.rhd files in
%   folder RHDroot, sorts them chronologically by file timestamp, reads each
%   file, concatenates the recording in time, extracts digital line events,
%   and returns requested continuous signals and metadata.
%
%   Outputs
%   -------
%   Y       struct
%           Signal fields are present only if requested via options.dataTypeOut.
%
%           Y.LFP   nSamplesLFP×nChan single
%               LFP-band data obtained by resampling the amplifier data to
%               options.LFP_Fs. (No additional LFP filtering is applied.)
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
%             • INFO.RHDroot, INFO.filenames
%             • INFO.labels (amplifier channel labels from options.labelField)
%             • INFO.origFs (amplifier sample rate)
%             • Per-stream sampling and time vectors (seconds):
%                 - INFO.LFP.Fs,   INFO.LFP.time
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
%       outliers by abs(zscore(rms(LFP))) > abs(value) (heuristic); this
%       requires "LFP" in dataTypeOut. The channels actually interpolated are
%       recorded in INFO.importOptions.badChannels.
%
%   options.LFP_Fs             scalar Hz      1000
%       Target LFP sampling rate for Y.LFP.
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
%       low < high.
%
%   options.SPIKE_Fs           scalar Hz      inf
%       Target sampling rate for Y.SPIKE. Use inf to keep the original
%       amplifier sampling (origFs).
%
%   options.SPIKE_bpLoHi       1×2 double Hz  [300 5000]
%       Bandpass edges [low high] for spike-band filtering at origFs.
%
%   options.labelField         string         "custom_channel_name"
%       Field within Intan channel structs used to label amplifier and
%       digital input lines (e.g., "custom_channel_name" or
%       "native_channel_name").
%
%   options.ProgressFcn        function handle []
%       Optional progress callback, called as
%           ProgressFcn(nDone, nTotal, message)
%       before each step (one step per *.rhd file read, then one per
%       processing stage) and once more as ProgressFcn(nTotal, nTotal, "Done")
%       at the end. nDone is the number of steps already completed. The
%       callback may throw an error to abort the import. When empty, progress
%       is printed to the command window with PARFOR_PROGRESS. The handle is
%       not stored in INFO.importOptions.
%
%   Notes
%   -----
%   • Files are discovered with DIR and sorted by DATENUM.
%   • Data are read using READ_INTAN_RHD2000_FILE_MODIFIED.
%   • Digital events are identified by labeling contiguous high segments of
%     concatenated digital input samples using BWLABEL; event times are
%     returned in seconds at origFs.
%   • Output signals are stored as SINGLE to reduce memory footprint.
%
%   Requirements
%   ------------
%   Signal Processing Toolbox (BUTTER, FILTFILT, RESAMPLE) and Image
%   Processing Toolbox (BWLABEL). Function READ_INTAN_RHD2000_FILE_MODIFIED
%   must be on the MATLAB path.
%
%   See also READ_INTAN_RHD2000_FILE_MODIFIED, RESAMPLE, BUTTER, FILTFILT, BWLABEL, FILLMISSING

arguments
    RHDroot (1,1) string
    options.channelRemap (1,:) double {mustBeInteger,mustBePositive} = []
    options.badChannels double = []
    options.keepAmpChannels double {mustBeInteger} = []
    options.dataTypeOut (1,:) string = "LFP"; % can be one or more values "LFP","MUA","SPIKE"
    options.LFP_Fs (1,1) double {mustBePositive} = 1000
    options.MUA_Fs (1,1) double {mustBePositive} = 2000
    options.SPIKE_Fs (1,1) double {mustBePositive} = inf % inf = original
    options.MUA_IntegrationHz (1,1) double {mustBePositive} = 1000
    options.MUA_bpLoHi (1,2) double {mustBePositive} = [300 5000]
    options.SPIKE_bpLoHi (1,2) double {mustBePositive} = [300 5000]
    options.labelField (1,1) string = "custom_channel_name"
    options.ProgressFcn = []
end

if ~isempty(options.ProgressFcn) && ~isa(options.ProgressFcn, 'function_handle')
    error('INTAN2MATLAB:ProgressFcn', 'ProgressFcn must be a function handle or [].');
end
progressFcn = options.ProgressFcn;
options = rmfield(options, 'ProgressFcn');   % never stored in info.importOptions

% Validate dataTypeOut values
badType = setdiff(options.dataTypeOut, ["LFP" "MUA" "SPIKE"]);
if ~isempty(badType)
    error('INTAN2MATLAB:dataTypeOut', ...
        'Unknown dataTypeOut value(s): %s. Use "LFP", "MUA" and/or "SPIKE".', ...
        strjoin(badType, ', '));
end

% Validate band-edge ordering
if options.MUA_bpLoHi(1) >= options.MUA_bpLoHi(2)
    error('INTAN2MATLAB:MUA_bpLoHiOrder','MUA_bpLoHi must be [low high] with low < high.');
end
if options.SPIKE_bpLoHi(1) >= options.SPIKE_bpLoHi(2)
    error('INTAN2MATLAB:SPIKE_bpLoHiOrder','SPIKE_bpLoHi must be [low high] with low < high.');
end

% Discover files and sort chronologically by datenum (fallback to name if needed)
D = dir(fullfile(RHDroot,'*.rhd'));
if isempty(D)
    error('INTAN2MATLAB:NoFiles','No .rhd files found in %s', RHDroot);
end
[~,ix] = sort([D.datenum]);
D = D(ix);
filenames = {D.name};


has.LFP = any(options.dataTypeOut == "LFP");
has.MUA = any(options.dataTypeOut == "MUA");
has.SPIKE = any(options.dataTypeOut == "SPIKE");

autoBad = isscalar(options.badChannels) && options.badChannels < 0;
if autoBad && ~has.LFP
    error('INTAN2MATLAB:AutoBadChannelsNeedLFP', ...
        ['Automatic bad-channel detection (negative scalar badChannels) is ' ...
         'computed from the LFP; include "LFP" in dataTypeOut.']);
end

% Progress steps: one per file, then one per processing stage.
nProc = has.LFP + has.MUA + has.SPIKE + ~isempty(options.badChannels) ...
    + ~isempty(options.channelRemap) + 1;   % +1 = digital events
nSteps = numel(D) + nProc;
nDone  = 0;


digData = cell(size(D));

Y.LFP = single([]);
Y.MUA = single([]);
Y.SPIKE = single([]);
AMPSIG = single([]);

fprintf('Reading RHD data from %d files\n',numel(D))
if isempty(progressFcn), parfor_progress(numel(D)); end
for i = 1:numel(D)
    nDone = reportProgress(progressFcn, nDone, nSteps, ...
        sprintf('Reading file %d/%d: %s', i, numel(D), D(i).name));
    ffn = fullfile(D(i).folder, D(i).name);
    S = read_Intan_RHD2000_file_modified(ffn,Verbosity="silent");

    S.amplifier_data = single(S.amplifier_data);

    % Select amplifier channels
    if ~isempty(options.keepAmpChannels)
        S.amplifier_channels = S.amplifier_channels(options.keepAmpChannels);
        S.amplifier_data     = S.amplifier_data(options.keepAmpChannels,:);
    end

    origFs = S.frequency_parameters.amplifier_sample_rate;
    if i == 1
        validateRates(options, has, origFs);   % fail fast, before reading everything
    end

    % Set label
    labels = {S.amplifier_channels.(options.labelField)};

    AMPSIG = [AMPSIG; S.amplifier_data.'];


    % only use number of digital channels from start of recording...
    % sometimes additional channels come online ???
    if i == 1
        ndid = size(S.board_dig_in_data,1);
    end

    digData{i} = S.board_dig_in_data(1:ndid,:);
    if isempty(progressFcn), parfor_progress; end
end
if isempty(progressFcn), parfor_progress(0); end


fprintf('Processing signals ...')

% filter signals ----------------------------------------------

if has.LFP
    nDone = reportProgress(progressFcn, nDone, nSteps, ...
        sprintf('LFP: resampling to %g Hz', options.LFP_Fs));
    Y.LFP = resample(AMPSIG, options.LFP_Fs, origFs);
end
if has.MUA
    % Bandpass at origFs -> rectify -> resample to MUA_Fs -> moving-mean
    % integration on the MUA_Fs grid (see help above).
    nDone = reportProgress(progressFcn, nDone, nSteps, ...
        sprintf('MUA: bandpass [%g %g] Hz, rectify, resample to %g Hz, integrate', ...
        options.MUA_bpLoHi, options.MUA_Fs));
    Wn = options.MUA_bpLoHi./(origFs/2);
    [b,a] = butter(4, Wn, 'bandpass');
    Y.MUA = abs(filtfilt(b,a,AMPSIG));
    Y.MUA = resample(Y.MUA, options.MUA_Fs, origFs);
    win = max(1, round(options.MUA_Fs/options.MUA_IntegrationHz));
    Y.MUA = single(movmean(Y.MUA, win)); % integrate along time
end

if has.SPIKE
    nDone = reportProgress(progressFcn, nDone, nSteps, ...
        sprintf('SPIKE: bandpass [%g %g] Hz', options.SPIKE_bpLoHi));
    if isinf(options.SPIKE_Fs) || options.SPIKE_Fs == origFs
        options.SPIKE_Fs = origFs;
        Y.SPIKE = AMPSIG;
    else
        Y.SPIKE = resample(AMPSIG, options.SPIKE_Fs, origFs);
    end
    Wn = options.SPIKE_bpLoHi./(options.SPIKE_Fs/2);
    [b,a] = butter(4, Wn, 'bandpass');
    Y.SPIKE = filtfilt(b,a,Y.SPIKE);
end
clear AMPSIG

% Interpolate bad channels across channels (spatial) after concat, before remap
if ~isempty(options.badChannels)
    nDone = reportProgress(progressFcn, nDone, nSteps, ...
        'Interpolating bad channels (fillmissing makima)');
    if autoBad
        r = rms(Y.LFP,1);
        zr = abs(zscore(r));
        zrthr = abs(options.badChannels);
        ind = zr > zrthr;
        options.badChannels = find(ind);
        fprintf('%d channels with abs(zscore(rms)) > %g flagged as bad and interpolated: %s\n', ...
            sum(ind),zrthr,mat2str(options.badChannels))
    end

    badCh = options.badChannels;

    % LFP
    if has.LFP
        Y.LFP(:,badCh) = NaN;
        Y.LFP = fillmissing(Y.LFP, 'makima', 2);
    end

    % MUA
    if has.MUA
        Y.MUA(:,badCh) = NaN;
        Y.MUA = fillmissing(Y.MUA, 'makima', 2);
    end

    % SPIKE
    if has.SPIKE
        Y.SPIKE(:,badCh) = NaN;
        Y.SPIKE = fillmissing(Y.SPIKE, 'makima', 2);
    end
end



if ~isempty(options.channelRemap)
    nDone = reportProgress(progressFcn, nDone, nSteps, 'Applying channel remap');
    if has.LFP, Y.LFP = Y.LFP(:,options.channelRemap); end
    if has.MUA, Y.MUA = Y.MUA(:,options.channelRemap); end
    if has.SPIKE, Y.SPIKE = Y.SPIKE(:,options.channelRemap); end
    labels = labels(options.channelRemap);   % keep labels matched to Y columns
end





% handle digital lines -----------------------------------
nDone = reportProgress(progressFcn, nDone, nSteps, 'Extracting digital events');
events = struct();
if ndid > 0
    ccn = {S.board_dig_in_channels.(options.labelField)};
    ccn = ccn(1:ndid);
    ccn = matlab.lang.makeValidName(ccn);
else
    ccn = {};   % no digital input lines recorded
end

digData = cat(2,digData{:}).';

% Build events at each stream's sampling grid
for j = 1:numel(ccn)
    ev = bwlabel(digData(:,j));
    u = unique(ev(ev>0));
    if isempty(u)
        events.(ccn{j}) = zeros(0,2);
    else
        trl1 = arrayfun(@(a) find(ev==a,1,'first'), u);
        trl2 = arrayfun(@(a) find(ev==a,1,'last'),  u);
        events.(ccn{j}) = [trl1 trl2] ./ origFs;
    end
end


% Package info
info = struct();
info.RHDroot = char(RHDroot);
info.filenames = filenames;
info.labels = labels(:);
info.origFs = origFs;

if has.LFP
    info.LFP.Fs = options.LFP_Fs;
    info.LFP.time = (0:size(Y.LFP,1)-1)' / options.LFP_Fs;
end

if has.SPIKE
    info.SPIKE.Fs = options.SPIKE_Fs;
    info.SPIKE.time = (0:size(Y.SPIKE,1)-1)' / options.SPIKE_Fs;
end

if has.MUA
    info.MUA.Fs = options.MUA_Fs;
    info.MUA.IntegrationHz = options.MUA_IntegrationHz;
    info.MUA.bpLoHi = options.MUA_bpLoHi;
    info.MUA.time = (0:size(Y.MUA,1)-1)' / options.MUA_Fs;
end


info.importOptions = options;

reportProgress(progressFcn, nDone, nSteps, 'Done');   % nDone == nSteps here
fprintf(' done\n')
end


function nDone = reportProgress(fcn, nDone, nTotal, msg)
%reportProgress  Invoke the optional ProgressFcn and advance the step count.
%   Called before each step with the steps completed so far; returns the
%   count including the step now starting.
if ~isempty(fcn)
    fcn(nDone, nTotal, msg);
end
nDone = nDone + 1;
end


function validateRates(options, has, origFs)
%validateRates  Check band edges against the Nyquist rate of the data they
%   are applied to, once the amplifier sample rate is known.
if has.MUA && options.MUA_bpLoHi(2) >= origFs/2
    error('INTAN2MATLAB:MUA_bpNyquist', ...
        'MUA_bpLoHi high edge (%g Hz) must be below origFs/2 (%g Hz).', ...
        options.MUA_bpLoHi(2), origFs/2);
end
if has.SPIKE
    spikeFs = options.SPIKE_Fs;
    if isinf(spikeFs), spikeFs = origFs; end
    if options.SPIKE_bpLoHi(2) >= spikeFs/2
        error('INTAN2MATLAB:SPIKE_bpNyquist', ...
            'SPIKE_bpLoHi high edge (%g Hz) must be below SPIKE_Fs/2 (%g Hz).', ...
            options.SPIKE_bpLoHi(2), spikeFs/2);
    end
end
end