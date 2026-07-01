function data = readSplitAll(obj, opts)
%readSplitAll  readData implementation for the split Intan recording formats.
%   DATA = ds.readSplitAll(opts) reads a "one-file-per-signal" or "one-file-per-
%   channel" recording into the SAME output struct shape produced by
%   IntanDataset.readData for the traditional format, so callers do not care
%   which layout a folder uses. readData delegates here whenever the recording is
%   not traditional; see readData for the option and field documentation.
%
%   Supported per layout
%   --------------------
%     amplifier (microvolts) and digital-input events are read for BOTH split
%     layouts. Board ADC and aux input are read only for one-file-per-signal
%     (the well-defined analogin.dat / auxiliary.dat); for one-file-per-channel
%     they return [] (the per-channel ADC/aux files are not yet mapped). Digital
%     events for one-file-per-channel are read from board-DIN-<order>.dat when
%     those files are present, and are otherwise empty.
%
%   See also IntanDataset.readData, IntanDataset.splitLayout,
%   IntanDataset.readSplitWindow.

arguments
    obj (1,1) IntanDataset
    opts.Files (1,:) string = string.empty(1,0)  %#ok<INUSA> (no per-file split units)
    opts.KeepChannels (1,:) double {mustBeInteger, mustBePositive} = []
    opts.IncludeADC (1,1) logical = false
    opts.IncludeAux (1,1) logical = false
    opts.Concatenate (1,1) logical = true
    opts.ProgressFcn = []
end

if isnan(obj.Fs) || isempty(obj.PerFile)
    obj.refreshMetadata();
end
L  = obj.splitLayout();
Fs = L.Fs;

if ~isempty(opts.ProgressFcn)
    opts.ProgressFcn(1, 1, "info.rhd");
end

% --- Amplifier (whole recording; readData concatenates everything anyway) -----
X = obj.readSplitWindow(0, L.nSamp);   % [nSamp x nChan], microvolts
keep = opts.KeepChannels;
if ~isempty(keep)
    if max(keep) > size(X, 2)
        error('IntanDataset:readSplitAll:BadKeepChannels', ...
            'KeepChannels references channel %d but recording has %d.', ...
            max(keep), size(X, 2));
    end
    X = X(:, keep);
    channelNames = L.ampCustom(keep);
    nativeNames  = L.ampNative(keep);
else
    channelNames = L.ampCustom;
    nativeNames  = L.ampNative;
end
nSamp = size(X, 1);

% --- Digital-input events -----------------------------------------------------
[events, digInNames, digData] = readSplitDigital(L, nSamp, Fs);

% --- Optional board ADC / aux (one-file-per-signal only) ----------------------
boardADC = [];
aux      = [];
auxFs    = NaN;
if opts.IncludeADC
    boardADC = readSplitADC(L, nSamp);
end
if opts.IncludeAux
    [aux, auxFs] = readSplitAux(L);
end

% --- Assemble (identical fields/orientation to readData) ----------------------
if opts.Concatenate
    amplifier = X;
    t = (0:nSamp-1).' / Fs;
else
    amplifier = {X};
    digData   = {digData}; %#ok<NASGU> (non-concatenated callers ignore events)
    t = [];
end

data = struct();
data.amplifier        = amplifier;
data.Fs               = Fs;
data.t                = t;
data.channelNames     = channelNames;
data.nativeNames      = nativeNames;
if isempty(keep)
    data.channelOrder = 1:numel(channelNames);
else
    data.channelOrder = keep;
end
data.events           = events;
data.digInNames       = digInNames;
data.boardADC         = boardADC;
data.aux              = aux;
data.auxFs            = auxFs;
data.files            = obj.Files;
data.fileSampleCounts = nSamp;
data.units            = "microvolts";
data.source           = struct('Folder', obj.Folder, 'Name', obj.Name);
end


% =========================================================================
function [events, digInNames, digData] = readSplitDigital(L, nSamp, Fs)
%readSplitDigital  Decode dig-in lines into per-line [nSamp x nLine] + events.
events     = struct();
digInNames = L.digInNames;
nLine      = numel(digInNames);
digData    = zeros(nSamp, max(nLine, 0));

