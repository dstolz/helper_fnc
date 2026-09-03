function n = normalizationOf(obj, depth, reference, inView)
    %NORMALIZATIONOF The rescaling the normalization controls describe.
    % Every mode is one affine map -- subtract a center, divide by a
    % scale -- so a mode is a choice of which statistic those two
    % numbers are read from, and a scope is a choice of how many
    % sections are pooled to read it. One pair of vectors then rescales
    % the profile grid and the section peaks alike. REFERENCE is the
    % smoothed grid over the whole depth axis; the reference window and
    % the sections in view are applied here.

    nSections = size(reference, 2);

    center = zeros(1, nSections);
    scale = ones(1, nSections);

    mode = string(obj.NormalizeDropDown.Value);

    if mode == "none"
        n = struct("center", center, "scale", scale, "degenerate", 0);
        return
    end

    inRef = depth >= obj.RefMinField.Value & depth <= obj.RefMaxField.Value;

    if ~any(inRef)
        n = struct("center", center, "scale", scale, "degenerate", nnz(inView));
        return
    end

    xRef = depth(inRef);
    R = reference(inRef, :);

    poolId = obj.poolOf(inView);
    pools = unique(poolId(~isnan(poolId)));

    for iPool = 1:numel(pools)
        inPool = poolId == pools(iPool);

        [poolCenter, poolScale] = pool_stats(mode, xRef, R(:, inPool));

        center(inPool) = poolCenter;
        scale(inPool) = poolScale;
    end

    % A pool the transform cannot be taken from -- one that never
    % reached the reference window, one that is flat inside it, or one
    % whose divisor is not positive because the profiles were already
    % centered on zero upstream -- is left in its own units rather than
    % blown up by a scale near zero, and its sections are counted so
    % that the status line can say it happened.
    usable = isfinite(center) & isfinite(scale) & scale > 0;

    center(~usable) = 0;
    scale(~usable) = 1;

    n = struct("center", center, "scale", scale, ...
        "degenerate", sum(~usable & ~isnan(poolId)));

end
