function v = section_metrics(x, Y, metric)
%SECTION_METRICS One number per column, summarizing the profile in it.
% X is the depth axis and Y one column per section on it, both already
% trimmed to the depth window on screen and rescaled by whatever the
% normalization asked for -- so every summary here answers a question
% about the curve that is actually drawn, and moving the depth window or
% the scale moves the summary with it. That is the whole difference
% between these and A.peaks, which was measured once upstream over a
% window of its own and does not follow the controls.
%
% A column is summarized over the samples it actually holds. Sections
% are interpolated onto a shared depth axis and hold nothing outside the
% depths they measured, so a column with fewer than two samples in the
% window has no shape to measure and comes back NaN rather than as a
% number taken from one point.
%
% See also ECMBROWSER/METRICLABEL, ECMBROWSER/DRAWGROUP.

x = x(:);
nCol = size(Y, 2);
v = nan(nCol, 1);

for iCol = 1:nCol
    y = Y(:, iCol);
    measured = isfinite(x) & isfinite(y);

    if nnz(measured) < 2
        continue
    end

    v(iCol) = one_column(x(measured), y(measured), metric);
end

end

function value = one_column(x, y, metric)
%ONE_COLUMN One section's summary, over the samples it measured.

value = NaN;

switch metric

    case "mean"
        value = mean(y);

    case "median"
        value = median(y);

    case "integral"
        % Trapezoidal over depth rather than a sum of samples, so that a
        % profile is worth the same whether the grid it was interpolated
        % onto is fine or coarse.
        value = trapz(x, y);

    case "peak height"
        value = max(y);

    case "peak depth"
        [~, at] = max(y);
        value = x(at);

    case "peak1 - peak2 (height)"
        [~, yp] = two_peaks(x, y);
        value = yp(1) - yp(2);

    case "peak1 to peak2 (depth)"
        xp = two_peaks(x, y);
        value = xp(2) - xp(1);

    case "FWHM"
        value = full_width(x, y);

    case "centroid depth"
        value = centroid_depth(x, y);

    case "range (max - min)"
        value = max(y) - min(y);

    case "variance"
        value = var(y);

    case "std. dev."
        value = std(y);

    case "coeff. of variation"
        % Undefined about a mean of zero, and meaningless about a
        % negative one, which is what a centering normalization leaves
        % behind: a ratio to a number that is only an offset says
        % nothing about the spread it is dividing.
        m = mean(y);

        if m > 0
            value = std(y) / m;
        end

    case "slope"
        p = polyfit(x, y, 1);
        value = p(1);

end

end

function [xp, yp] = two_peaks(x, y)
%TWO_PEAKS The two most prominent local maxima, shallowest first.
% Picked by prominence rather than by height, so that a shoulder on the
% side of a tall peak is not read as the second peak of a profile that
% only has one; returned in depth order, so that peak1 is the shallower
% of the two whichever of them is taller and a difference between them
% keeps its sign from one section to the next.
%
% A profile with fewer than two local maxima inside the window has no
% second peak to measure against, and comes back NaN rather than as a
% difference against its own edge.

xp = [NaN NaN];
yp = [NaN NaN];

[isPeak, prominence] = islocalmax(y);
at = find(isPeak);

if numel(at) < 2
    return
end

[~, order] = sort(prominence(at), "descend");
top = sort(at(order(1:2)));

xp = x(top).';
yp = y(top).';

end

function width = full_width(x, y)
%FULL_WIDTH How wide the tallest peak is at half its height.
% Half of the way from the lowest sample in the window to the highest
% rather than half of the height itself: a profile sitting on a
% background, or one a normalization has pushed below zero, would
% otherwise be measured at a level that is nowhere near the middle of
% its peak, and a negative floor would put the half-height above the
% peak altogether.

width = NaN;

[peak, at] = max(y);
half = (peak + min(y)) / 2;

if ~isfinite(half) || peak <= half
    return
end

% Out from the peak to the samples on either side of it that have
% dropped below half height. The crossing lies between such a sample
% and its neighbor toward the peak, and is placed on the straight line
% between the two rather than at whichever of them is nearer, so that
% the width does not step in whole samples. A peak that never comes
% back down inside the window is measured to the edge of it, which is a
% lower bound on the width rather than no answer at all.
below = find(y(1:at) < half, 1, "last");

if isempty(below)
    left = x(1);
else
    left = crossing(x(below), y(below), x(below + 1), y(below + 1), half);
end

above = at - 1 + find(y(at:end) < half, 1, "first");

if isempty(above)
    right = x(end);
else
    right = crossing(x(above - 1), y(above - 1), x(above), y(above), half);
end

width = right - left;

end

function depth = centroid_depth(x, y)
%CENTROID_DEPTH Where the area under the profile balances.
% Weighted by height above the lowest sample in the window rather than
% by the intensity itself. A profile on a pedestal would otherwise be
% weighted mostly by the pedestal and balance near the middle of the
% window whatever its shape, and one carrying negative values -- which
% is what a z-score or a subtracted baseline leaves -- could balance
% outside the window entirely.

depth = NaN;

w = y - min(y);
total = trapz(x, w);

if total > 0
    depth = trapz(x, w .* x) / total;
end

end

function xc = crossing(x1, y1, x2, y2, level)
%CROSSING Where the straight line between two samples passes LEVEL.

if y2 == y1
    xc = x1;
    return
end

xc = x1 + (level - y1) * (x2 - x1) / (y2 - y1);

end
