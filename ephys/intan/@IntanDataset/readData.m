function data = readData(obj, opts)
%readData  Read amplifier (and optional ADC/aux) data into one struct.
%   DATA = ds.readData() reads every *.rhd file in chronological order via
%   READ_INTAN_RHD2000_FILE_MODIFIED, transposes each amplifier matrix to
%   [nSamples x nChan], concatenates in time, and extracts digital-input
%   events. The returned struct uses [nSamples x nChan] orientation throughout
%   (matching MATRIX2KILOSORT and EXTRACT_TRIALS).
%
%   DATA = ds.readData(opts) with name-value options:
%     Files        (1,:) string  subset/order of file names to read (default: all)
%     KeepChannels (1,:) double   1-based amplifier channels to keep (default: all)
%     IncludeADC   (1,1) logical  also return board ADC data (default false)
%     IncludeAux   (1,1) logical  also return aux input data (default false)
%     Concatenate  (1,1) logical  concatenate files in time (default true)
%     ProgressFcn  function handle  called before each file as
%                  ProgressFcn(i, nFiles, fileName) for progress reporting
%                  (default: none)
%
%   Output struct fields
%   --------------------
%     amplifier      [nSamples x nChan] double, microvolts
%     Fs             amplifier sample rate (Hz)
%     t              [nSamples x 1] time vector (s)
%     channelNames / nativeNames / channelOrder
%     events         struct, one field per dig-in line -> [k x 2] [t_on t_off] (s)
%     digInNames
%     boardADC / aux / auxFs   (or [] when not requested/present)
%     files          string array of files read (chronological)
%     fileSampleCounts  per-file amplifier sample counts
%     units          "microvolts"
%     source         struct with Folder/Name
%
%   Digital events follow intan2matlab: the dig-in channel count is fixed from
%   the FIRST file (later extra lines are ignored), contiguous high segments
%   are labelled with bwlabel (diff-based fallback if Image Processing Toolbox
%   is unavailable), and times are reported in seconds on the original Fs grid.
%
%   See also READ_INTAN_RHD2000_FILE_MODIFIED, MATRIX2KILOSORT, EXTRACT_TRIALS.

arguments
    obj (1,1) IntanDataset
    opts.Files (1,:) string = string.empty(1,0)
    opts.KeepChannels (1,:) double {mustBeInteger, mustBePositive} = []
    opts.IncludeADC (1,1) logical = false
    opts.IncludeAux (1,1) logical = false
    opts.Concatenate (1,1) logical = true
    opts.ProgressFcn = []
end

if obj.NumFiles == 0
    obj.discoverFiles();
end
if obj.NumFiles == 0
    error('IntanDataset:readData:NoFiles', 'No *.rhd files in %s', obj.Folder);
end

% Resolve which files to read (chronological order preserved unless overridden)
if isempty(opts.Files)
    fileList = obj.Files;
else
    fileList = opts.Files;
end
nFiles = numel(fileList);

AMP   = cell(1, nFiles);
ADC   = cell(1, nFiles);
AUX   = cell(1, nFiles);
digCell = cell(1, nFiles);
fileSampleCounts = zeros(1, nFiles);

channelNames = string.empty(1,0);
nativeNames  = string.empty(1,0);
digInNames   = string.empty(1,0);
Fs    = NaN;
auxFs = NaN;
ndid  = 0;  % dig-in line count fixed from first file (intan2matlab policy)

