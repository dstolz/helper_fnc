function info = matrix2kilosort(X, binFile, options)
%MATRIX2KILOSORT  Write a continuous multichannel signal to a Kilosort4 .bin file.
%   INFO = MATRIX2KILOSORT(X, BINFILE) writes the continuous, multichannel
%   matrix X to a flat binary file BINFILE in the layout expected by
%   Kilosort4: int16 samples, little-endian, with no header, and with the
%   channel index varying fastest on disk (i.e. for every time sample all
%   channels are stored contiguously). This is the format Kilosort4 reads
%   when its settings specify n_chan_bin = nChan and dtype = 'int16'.
%
%   INFO = MATRIX2KILOSORT(X, BINFILE, OPTIONS) overrides the defaults below.
%
%   Inputs
%   ------
%   X        [nSamples x nChan] real numeric array (single/double/integer).
%            Time runs down the rows and channels across the columns, matching
%            the orientation produced by INTAN2MATLAB (Y.SPIKE, Y.LFP, ...) and
%            consumed by EXTRACT_TRIALS. Set options.channelsAreRows = true if
%            your data is instead [nChan x nSamples].
%
%   BINFILE  Output path (string/char). If no extension is given, ".bin" is
%            appended. The parent folder must already exist.
%
%   Output
%   ------
%   INFO     struct describing what was written, with fields:
%              .filename   full path to the .bin file
%              .dtype      on-disk class (e.g. 'int16')
%              .nChan      number of channels written (n_chan_bin)
%              .nSamples   number of time samples per channel
%              .fs         sampling rate in Hz (NaN if not provided)
%              .scale      scale factor applied before casting
%              .offset     offset added after scaling
%              .byteOrder  'little-endian'
%              .nClipped   count of samples saturated to the integer range
%              .nBytes     size of the written file in bytes
%              .metaFile   path to the JSON sidecar (if options.writeMeta)
%
%   Options (name-value via ARGUMENTS)
%   ----------------------------------
%   options.fs               scalar Hz        NaN
%       Sampling rate, stored in the JSON sidecar and INFO for convenience.
%       Set this to the value you will pass to Kilosort4 (settings['fs']).
%
%   options.dtype            string           "int16"
%       On-disk sample class. One of "int16" (Kilosort4 default), "uint16",
%       "int32", or "single"/"float32". Integer classes round to nearest and
%       saturate; saturated samples are counted in INFO.nClipped.
%
%   options.scale            scalar           1
%       Multiplier applied to the data before casting (data .* scale + offset).
%       Use this to map your units into the integer range while preserving
%       resolution. For Intan amplifier data already converted to microvolts
%       (0.195 uV/bit), use scale = 1/0.195 (~5.1282) to restore the native
%       int16 ADC resolution. The absolute scale does not affect sorting
%       (Kilosort whitens), but it must keep samples within the dtype range.
%
%   options.offset           scalar           0
%       Constant added after scaling (data .* scale + offset). Typically 0 for
%       int16; for uint16 you may want offset = 32768.
%
%   options.channelsAreRows  logical          false
%       Set true if X is [nChan x nSamples] instead of [nSamples x nChan].
%
%   options.channelOrder     integer vector   []
%       Optional 1-based channel ordering applied before writing, so the
%       on-disk channel order matches your Kilosort probe/channel map. May
%       select a subset and/or reorder; INFO.nChan reflects numel(channelOrder).
%
%   options.chunkSamples     integer          [] (auto)
%       Number of time samples written per fwrite call. Bounds peak memory for
%       long recordings. When empty, a value targeting ~128 MB per chunk is
%       chosen from nChan.
%
%   options.writeMeta        logical          true
%       Also write a JSON sidecar next to the .bin (same name, ".json") holding
%       n_chan_bin, fs, dtype, n_samples and byte order for bookkeeping.
%       Kilosort4 does not read this file; it is a record for you.
%
%   Notes
%   -----
%   * Kilosort4 needs three things to load raw data: this binary file, the
%     channel count (n_chan_bin = INFO.nChan), and the sampling rate (fs). It
%     additionally needs a probe/channel-map file to actually run sorting. This
%     function writes only the data file, as requested.
%   * The file has no header. Total size = nChan * nSamples * bytesPerSample.
%   * Bytes are written little-endian to match Kilosort/NumPy on typical x86
%     platforms, regardless of the host machine's native byte order.
%
%   Example
%   -------
%     % Y.SPIKE is [nSamples x nChan] single, in microvolts, at info.origFs
%     [Y,~,I] = intan2matlab(rhdFolder, dataTypeOut="SPIKE");
%     ks = matrix2kilosort(Y.SPIKE, "recording.bin", ...
%                          fs=I.SPIKE.Fs, scale=1/0.195);
%     % In Kilosort4: settings = {'n_chan_bin': ks.nChan, 'fs': ks.fs}
%
%   See also INTAN2MATLAB, EXTRACT_TRIALS, FWRITE, FOPEN, CAST

arguments
    X {mustBeReal, mustBeNonempty}
    binFile (1,1) string
    options.fs (1,1) double = NaN   % positive Hz, or NaN if unspecified
    options.dtype (1,1) string {mustBeMember(options.dtype, ...
        ["int16","uint16","int32","single","float32"])} = "int16"
    options.scale (1,1) double {mustBeFinite} = 1
    options.offset (1,1) double {mustBeFinite} = 0
    options.channelsAreRows (1,1) logical = false
    options.channelOrder (1,:) double {mustBeInteger, mustBePositive} = []
    options.chunkSamples double {mustBeScalarOrEmpty, mustBeInteger, mustBePositive} = []
    options.writeMeta (1,1) logical = true
end

