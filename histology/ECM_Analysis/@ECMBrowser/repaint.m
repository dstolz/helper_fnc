function repaint(obj, h)
    %REPAINT One artist, in whatever its group is drawn in now.
    % A band and a scatter have no line style to take, the rules through
    % a metric summary's group have one but should not take it, and the
    % sections drawn faintly behind a mean carry their transparency in
    % the color itself, so each part of a group is put back its own way.

    mark = h.UserData;
    key = obj.styleKey(mark.Field, mark.Group);

    color = mark.Color;
    lineStyle = "-";

    if isKey(obj.Styles, key)
        chosen = obj.Styles(key);

        if ~isempty(chosen.Color)
            color = chosen.Color;
        end

        if chosen.LineStyle ~= ""
            lineStyle = chosen.LineStyle;
        end
    end

    switch mark.Role
        case "line"
            h.Color = color;
            h.LineStyle = lineStyle;

        case "faint"
            h.Color = [color 0.25];
            h.LineStyle = lineStyle;

        case "band"
            h.FaceColor = color;

        case "rule"
            % The mean and the interval through a metric summary's
            % group. Both are lines, but neither is the curve the line
            % style was chosen for -- a dashed mean would read as
            % another kind of average rather than as the same one in
            % another group's style -- so they take the color alone.
            h.Color = color;

        case "marker"
            h.CData = color;
    end

end
