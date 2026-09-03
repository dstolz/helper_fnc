function [center, scale] = pool_stats(mode, x, R)
%POOL_STATS The center and scale one pool of sections is rescaled by.
% R holds every sample the pool contributes inside the reference window, and
% the statistic is taken over the whole block rather than column by column: a
% pool of one section and a pool of a whole plot are then the same arithmetic,
% and pooling keeps the differences between the sections it holds instead of
% flattening them the way rescaling each section separately does.

v = R(:);

center = 0;
scale = 1;

switch mode

    case "z-score"
        center = mean(v, 1, "omitnan");
        scale = std(v, 0, 1, "omitnan");

    case "min-max"
        center = min(v, [], 1, "omitnan");
        scale = max(v, [], 1, "omitnan") - center;

    case "peak = 1"
        scale = max(v, [], 1, "omitnan");

    case "area = 1"
        % The mean area of the pool rather than its total, so that the average
        % section comes out at one whether the pool holds one or thirty.
        scale = mean(column_area(x, R), 2, "omitnan");

    case "subtract baseline"
        % The median rather than the mean: the band is chosen to hold
        % background, and one stray bright sample in it should not shift
        % everything drawn against it.
        center = median(v, 1, "omitnan");

    case "% of baseline"
        scale = median(v, 1, "omitnan") ./ 100;
end

end
