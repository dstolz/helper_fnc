function plan = streamPlan(obj, opts)
%streamPlan  Format-agnostic list of streaming chunks for this recording.
%   PLAN = ds.streamPlan() returns a struct array describing the units in which
%   the recording should be read one-at-a-time, so the callers that stream the
%   data (toBin, analyzeArtifacts, the Visualize tab) can share a single loop
%   regardless of the on-disk layout. Each element is read with
%   IntanDataset.readChunkUV.
%
%   For the traditional embedded-data format each *.rhd file is one chunk (the
%   long-standing one-file-in-memory invariant). For the split formats
%   (one-file-per-signal / one-file-per-channel) the single big amplifier .dat is
%   carved into fixed-size sample windows so peak memory stays bounded just as it
%   does for the per-file traditional path.
%
%   Options
%   -------
%     Files            (1,:) string  subset/order of *.rhd files (traditional
%                      only; ignored for split formats, which have one data set).
%     MaxChunkSamples  (1,1) double  cap on samples per split chunk (default:
%                      a memory-budget-derived size, ~250 MB of double).
%
%   Fields per element
%   ------------------
%     kind          "rhd" | "split"
%     name          display label (file name, or "samples a-b")
%     file          full path to the *.rhd file ("" for split chunks)
%     sampleOffset  0-based recording-global sample offset (0 for rhd chunks)
%     nSamples      amplifier samples in this chunk (NaN if header not parsed)
%
%   See also IntanDataset.readChunkUV, IntanDataset.toBin, IntanDataset.readSplitWindow.

arguments
    obj (1,1) IntanDataset
    opts.Files (1,:) string = string.empty(1,0)
    opts.MaxChunkSamples (1,1) double = NaN
end

if isnan(obj.Fs) || isempty(obj.PerFile)
    obj.refreshMetadata();
end

proto = struct('kind', "", 'name', "", 'file', "", ...
    'sampleOffset', 0, 'nSamples', 0);

switch obj.RecordingFormat
    case "traditional"
        if isempty(opts.Files)
            fileList = obj.Files;
        else
            fileList = opts.Files;
        end
        n = numel(fileList);
        plan = repmat(proto, 1, n);
        pfNames = string.empty(1,0);
        if ~isempty(obj.PerFile) && isfield(obj.PerFile, 'name')
            pfNames = string({obj.PerFile.name});
        end
        for i = 1:n
            ns = NaN;
            j = find(pfNames == fileList(i), 1);
            if ~isempty(j); ns = obj.PerFile(j).numAmplifierSamples; end
            plan(i).kind         = "rhd";
            plan(i).name         = fileList(i);
            plan(i).file         = fullfile(obj.Folder, fileList(i));
            plan(i).sampleOffset = 0;
            plan(i).nSamples     = ns;
        end

    case {"one-file-per-signal", "one-file-per-channel"}
        L = obj.splitLayout();
        total = L.nSamp;
        maxc = opts.MaxChunkSamples;
        if isnan(maxc) || maxc <= 0
            % ~250 MB of double per chunk, but never less than ~1 s of data.
            maxc = max(round(L.Fs), floor(2.5e8 / (max(L.nChan, 1) * 8)));
        end
        maxc = max(1, maxc);
        nChunks = max(1, ceil(total / maxc));
        plan = repmat(proto, 1, nChunks);
        for i = 1:nChunks
            off = (i - 1) * maxc;
            len = min(maxc, total - off);
            plan(i).kind         = "split";
            plan(i).name         = sprintf('samples %d-%d', off + 1, off + len);
            plan(i).file         = "";
            plan(i).sampleOffset = off;
            plan(i).nSamples     = len;
        end

    otherwise
        plan = repmat(proto, 1, 0);
end
end
