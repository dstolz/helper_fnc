function [peakX, peakY] = comparisonPeaks(obj, depth, D, op)
    %COMPARISONPEAKS Where each comparison departs furthest from no difference.
    % A section's peak is the highest point of its profile, which is
    % the depth that says the most about it. A comparison is a
    % departure from no difference rather than a height -- and it can
    % depart downward -- so the depth that says the most about it is
    % the one furthest from the value that means the two sides agree:
    % zero, or one under a ratio. The value reported there is signed,
    % so a peak below the reference reads as one.
    %
    % Taken over the peak search window ecm_prepare_analysis_data used
    % rather than the depth window on screen, the way A.peaks is, so
    % zooming in moves the axes rather than the summary.

    nPairs = size(D, 2);
    peakX = nan(nPairs, 1);
    peakY = nan(nPairs, 1);

    neutral = compare_neutral(op);
    inRange = obj.peakWindow(depth);

    for iPair = 1:nPairs
        d = D(:, iPair);
        usable = inRange & isfinite(d);

        if ~any(usable)
            continue
        end

        from = abs(d - neutral);
        from(~usable) = -Inf;

        [~, iPeak] = max(from);

        peakX(iPair) = depth(iPeak);
        peakY(iPair) = d(iPeak);
    end

end
