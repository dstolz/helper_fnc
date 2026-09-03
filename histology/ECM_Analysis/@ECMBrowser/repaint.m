function repaint(obj, h)
    %REPAINT One artist, in whatever its group is drawn in now.
    % A band and a scatter have no line style to take, and the sections
    % drawn faintly behind a mean carry their transparency in the color
    % itself, so each part of a group is put back its own way.

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

        case "marker"
            h.CData = color;
    end

end
