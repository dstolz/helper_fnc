function mask = manualArtifactMask(obj, nSamp, sampleOffset, Fs)
%manualArtifactMask  Logical mask of ManualArtifacts for one streamed block.
%   MASK = ds.manualArtifactMask(NSAMP, SAMPLEOFFSET, FS) returns an
%   [NSAMP x 1] logical flagging the samples of a block that fall within any
%   manually defined artifact period (ds.ManualArtifacts, recording-relative
%   seconds). SAMPLEOFFSET is the number of samples that precede this block in
%   the whole recording, so the absolute (0-based) sample index of row k is
%   SAMPLEOFFSET + k - 1 and its time is that divided by FS.
%
%   toBin streams one *.rhd file at a time and calls this per file (with the
%   running sample offset) to build the mask it passes to blankArtifacts.
%
%   See also IntanDataset.addArtifact, IntanDataset.blankArtifacts, IntanDataset.toBin.

arguments
    obj (1,1) IntanDataset
    nSamp (1,1) double {mustBeInteger, mustBeNonnegative}
    sampleOffset (1,1) double {mustBeInteger, mustBeNonnegative}
    Fs (1,1) double {mustBePositive}
end

mask = false(nSamp, 1);
iv = obj.ManualArtifacts;
if isempty(iv) || nSamp == 0
    return
end

for k = 1:size(iv, 1)
    a = min(iv(k, 1), iv(k, 2));
    b = max(iv(k, 1), iv(k, 2));
    % Absolute 0-based sample indices covered by [a, b] seconds.
    n0 = ceil(a * Fs);
    n1 = floor(b * Fs);
    % Map to 1-based rows within this block and clamp to it.
    i0 = max(1, n0 - sampleOffset + 1);
    i1 = min(nSamp, n1 - sampleOffset + 1);
    if i1 >= i0
        mask(i0:i1) = true;
    end
end
end
