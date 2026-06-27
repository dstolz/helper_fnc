function refreshMetadata(obj)
%refreshMetadata  Fill header metadata from each *.rhd file (no data read).
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
