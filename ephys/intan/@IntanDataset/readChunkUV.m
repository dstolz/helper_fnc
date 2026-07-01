function X = readChunkUV(obj, chunk)
%readChunkUV  Read one streaming chunk's amplifier data, in microvolts.
%   X = ds.readChunkUV(chunk) returns a [nSamp x nChan] double matrix of
%   amplifier data in MICROVOLTS for the chunk described by one element of
%   IntanDataset.streamPlan, dispatching on the on-disk layout. All amplifier
%   channels are returned in header order; the caller applies any channel
%   reorder/subset/exclusion (so the per-file channel-count guard in toBin still
%   sees the raw count). An empty result ([] or 0x0) means the chunk held no
%   amplifier data and should be skipped.
%
%   - "rhd"   chunks read a whole traditional *.rhd file via
%             READ_INTAN_RHD2000_FILE_MODIFIED (microvolts = 0.195*(uint16-32768)).
%   - "split" chunks read a sample window from the flat int16 .dat file(s) via
%             IntanDataset.readSplitWindow (microvolts = 0.195*int16).
%   Both produce microvolts on the same scale, so downstream processing is
%   format-agnostic.
%
%   See also IntanDataset.streamPlan, IntanDataset.readSplitWindow,
%   READ_INTAN_RHD2000_FILE_MODIFIED.

arguments
    obj (1,1) IntanDataset
    chunk (1,1) struct
end

switch chunk.kind
    case "rhd"
        S = read_Intan_RHD2000_file_modified(chunk.file, Verbosity="silent");
        if ~isfield(S, 'amplifier_data') || isempty(S.amplifier_data)
            X = zeros(0, 0);
            return
        end
        X = S.amplifier_data.';   % [nSamp x nChan], microvolts

    case "split"
        X = obj.readSplitWindow(chunk.sampleOffset, chunk.nSamples);

    otherwise
        error('IntanDataset:readChunkUV:BadKind', ...
            'Unknown chunk kind "%s".', chunk.kind);
end
end
