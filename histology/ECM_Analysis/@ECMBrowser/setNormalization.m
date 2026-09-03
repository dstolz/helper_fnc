function setNormalization(obj, mode, window, options)
    %SETNORMALIZATION Rescale each section, and say where from.
    %   B.setNormalization("z-score")
    %   B.setNormalization("peak = 1", scope = "within plot")
    %   B.setNormalization("% of baseline", [800 1500])
    %   B.setNormalization()  draws the intensities as they were prepared
    %
    % The mode, the sections it pools, and the window it is measured
    % over only mean anything together, so they are set together: the
    % one call a script needs to put a figure on the scale it should be
    % read on.

    arguments
        obj
        mode (1,1) string = "none"
        window (1,2) double = [obj.RefMinField.Value obj.RefMaxField.Value]
        options.scope (1,1) string = string(obj.ScopeDropDown.Value)
    end

    if ~ismember(mode, obj.NormalizeModes)
        error("ECMBrowser:UnknownNormalization", ...
            "Normalization must be one of: %s", strjoin(obj.NormalizeModes, ", "))
    end

    if ~ismember(options.scope, obj.NormalizeScopes)
        error("ECMBrowser:UnknownNormalizationScope", ...
            "Scope must be one of: %s", strjoin(obj.NormalizeScopes, ", "))
    end

    if ~all(isfinite(window)) || window(2) <= window(1)
        error("ECMBrowser:EmptyReferenceWindow", ...
            "The reference window must run from one finite depth to a larger one.")
    end

    obj.NormalizeDropDown.Value = mode;
    obj.ScopeDropDown.Value = options.scope;
    obj.RefMinField.Value = window(1);
    obj.RefMaxField.Value = window(2);
    obj.refresh();

end
