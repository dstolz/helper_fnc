function addArtifact(obj, t0, t1)
%addArtifact  Add a manual artifact period [t0 t1] (s), merging overlaps.
%   ds.addArtifact(T0, T1) appends the period spanning T0..T1 seconds
%   (recording-relative) to ds.ManualArtifacts, then sorts and merges any
%   overlapping or touching periods so the list stays minimal. Negative times
%   are clamped to 0; a zero-width period is ignored.
%
%   See also IntanDataset.manualArtifactMask, IntanDataset.ManualArtifacts.

arguments
    obj (1,1) IntanDataset
    t0 (1,1) double {mustBeFinite}
    t1 (1,1) double {mustBeFinite}
end

a = max(0, min(t0, t1));
b = max(t0, t1);
if b <= a
    return
end

iv = sortrows([obj.ManualArtifacts; a b], 1);
merged = iv(1, :);
for k = 2:size(iv, 1)
    if iv(k, 1) <= merged(end, 2)
        merged(end, 2) = max(merged(end, 2), iv(k, 2));
    else
        merged(end + 1, :) = iv(k, :); %#ok<AGROW>
    end
end
obj.ManualArtifacts = merged;
end
