function refreshMetadata(obj)
%refreshMetadata  Fill header metadata for the recording (no data read).
%   For the traditional format this parses every *.rhd header; for the split
%   formats it parses info.rhd and sizes the recording from the .dat file(s) (see
%   refreshSplitMetadata / splitLayout). The traditional path below:
%   ds.refreshMetadata() parses the header of every file in ds.Files via
%   IntanDataset.parseIntanHeader (header-only; no amplifier matrix is
%   allocated) and populates Fs, NumChannels, ChannelNames, NativeNames,
%   DigInNames, Duration, AcqDate, NumFiles and the PerFile struct array.
%
%   The amplifier channel count is taken from the FIRST file; a hard error is
%   raised if any later file disagrees, because a flat int16 .bin cannot
%   tolerate a mid-dataset channel-count change. Dig-in channel counts follow
%   the first-file policy used by intan2matlab (later extra lines ignored).
%
%   See also IntanDataset.parseIntanHeader, IntanDataset.readData.

arguments
    obj (1,1) IntanDataset
end

obj.discoverFiles();  % re-scan in case files changed on disk

% Split formats (info.rhd + flat .dat files): the header carries no data
% blocks, so amplifier sample counts come from the .dat file size(s) resolved by
% splitLayout, not from parseIntanHeader's block count.
if obj.RecordingFormat == "one-file-per-signal" || ...
        obj.RecordingFormat == "one-file-per-channel"
    refreshSplitMetadata(obj);
    return
end

if obj.NumFiles == 0
    warning('IntanDataset:refreshMetadata:NoFiles', ...
        'No *.rhd files found in %s', obj.Folder);
    return
end

pf = struct('name', {}, 'bytesPerBlock', {}, 'numDataBlocks', {}, ...
    'numAmplifierSamples', {}, 'recordTime', {}, 'numAmplifierChannels', {}, ...
    'numBoardDigIn', {}, 'headerBytes', {}, 'datenum', {}, 'partialBlock', {}, ...
    'dataPresent', {});

firstNumChan = NaN;
for i = 1:obj.NumFiles
    ffn = fullfile(obj.Folder, obj.Files(i));
    hdr = IntanDataset.parseIntanHeader(ffn);

    if i == 1
        firstNumChan = hdr.numAmplifierChannels;
        obj.Fs           = hdr.sampleRate;
        obj.NumChannels  = hdr.numAmplifierChannels;
        obj.ChannelNames = hdr.channelNames;
        obj.NativeNames  = hdr.nativeNames;
        obj.DigInNames   = hdr.digInNames;
    elseif hdr.numAmplifierChannels ~= firstNumChan
        error('IntanDataset:refreshMetadata:ChannelMismatch', ...
            ['Amplifier channel count changed mid-dataset (%d -> %d) at %s. ', ...
             'A flat int16 .bin cannot represent this; split the recording.'], ...
            firstNumChan, hdr.numAmplifierChannels, obj.Files(i));
    end

    if hdr.partialBlock
        warning('IntanDataset:refreshMetadata:PartialBlock', ...
            'Truncated trailing data block in %s; only whole blocks counted.', obj.Files(i));
    end

    pf(i) = struct('name', hdr.name, 'bytesPerBlock', hdr.bytesPerBlock, ...
        'numDataBlocks', hdr.numDataBlocks, ...
        'numAmplifierSamples', hdr.numAmplifierSamples, ...
        'recordTime', hdr.recordTime, ...
        'numAmplifierChannels', hdr.numAmplifierChannels, ...
        'numBoardDigIn', hdr.numBoardDigInChannels, ...
        'headerBytes', hdr.headerBytes, 'datenum', hdr.datenum, ...
        'partialBlock', hdr.partialBlock, 'dataPresent', hdr.dataPresent);
end

obj.PerFile  = pf;
obj.Duration = sum([pf.recordTime]);
obj.AcqDate  = datetime(min([pf.datenum]), 'ConvertFrom', 'datenum');

if ~isempty(obj.Manifest) && isa(obj.Manifest, 'Manifest')
    obj.Manifest.add("metadata", "Parsed Intan headers", ...
        struct('folder', obj.Folder, 'numFiles', obj.NumFiles, ...
        'fs', obj.Fs, 'numChannels', obj.NumChannels, ...
        'duration', obj.Duration));
end
end


% =========================================================================
function refreshSplitMetadata(obj)
%refreshSplitMetadata  Fill metadata for a split-format recording.
%   Parses info.rhd for header fields and derives the amplifier sample count
%   from the .dat file size(s) (the header has no data blocks). Mirrors the
%   PerFile summary the traditional path builds, with a single entry standing in
%   for the whole recording, so downstream code (NumSamples, the GUI tables,
%   onPlotVisualization) is unchanged.
L = obj.splitLayout();

obj.Fs           = L.Fs;
obj.NumChannels  = L.nChan;
obj.ChannelNames = L.ampCustom;
obj.NativeNames  = L.ampNative;
obj.DigInNames   = L.digInNames;

nSamp = L.nSamp;
obj.PerFile = struct( ...
    'name',                 "info.rhd", ...
    'bytesPerBlock',        NaN, ...
    'numDataBlocks',        NaN, ...
    'numAmplifierSamples',  nSamp, ...
    'recordTime',           nSamp / L.Fs, ...
    'numAmplifierChannels', L.nChan, ...
    'numBoardDigIn',        numel(L.digInNames), ...
    'headerBytes',          NaN, ...
    'datenum',              L.ampDatenum, ...
    'partialBlock',         false, ...
    'dataPresent',          nSamp > 0);

obj.Duration = nSamp / L.Fs;
obj.AcqDate  = datetime(L.ampDatenum, 'ConvertFrom', 'datenum');

if ~isempty(obj.Manifest) && isa(obj.Manifest, 'Manifest')
    obj.Manifest.add("metadata", "Parsed Intan split-format header", ...
        struct('folder', obj.Folder, 'format', obj.RecordingFormat, ...
        'fs', obj.Fs, 'numChannels', obj.NumChannels, ...
        'duration', obj.Duration));
end
end
