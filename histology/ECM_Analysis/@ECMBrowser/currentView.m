function [idx, Y, x] = currentView(obj)
    %CURRENTVIEW The sections and depths the controls have selected.

    x = obj.Data.grid.depth;

    if string(obj.SignalDropDown.Value) == "raw"
        Y = obj.Data.grid.raw;
    else
        Y = obj.Data.grid.smoothed;
    end

    keep = obj.filterMask();

    idx = find(keep);

    % Whichever trace is drawn, the transform is taken from the smoothed
    % one: raw and smoothed then sit on a single scale, so switching
    % Signal moves between two views of one plot rather than rescaling
    % it, and one noisy sample cannot become a section's peak or range.
    % The filter is settled first because a pooled scale is taken from
    % the sections actually drawn, and rescaling before the depth trim
    % is what keeps the reference window independent of the window on
    % screen. The transform is kept on the object for the rest of this
    % draw because the peak summary needs the same numbers.
    obj.Norm = obj.normalizationOf(x, obj.Data.grid.smoothed, keep);

    Y = (Y - obj.Norm.center) ./ obj.Norm.scale;

    % What is drawn is one column per section, or one per comparison
    % once a comparison has been asked for. Either way IDX indexes the
    % roster the draw is about to split, tile, and export, and the
    % columns of Y are in the order it lists them.
    [idx, Y] = obj.rosterOf(x, Y, idx);

    inDepth = x >= obj.DepthMinField.Value & x <= obj.DepthMaxField.Value;
    x = x(inDepth);
    Y = Y(inDepth, :);

end