for i = 1:nFiles
    if ~isempty(opts.ProgressFcn)
        opts.ProgressFcn(i, nFiles, fileList(i));
    end
    ffn = fullfile(obj.Folder, fileList(i));
    S = read_Intan_RHD2000_file_modified(ffn, Verbosity="silent");

    if ~isfield(S, 'amplifier_data') || isempty(S.amplifier_data)
        warning('IntanDataset:readData:NoData', ...
            'No amplifier data in %s; skipping.', fileList(i));
        AMP{i} = zeros(0, 0);
        digCell{i} = zeros(0, ndid);
        continue
    end

    X = S.amplifier_data.';  % [nSamples x nChan], microvolts

    if ~isempty(opts.KeepChannels)
        if max(opts.KeepChannels) > size(X, 2)
            error('IntanDataset:readData:BadKeepChannels', ...
                'KeepChannels references channel %d but file has %d.', ...
                max(opts.KeepChannels), size(X, 2));
        end
        X = X(:, opts.KeepChannels);
    end

    AMP{i} = X;
    fileSampleCounts(i) = size(X, 1);

    if i == 1
        Fs = S.frequency_parameters.amplifier_sample_rate;
        if isempty(opts.KeepChannels)
            channelNames = string({S.amplifier_channels.custom_channel_name});
            nativeNames  = string({S.amplifier_channels.native_channel_name});
        else
            channelNames = string({S.amplifier_channels(opts.KeepChannels).custom_channel_name});
            nativeNames  = string({S.amplifier_channels(opts.KeepChannels).native_channel_name});
        end
        if isfield(S, 'board_dig_in_data') && ~isempty(S.board_dig_in_data)
            ndid = size(S.board_dig_in_data, 1);
            digInNames = string({S.board_dig_in_channels.custom_channel_name});
            digInNames = digInNames(1:ndid);
        end
        if opts.IncludeAux && isfield(S, 'aux_input_data') && ~isempty(S.aux_input_data)
            auxFs = S.frequency_parameters.aux_input_sample_rate;
        end
    end

    % Dig-in (use first-file line count only)
    if ndid > 0 && isfield(S, 'board_dig_in_data') && ~isempty(S.board_dig_in_data)
        digCell{i} = S.board_dig_in_data(1:ndid, :).';  % [nSamples x ndid]
    else
        digCell{i} = zeros(size(X, 1), ndid);
    end

    if opts.IncludeADC && isfield(S, 'board_adc_data') && ~isempty(S.board_adc_data)
        ADC{i} = S.board_adc_data.';
    end
    if opts.IncludeAux && isfield(S, 'aux_input_data') && ~isempty(S.aux_input_data)
        AUX{i} = S.aux_input_data.';
    end
end

% Concatenate
if opts.Concatenate
    amplifier = cat(1, AMP{:});
    digData   = cat(1, digCell{:});
    boardADC  = ternaryCat(opts.IncludeADC, ADC);
    aux       = ternaryCat(opts.IncludeAux, AUX);
else
    amplifier = AMP;
    digData   = digCell;
    boardADC  = ADC;
    aux       = AUX;
end

% Build events from concatenated dig lines (seconds on Fs grid)
events = struct();
if opts.Concatenate && ndid > 0 && ~isempty(digData)
    names = matlab.lang.makeValidName(cellstr(digInNames));
    for j = 1:ndid
        events.(names{j}) = highSegments(digData(:, j), Fs);
    end
end

if opts.Concatenate
    nTot = size(amplifier, 1);
    t = (0:nTot-1).' / Fs;
else
    t = [];
end

data = struct();
data.amplifier        = amplifier;
data.Fs               = Fs;
data.t                = t;
data.channelNames     = channelNames;
data.nativeNames      = nativeNames;
data.channelOrder     = resolveOrder(opts.KeepChannels, numel(channelNames));
data.events           = events;
data.digInNames       = digInNames;
data.boardADC         = boardADC;
data.aux              = aux;
data.auxFs            = auxFs;
data.files            = fileList;
data.fileSampleCounts = fileSampleCounts;
data.units            = "microvolts";
data.source           = struct('Folder', obj.Folder, 'Name', obj.Name);
end


function ord = resolveOrder(keep, n)
if isempty(keep)
    ord = 1:n;
else
    ord = keep;
end
end


function out = ternaryCat(flag, C)
if flag && ~all(cellfun(@isempty, C))
    out = cat(1, C{:});
else
    out = [];
end
end


function iv = highSegments(x, Fs)
%highSegments  Return [k x 2] [t_on t_off] (s) for contiguous high runs of x.
x = x(:) > 0;
if license('test', 'Image_Toolbox') && exist('bwlabel', 'file')
    ev = bwlabel(x);
    u  = unique(ev(ev > 0));
    if isempty(u)
        iv = zeros(0, 2);
        return
    end
    on  = arrayfun(@(a) find(ev == a, 1, 'first'), u);
    off = arrayfun(@(a) find(ev == a, 1, 'last'),  u);
    iv  = [on off] ./ Fs;
else
    % diff-based fallback (no Image Processing Toolbox)
    d = diff([0; x; 0]);
    on  = find(d == 1);
    off = find(d == -1) - 1;
    if isempty(on)
        iv = zeros(0, 2);
    else
        iv = [on off] ./ Fs;
    end
end
end
