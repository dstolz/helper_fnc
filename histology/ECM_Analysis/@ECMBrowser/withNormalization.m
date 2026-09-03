function text = withNormalization(obj, label)
    %WITHNORMALIZATION Name the scale the intensities are drawn on.
    % Normalized intensities carry no unit, and the mode and the scope
    % together are the only thing that says what a value of 1 means, so
    % both are named on the axis rather than left in the control panel
    % of whoever drew the figure.

    switch string(obj.NormalizeDropDown.Value)
        case "z-score"
            scaleName = "z-score";
        case "min-max"
            scaleName = "0-1";
        case "peak = 1"
            scaleName = "fraction of peak";
        case "area = 1"
            scaleName = "unit area";
        case "subtract baseline"
            scaleName = "baseline subtracted";
        case "% of baseline"
            scaleName = "% of baseline";
        otherwise
            text = label;
            return
    end

    scope = string(obj.ScopeDropDown.Value);

    if scope ~= "per section"
        scaleName = scaleName + ", " + scope;
    end

    text = label + " (" + scaleName + ")";

end