if nLine == 0
    return
end

switch L.format
    case "one-file-per-signal"
        if L.digInFile == "" || ~isfile(L.digInFile)
            digInNames = string.empty(1,0);
            digData    = zeros(nSamp, 0);
            return
        end
        raw = readDatVector(L.digInFile, nSamp, 'uint16');   % [n x 1] packed bits
        for j = 1:nLine
            bit = L.digInOrders(j);
            digData(1:numel(raw), j) = double(bitand(uint32(raw), 2^bit) > 0);
        end

    case "one-file-per-channel"
        if isempty(L.digInFiles) || ~all(arrayfun(@(f) isfile(f), L.digInFiles))
            digInNames = string.empty(1,0);
            digData    = zeros(nSamp, 0);
            return
        end
        for j = 1:nLine
            raw = readDatVector(L.digInFiles(j), nSamp, 'uint16');
            digData(1:numel(raw), j) = double(raw > 0);
        end
end

names = matlab.lang.makeValidName(cellstr(digInNames));
for j = 1:numel(names)
    events.(names{j}) = highSegments(digData(:, j), Fs);
end
end


function adc = readSplitADC(L, nSamp)
%readSplitADC  Board ADC (volts), one-file-per-signal only; [] otherwise.
adc = [];
if L.format ~= "one-file-per-signal" || L.numADC <= 0
    return
end
if L.adcFile == "" || ~isfile(L.adcFile)
    return
end
fid = fopen(char(L.adcFile), 'r', 'ieee-le');
if fid < 0; return; end
raw = fread(fid, [L.numADC, nSamp], 'uint16=>double');   % [nADC x n]
fclose(fid);
raw = raw.';                                             % [n x nADC]
if L.boardMode == 1
    adc = 152.59e-6 * (raw - 32768);
elseif L.boardMode == 13
    adc = 312.5e-6 * (raw - 32768);
else
    adc = 50.354e-6 * raw;
end
end


function [aux, auxFs] = readSplitAux(L)
%readSplitAux  Aux input (volts, Fs/4), one-file-per-signal only; [] otherwise.
aux   = [];
auxFs = NaN;
if L.format ~= "one-file-per-signal" || L.numAux <= 0
    return
end
if L.auxFile == "" || ~isfile(L.auxFile)
    return
end
d = dir(char(L.auxFile));
nAuxSamp = floor(d.bytes / (2 * L.numAux));
fid = fopen(char(L.auxFile), 'r', 'ieee-le');
if fid < 0; return; end
raw = fread(fid, [L.numAux, nAuxSamp], 'uint16=>double');
fclose(fid);
aux   = 37.4e-6 * raw.';      % [n x nAux], volts
auxFs = L.Fs / 4;
end


function v = readDatVector(file, nSamp, prec)
%readDatVector  Read up to nSamp values from a flat .dat file as a column.
fid = fopen(char(file), 'r', 'ieee-le');
if fid < 0
    v = zeros(0, 1);
    return
end
v = fread(fid, nSamp, [prec '=>double']);
fclose(fid);
end


function iv = highSegments(x, Fs)
%highSegments  [k x 2] [t_on t_off] (s) for contiguous high runs of x.
%   Mirrors the helper in readData so split-format events use the same
%   intan2matlab-compatible onset/offset convention.
x = x(:) > 0;
if license('test', 'Image_Toolbox') && exist('bwlabel', 'file')
    ev = bwlabel(x);
    u  = unique(ev(ev > 0));
    if isempty(u); iv = zeros(0, 2); return; end
    on  = arrayfun(@(a) find(ev == a, 1, 'first'), u);
    off = arrayfun(@(a) find(ev == a, 1, 'last'),  u);
    iv  = [on off] ./ Fs;
else
    d = diff([0; x; 0]);
    on  = find(d == 1);
    off = find(d == -1) - 1;
    if isempty(on); iv = zeros(0, 2); else; iv = [on off] ./ Fs; end
end
end
