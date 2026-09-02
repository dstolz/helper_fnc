function X = readSplitWindow(obj, sampleOffset, nSamp)
%readSplitWindow  Read an amplifier sample window from a split-format recording.
%   X = ds.readSplitWindow(sampleOffset, nSamp) returns a [nSamp x nChan] double
%   matrix of amplifier data in MICROVOLTS for the recording-global sample range
%   [sampleOffset+1 : sampleOffset+nSamp], reading directly from the flat int16
%   .dat file(s) described by ds.splitLayout. This is the streaming primitive
%   behind toBin / analyzeArtifacts / the Visualize tab for the "one-file-per-
%   signal" and "one-file-per-channel" layouts; only the requested window is held
%   in memory, so peak usage never scales with the whole recording length.
%
%   Scaling mirrors the Intan convention for the split formats: microvolts =
%   0.195 * int16 (the on-disk samples are already centered; there is no 32768
%   offset, unlike the offset-binary uint16 stored in traditional *.rhd blocks).
%   Channels are returned in header order (the same order used by NumChannels /
%   ChannelNames and by toBin's .bin rows); apply any ChannelOrder/exclusion at
%   the call site, exactly as for the traditional reader.
%
%   A short final window (fewer samples on disk than requested) returns only the
%   rows actually present.
%
%   See also IntanDataset.splitLayout, IntanDataset.readChunkUV, IntanDataset.toBin.

arguments
    obj (1,1) IntanDataset
    sampleOffset (1,1) double {mustBeInteger, mustBeNonnegative}
    nSamp (1,1) double {mustBeInteger, mustBeNonnegative}
end

L = obj.splitLayout();
nChan = L.nChan;

if nSamp == 0
    X = zeros(0, nChan);
    return
end

switch L.format
    case "one-file-per-signal"
        fid = fopen(char(L.ampFile), 'r', 'ieee-le');
        if fid < 0
            error('IntanDataset:readSplitWindow:OpenFailed', ...
                'Could not open %s', L.ampFile);
        end
        closer = onCleanup(@() fclose(fid));
        if fseek(fid, sampleOffset * nChan * 2, 'bof') ~= 0
            error('IntanDataset:readSplitWindow:SeekFailed', ...
                'Could not seek to sample %d in %s', sampleOffset, L.ampFile);
        end
        raw = fread(fid, [nChan, nSamp], 'int16=>double');  % [nChan x got]
        X = 0.195 * raw.';                                  % [got x nChan] uV

    case "one-file-per-channel"
        X = zeros(nSamp, nChan);
        got = nSamp;
        for k = 1:nChan
            fid = fopen(char(L.ampFiles(k)), 'r', 'ieee-le');
            if fid < 0
                error('IntanDataset:readSplitWindow:OpenFailed', ...
                    'Could not open %s', L.ampFiles(k));
            end
            if fseek(fid, sampleOffset * 2, 'bof') ~= 0
                fclose(fid);
                error('IntanDataset:readSplitWindow:SeekFailed', ...
                    'Could not seek to sample %d in %s', sampleOffset, L.ampFiles(k));
            end
            col = fread(fid, nSamp, 'int16=>double');
            fclose(fid);
            got = min(got, numel(col));
            X(1:numel(col), k) = 0.195 * col;
        end
        if got < nSamp                 % trim to the shortest channel actually read
            X = X(1:got, :);
        end

    otherwise
        error('IntanDataset:readSplitWindow:NotSplit', ...
            'readSplitWindow only applies to split formats (got "%s").', L.format);
end
end
