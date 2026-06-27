function info = matrixToBin(obj, X, opts)
%matrixToBin  Write an already-in-memory matrix to a Kilosort4 .bin (delegates).
%   INFO = ds.matrixToBin(X) writes the [nSamples x nChan] matrix X (microvolts,
%   as returned by readData) to ds.BinFile by delegating to MATRIX2KILOSORT,
%   using the dataset's Scale/Dtype/Fs defaults. This is the in-memory
%   counterpart to the streaming ds.toBin path; for the same data and options
%   the two produce a byte-identical file.
%
%   Options
%   -------
%     BinFile        (1,1) string  output path (default ds.BinFile)
%     Scale          (1,1) double  default ds.Scale
%     Offset         (1,1) double  default 0
%     Dtype          string        default ds.Dtype
%     Fs             (1,1) double  default ds.Fs
%     ChannelOrder   (1,:) double  1-based reorder/subset
%     ChannelsAreRows logical      true if X is [nChan x nSamples] (default false)
%     WriteMeta      logical       default true
%
%   See also MATRIX2KILOSORT, IntanDataset.toBin, IntanDataset.readData.

arguments
    obj (1,1) IntanDataset
    X {mustBeReal, mustBeNonempty}
    opts.BinFile (1,1) string = ""
    opts.Scale (1,1) double = NaN
    opts.Offset (1,1) double = 0
    opts.Dtype (1,1) string = ""
    opts.Fs (1,1) double = NaN
    opts.ChannelOrder (1,:) double {mustBeInteger, mustBePositive} = []
    opts.ChannelsAreRows (1,1) logical = false
    opts.WriteMeta (1,1) logical = true
end

binFile = opts.BinFile; if binFile == ""; binFile = obj.BinFile; end
scale   = opts.Scale;   if isnan(scale); scale = obj.Scale; end
dtype   = opts.Dtype;   if dtype == "";  dtype = obj.Dtype; end
Fs      = opts.Fs;      if isnan(Fs);    Fs = obj.Fs; end

outDir = fileparts(char(binFile));
if outDir ~= "" && ~isfolder(outDir)
    mkdir(outDir);
end

info = matrix2kilosort(X, binFile, fs=Fs, dtype=dtype, scale=scale, ...
    offset=opts.Offset, channelOrder=opts.ChannelOrder, ...
    channelsAreRows=opts.ChannelsAreRows, writeMeta=opts.WriteMeta);

if ~isempty(obj.Manifest) && isa(obj.Manifest, 'Manifest')
    obj.Manifest.add("matrixToBin", "Wrote Kilosort4 .bin (in-memory)", ...
        struct('binFile', info.filename, 'nChan', info.nChan, ...
        'nSamples', info.nSamples, 'fs', info.fs));
end
end
