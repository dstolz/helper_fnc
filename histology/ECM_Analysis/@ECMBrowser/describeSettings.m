function label = describeSettings(obj, s)
    %DESCRIBESETTINGS A name built from the choices that set the view apart:
    % what is shown, what it is colored and tiled by, whether it is
    % filtered, and how it is normalized. Left out entirely are the
    % reference and depth windows, the signal and error-band choice, the
    % legend placement, and the link/sections-behind flags -- fine-tuning
    % that would make every name different rather than saying what the
    % view is.

    label = s.Show;

    if s.Group ~= obj.NoField
        label = label + " by " + s.Group;
    end

    tile = s.Tile(s.Tile ~= obj.NoField);

    if ~isempty(tile)
        label = label + ", tiled " + strjoin(tile, " x ");
    end

    if s.FilterField ~= obj.AllSections
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