if ~ismatrix(X)
    error('MATRIX2KILOSORT:NotMatrix', ...
        'X must be a 2-D matrix; got a %d-D array.', ndims(X));
end
if ~isnan(options.fs) && options.fs <= 0
    error('MATRIX2KILOSORT:BadFs', 'options.fs must be a positive sampling rate (Hz).');
end

% Resolve sizes from orientation
if options.channelsAreRows
    [nChan, nSamples] = size(X);
else
    [nSamples, nChan] = size(X);
end

% Resolve channel ordering / subset
if isempty(options.channelOrder)
    chOrder = 1:nChan;
else
    if max(options.channelOrder) > nChan
        error('MATRIX2KILOSORT:BadChannelOrder', ...
            'options.channelOrder references channel %d but X has only %d channels.', ...
            max(options.channelOrder), nChan);
    end
    chOrder = options.channelOrder;
end
nChanOut = numel(chOrder);

% Map dtype -> MATLAB class + saturation range
switch options.dtype
    case "int16"
        targetClass = 'int16';  isFloat = false;  lo = -32768;       hi = 32767;
    case "uint16"
        targetClass = 'uint16'; isFloat = false;  lo = 0;            hi = 65535;
    case "int32"
        targetClass = 'int32';  isFloat = false;  lo = -2147483648;  hi = 2147483647;
    otherwise % "single" or "float32"
        targetClass = 'single'; isFloat = true;   lo = -inf;         hi = inf;
end

% Resolve chunk size (target ~128 MB of double per chunk)
if isempty(options.chunkSamples)
    chunkSamples = max(1e4, floor(16e6 / max(nChanOut,1)));
else
    chunkSamples = options.chunkSamples;
end
chunkSamples = min(chunkSamples, nSamples);

% Resolve output path / extension
[outDir, outName, outExt] = fileparts(binFile);
if outExt == ""
    outExt = ".bin";
    binFile = fullfile(outDir, outName + outExt);
end
if outDir ~= "" && ~isfolder(outDir)
    error('MATRIX2KILOSORT:NoFolder', 'Output folder does not exist: %s', outDir);
end

% Open little-endian to match Kilosort/NumPy regardless of host byte order
fid = fopen(binFile, 'w', 'ieee-le');
if fid < 0
    error('MATRIX2KILOSORT:OpenFailed', 'Could not open %s for writing.', binFile);
end

nClipped = 0;
nWritten = 0;
nChunks  = ceil(nSamples / chunkSamples);

fprintf('Writing %d channels x %d samples to %s ...\n', nChanOut, nSamples, binFile);
try
    for c = 1:nChunks
        s0 = (c-1)*chunkSamples + 1;
        s1 = min(c*chunkSamples, nSamples);

        % Extract chunk as [nChan x L] (channel fastest for fwrite)
        if options.channelsAreRows
            blk = X(chOrder, s0:s1);
        else
            blk = X(s0:s1, chOrder).';
        end

        % Scale/offset in double, then count saturation before casting
        blk = options.scale .* double(blk) + options.offset;
        if ~isFloat
            nClipped = nClipped + nnz(blk < lo | blk > hi);
        end
        blk = cast(blk, targetClass); % rounds + saturates for integer classes

        % fwrite is column-major => writes all channels of each sample
        % contiguously (channel varies fastest), as Kilosort4 expects.
        nWritten = nWritten + fwrite(fid, blk, targetClass);
    end
catch ME
    fclose(fid);
    rethrow(ME);
end
fclose(fid);

% Sanity check on element count
nExpected = nChanOut * nSamples;
if nWritten ~= nExpected
    warning('MATRIX2KILOSORT:ShortWrite', ...
        'Wrote %d of %d expected samples; the file may be incomplete (disk full?).', ...
        nWritten, nExpected);
end

if nClipped > 0
    warning('MATRIX2KILOSORT:Clipping', ...
        ['%d sample(s) (%.4f%%) saturated the %s range and were clipped. ', ...
         'Adjust options.scale/options.offset to avoid clipping.'], ...
        nClipped, 100*nClipped/nExpected, options.dtype);
end

if isnan(options.fs)
    warning('MATRIX2KILOSORT:NoFs', ...
        'options.fs was not provided; set it to the rate you will give Kilosort4 (settings.fs).');
end

% Package info
d = dir(binFile);
info = struct();
info.filename  = char(binFile);
info.dtype     = char(options.dtype);
info.nChan     = nChanOut;
info.nSamples  = nSamples;
info.fs        = options.fs;
info.scale     = options.scale;
info.offset    = options.offset;
info.byteOrder = 'little-endian';
info.nClipped  = nClipped;
info.nBytes    = d.bytes;

% Optional JSON sidecar (bookkeeping; Kilosort4 does not read it)
if options.writeMeta
    meta = struct('n_chan_bin', nChanOut, 'fs', options.fs, ...
        'dtype', char(options.dtype), 'n_samples', nSamples, ...
        'byte_order', 'little-endian', 'scale', options.scale, ...
        'offset', options.offset, 'bin_file', char(binFile), ...
        'created', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
    metaFile = fullfile(outDir, outName + ".json");
    try
        txt = jsonencode(meta, 'PrettyPrint', true);
    catch
        txt = jsonencode(meta);
    end
    fidm = fopen(metaFile, 'w');
    if fidm < 0
        warning('MATRIX2KILOSORT:MetaWriteFailed', 'Could not write metadata to %s', metaFile);
    else
        fwrite(fidm, txt, 'char');
        fclose(fidm);
        info.metaFile = char(metaFile);
    end
end

fprintf('Done. %.2f MB written (%s, little-endian).\n', info.nBytes/1e6, info.dtype);
if ~isnan(options.fs)
    fprintf('Kilosort4 settings: n_chan_bin = %d, fs = %g\n', nChanOut, options.fs);
end
