function copySummary(obj)
    %COPYSUMMARY Put a written account of the view on the clipboard.
    % Every choice that decides what the plot means -- the scale, how
    % many sections were pooled to set it, what is shown, split, and
    % filtered -- which is what a figure legend or a methods paragraph
    % has to say, and what a picture of the plot does not hold.

    s = obj.captureSettings();

    lines = "ECM Browser view";
    lines(end+1) = "  Signal: " + s.Signal;
    lines(end+1) = "  Normalize: " + s.Normalize;

    if s.Normalize ~= "none"
        lines(end) = lines(end) + " (" + s.Scope + "), reference " + ...
            s.RefMin + " to " + s.RefMax;
    end

    lines(end+1) = "  Compare: " + s.Compare;

    if s.Compare ~= "none" && s.CompareField ~= obj.NoField
        lines(end) = lines(end) + " by " + s.CompareField + ...
            ", against " + s.CompareRef;

        paired = s.PairWithin(s.PairWithin ~= obj.NoField);

        if isempty(paired)
            lines(end) = lines(end) + ", pooled over every section in view";
        else
            lines(end) = lines(end) + ", paired within " + ...
                strjoin(paired, " x ");
        end
    end

    lines(end+1) = "  Show: " + s.Show;

    if s.Show == "metric summary"
        lines(end) = lines(end) + ", metric " + s.Metric + ...
            " (per section, over the depth window and on the scale above)";
    end

    if ismember(s.Show, ["group mean", "metric summary"])
        lines(end) = lines(end) + ", error band " + s.ErrorBand;

        if s.ErrorBand == "bootstrap 95%"
            lines(end) = lines(end) + " (percentile, " + ...
                obj.BootReps + " resamples of the sections)";
        end
    end

    if s.Show == "group mean"
        lines(end) = lines(end) + ...
            ", sections behind the mean: " + string(logical(s.SectionsBehind));
    end

    lines(end+1) = "  Color by: " + s.Group;
    lines(end+1) = "  Tile by: " + strjoin(s.Tile, " x ");
    % One condition to a line, spelled out in full: a caption has room for
    % the values a panel had to abbreviate, and which sections a figure was
    % made from is exactly what a methods paragraph is being asked for.
    if isempty(s.Filters)
        lines(end+1) = "  Filter: " + obj.AllSections;
    else
        conditions = strings(1, numel(s.Filters));

        for k = 1:numel(s.Filters)
            if s.Filters(k).Keep
                operator = " = ";
            else
                operator = " is not ";
            end

            conditions(k) = s.Filters(k).Field + operator + ...
                strjoin(s.Filters(k).Values, ", ");
        end

        % Under the second and later conditions goes the word that
        % combines them, so that a list of three is not left to be read as
        % an AND when it was asked as an OR.
        joiner = lower(string(extractBetween(s.FilterMatch, "(", ")")));
        conditions(2:end) = joiner + " " + conditions(2:end);

        lines = [lines, "  Filter: " + conditions(1), ...
            "          " + conditions(2:end)];
    end

    lines(end+1) = "  " + obj.withUnit("Depth") + ": " + ...
        s.DepthMin + " to " + s.DepthMax;
    lines(end+1) = "  " + obj.StatusLabel.Text;

    try
        clipboard("copy", strjoin(lines, newline))
    catch ME
        uialert(obj.Fig, ME.message, "Could not copy the summary");
        return
    end

    obj.setStatus("View summary copied to the clipboard.");

end
