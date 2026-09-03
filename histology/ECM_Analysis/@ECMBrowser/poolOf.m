function poolId = poolOf(obj, inView)
    %POOLOF Label each section with the sections it shares a scale with.
    % A section that is filtered out is left unlabeled: it is not on
    % screen, so it has no business setting the scale of a plot it is
    % absent from.

    inView = reshape(logical(inView), 1, []);

    poolId = nan(1, numel(inView));

    switch string(obj.ScopeDropDown.Value)

        case "per section"
            poolId(inView) = find(inView);

        case "per group"
            poolId = obj.poolByFields(inView, string(obj.GroupDropDown.Value));

        case "per group in plot"
            poolId = obj.poolByFields(inView, ...
                [string(obj.GroupDropDown.Value), obj.tileFields()]);

        case "within plot"
            poolId = obj.poolByFields(inView, obj.tileFields());

        otherwise
            poolId(inView) = 1;
    end

end
