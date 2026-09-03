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

    if s.Show == "group mean"
        lines(end) = lines(end) + ", error band " + s.ErrorBand;

        if s.ErrorBand == "bootstrap 95%"
            lines(end) = lines(end) + " (percentile, " + ...
                obj.BootReps + " resamples of the sections)";
        end

        lines(end) = lines(end) + ...
            ", sections behind the mean: " + string(logical(s.SectionsBehind));
    end

    lines(end+1) = "  Color by: " + s.Group;
    lines(end+1) = "  Tile by: " + strjoin(s.Tile, " x ");
    lines(end+1) = "  Filter: " + s.FilterField;

    if s.FilterField ~= obj.AllSections
        lines(end) = lines(end) + " = " + strjoin(s.FilterValues, ", ");
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
