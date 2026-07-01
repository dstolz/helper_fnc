function C = binColumnsMean(seg, nPix)
%binColumnsMean  Average [m x nCh] down the time axis to <= nPix rows.
%   C = MultiChannelViewer.binColumnsMean(SEG, NPIX) bins SEG's rows (time) into
%   groups and averages each group, used for heatmap column decimation. Returns
%   SEG unchanged when already within budget.
%
%   Static so it can be called without an instance.

arguments
    seg (:,:) {mustBeNumeric}
    nPix (1,1) double {mustBePositive}
end

m = size(seg, 1);
nCh = size(seg, 2);
if m <= nPix
    C = seg;
    return
end
binSize = ceil(m / nPix);
nbin = floor(m / binSize);
use  = nbin * binSize;
Yr = reshape(seg(1:use, :), binSize, nbin, nCh);
C = reshape(mean(Yr, 1, 'omitnan'), nbin, nCh);
end
