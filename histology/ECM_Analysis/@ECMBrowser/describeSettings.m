function label = describeSettings(obj, s)
    %DESCRIBESETTINGS A name built from the choices that set the view apart:
    % what is shown, what it is colored and tiled by, whether it is
    % filtered, and how it is normalized. Left out entirely are the
    % reference and depth windows, the signal and error-band choice, the
    % legend placement, and the link/sections-behind flags -- fine-tuning
    % that would make every name different rather than saying what the
    % view is.

    label = s.Show;

    % Which summary, though, is part of what is shown rather than a
    % fine-tuning of it: two configurations that differ only by it are
    % two different plots and should not come back under one name.
    if isfield(s, "Metric") && s.Show == "metric summary"
        label = label + ": " + s.Metric;
    end

    if s.Group ~= obj.NoField
        label = label + " by " + s.Group;
    end

    tile = s.Tile(s.Tile ~= obj.NoField);

    if ~isempty(tile)
        label = label + ", tiled " + strjoin(tile, " x ");
    end

    % Which fields are narrowed rather than what they are narrowed to: the
    % values are the fine-tuning this name leaves out, and joined by the
    % rule that combines them so that an AND is not read as an OR.
    if isfield(s, "Filters") && ~isempty(s.Filters)
        if isfield(s, "FilterMatch") && s.FilterMatch == obj.FilterMatches(2)
            joiner = " or ";
        else
            joiner = " and ";
        end

        label = label + ", filtered " + ...
            strjoin(reshape([s.Filters.Field], 1, []), joiner);
    elseif isfield(s, "FilterField") && s.FilterField ~= obj.AllSections
        label = label + ", filtered " + s.FilterField;
    end

    if s.Normalize ~= "none"
        label = label + ", " + s.Normalize;
    end

    % Saved before there was a comparison to save, so a name is asked
    % of it rather than a field it never held.
    if isfield(s, "Compare") && s.Compare ~= "none" && ...
            s.CompareField ~= obj.NoField
        label = label + ", " + s.Compare + " by " + s.CompareField;
    end

end
