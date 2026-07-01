function [te, Ye] = decimateMinMax(tt, seg, nPix)
%decimateMinMax  Per-pixel-bin min/max envelope decimation for line plots.
%   [TE, YE] = MultiChannelViewer.decimateMinMax(TT, SEG, NPIX) reduces the
%   [m x nCh] block SEG (sampled at times TT, m x 1) to at most 2*NPIX rows per
%   channel by taking the min and max of each bin. This preserves spike/pulse
%   extrema far better than averaging while capping the plotted point count.
%   Returns SEG/TT unchanged when already within budget.
%
%   Static so it can be called without an instance, e.g. by other code in this
%   repo that wants the same decimation without duplicating it.

arguments
    tt (:,1) double
    seg (:,:) {mustBeNumeric}
    nPix (1,1) double {mustBePositive}
end

m = size(tt, 1);
nCh = size(seg, 2);
if m <= 2 * nPix
    te = tt(:).';
    Ye = seg;
    return
end

binSize = ceil(m / nPix);
nbin = floor(m / binSize);
use  = nbin * binSize;

T = reshape(tt(1:use), binSize, nbin);
tmid = T(1, :);                              % 1 x nbin
Yr = reshape(seg(1:use, :), binSize, nbin, nCh);
ymin = reshape(min(Yr, [], 1), nbin, nCh);   % nbin x nCh
ymax = reshape(max(Yr, [], 1), nbin, nCh);

te = reshape([tmid; tmid], 1, []);           % 1 x 2*nbin
Ye = zeros(2 * nbin, nCh, 'like', seg);
Ye(1:2:end, :) = ymin;
Ye(2:2:end, :) = ymax;
end
