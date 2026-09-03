function setGroupStyle(obj, field, level, opts)
    %SETGROUPSTYLE Draw one group in a color and line style of your own.
    %   B.setGroupStyle("Treatment", "GM6001", Color = [0.85 0.33 0.10])
    %   B.setGroupStyle("Treatment", "GM6001", LineStyle = "--")
    %
    % What the right-click menu does, reachable from a script. FIELD is
    % the field the group came from -- normally whatever Color by is
    % set to -- and LEVEL one of its values. Either option can be given
    % on its own, and the other is left as it was.
    %
    % The change reaches every plot already on screen without a redraw,
    % so nothing loses the zoom it was left at, and it is kept until
    % RESETGROUPSTYLES takes it back.

    arguments
        obj
        field (1,1) string
        level (1,1) string
        opts.Color (1,:) double = []
        opts.LineStyle (1,1) string = ""
    end

    key = obj.styleKey(field, level);

    if isKey(obj.Styles, key)
        chosen = obj.Styles(key);
    else
        chosen = struct(Color = [], LineStyle = "");
    end

    if ~isempty(opts.Color)
        if numel(opts.Color) ~= 3 || any(opts.Color < 0 | opts.Color > 1)
            error("ECMBrowser:BadColor", ...
                "Color must be an RGB triplet with each part between 0 and 1.")
        end

        chosen.Color = opts.Color;
    end

    if opts.LineStyle ~= ""
        mustBeMember(opts.LineStyle, obj.LineStyleValues)
        chosen.LineStyle = opts.LineStyle;
    end

    obj.Styles(key) = chosen;
    obj.applyStyles();

end
