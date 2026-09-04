function code = viewCommands(obj, options)
    %VIEWCOMMANDS This view, as the commands that would put a browser back in it.
    %   code = B.viewCommands()
    %   code = B.viewCommands(Variable = "browser")
    %
    % A view is arrived at by clicking, and is wanted again in a script:
    % in the next session, in the figure-making file that goes with the
    % paper, in a message to whoever asks how a plot was made. What comes
    % back is the calls that make it -- SETCOMPARISON, SETNORMALIZATION,
    % SETTILING, SETFILTER, and a control set directly where there is no
    % method for it -- one line each, ready to paste.
    %
    % Only what has been changed is written out. A browser opens on the
    % rest, so a line saying so would be a line to read and check for
    % nothing; what is always written is the color and the tiling, which
    % a browser picks from the dataset rather than from a fixed default
    % and which are the two choices a figure is really made of.
    %
    % VARIABLE is what the browser is called in the commands, and
    % defaults to the name it goes under in the base workspace, or to B
    % where it goes under none -- which is the case when ECMBROWSER was
    % called for its side effect, as LAUNCH_ECM_BROWSER calls it.
    %
    % See also COPYSUMMARY, CAPTURESETTINGS.

    arguments
        obj
        options.Variable (1,1) string = obj.browserVariable()
    end

    s = obj.captureSettings();
    v = options.Variable;

    depth = obj.Data.grid.depth;
    fullWindow = [floor(min(depth)) ceil(max(depth))];

    stamp = string(datetime("now", Format = "uuuu-MM-dd HH:mm"));

    code = "% The ECM Browser view of " + stamp + ", as commands.";
    code(end+1) = "% Everything not named here is what a browser opens on.";

    if s.Signal ~= "smoothed"
        code(end+1) = v + ".SignalDropDown.Value = " + obj.textLiteral(s.Signal) + ";";
    end

    % The normalization is three controls and one call, and means
    % nothing at all while the mode is none -- a scope and a window
    % with nothing to rescale are not worth a line.
    if s.Normalize ~= "none"
        code(end+1) = v + ".setNormalization(" + ...
            obj.textLiteral(s.Normalize) + ", " + ...
            obj.numberLiteral([s.RefMin s.RefMax]) + ", " + ...
            "scope = " + obj.textLiteral(s.Scope) + ");";
    end

    % The comparison is written out in full rather than left to its
    % defaults: which value is the reference and what a match has to
    % agree on are the two things a reader of the command wants said,
    % and are exactly the two that are easiest to get wrong.
    if obj.comparing()
        within = s.PairWithin(s.PairWithin ~= obj.NoField);

        if isempty(within)
            within = obj.NoField;
        end

        code(end+1) = v + ".setComparison(" + obj.textLiteral(s.Compare) + ", " + ...
            obj.textLiteral(s.CompareField) + ", ..." ;
        code(end+1) = "    reference = " + obj.textLiteral(s.CompareRef) + ", " + ...
            "within = " + obj.textLiteral(within) + ");";
    end

    if s.Show ~= "sections"
        code(end+1) = v + ".ShowDropDown.Value = " + obj.textLiteral(s.Show) + ";";
    end

    % Which summary, where there is one. Written out whatever it is set
    % to rather than only when it differs from the default: it is the
    % whole of what the points on screen are, and a reader of the command
    % should not have to know what a browser opens on to know that.
    if s.Show == "metric summary"
        code(end+1) = v + ".MetricDropDown.Value = " + obj.textLiteral(s.Metric) + ";";
    end

    if ismember(s.Show, ["group mean", "metric summary"]) && s.ErrorBand ~= "sem"
        code(end+1) = v + ".ErrorDropDown.Value = " + obj.textLiteral(s.ErrorBand) + ";";
    end

    if s.Show == "group mean" && ~s.SectionsBehind
        code(end+1) = v + ".SectionsCheckBox.Value = false;";
    end

    % The split the figure is made of, said whatever it is set to.
    code(end+1) = v + ".GroupDropDown.Value = " + obj.textLiteral(s.Group) + ";";

    tile = s.Tile(s.Tile ~= obj.NoField);

    if isempty(tile)
        code(end+1) = v + ".setTiling();";
    else
        code(end+1) = v + ".setTiling(" + obj.textLiteral(tile) + ");";
    end

    % One call per condition, in the order they were made, because that is
    % how they accumulate: the first narrows a field and every one after it
    % adds a condition beside the ones before.
    for k = 1:numel(s.Filters)
        line = v + ".setFilter(" + obj.textLiteral(s.Filters(k).Field) + ", " + ...
            obj.textLiteral(s.Filters(k).Values);

        if ~s.Filters(k).Keep
            line = line + ", keep = false";
        end

        code(end+1) = line + ");"; %#ok<AGROW>
    end

    % And the rule combining them last, where it is not the AND a browser
    % opens on -- after the conditions rather than on the first of them, so
    % that it reads as the word between them and not as something asked of
    % the one field that call names. One condition is the same either way
    % and is left to say nothing about it.
    if numel(s.Filters) > 1 && s.FilterMatch ~= obj.FilterMatches(1)
        code(end+1) = v + ".setFilter(match = " + ...
            obj.textLiteral(lower(extractBetween(s.FilterMatch, "(", ")"))) + ");";
    end

    if ~isequal([s.DepthMin s.DepthMax], fullWindow)
        code(end+1) = v + ".DepthMinField.Value = " + obj.numberLiteral(s.DepthMin) + ";";
        code(end+1) = v + ".DepthMaxField.Value = " + obj.numberLiteral(s.DepthMax) + ";";
    end

    % How the grid is dressed. None of it changes what is drawn, so it
    % is written out only where it has been changed.
    code = [code, obj.layoutCommands(s, v)];

    % A color or a line style picked from a right-click menu is no part
    % of the panel and so no part of a saved configuration, but it is
    % part of the figure, and this is the only way it leaves the browser.
    code = [code, obj.styleCommands(v)];

    code(end+1) = v + ".refresh();";
    code = [code, obj.nextCommands(s, v)];

    code = reshape(code, [], 1);

    if nargout == 0
        fprintf("%s\n", code)
        clear code
    end

end
