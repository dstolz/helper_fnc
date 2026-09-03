function h = drawGroup(obj, ax, x, Y, idx, cols, groupField, groupName, color)
    %DRAWGROUP Draw one group's sections into one tile.
    % Only the first artist of a group carries a DisplayName, so the
    % legend lists groups rather than every section in them.
    %
    % Everything drawn is handed back and marked with the group it
    % belongs to and the part it plays in it, which is what lets a
    % color chosen later find its way to every tile at once.

    sty = obj.effectiveStyle(groupField, groupName);

    h = gobjects(1, 0);
    roles = strings(1, 0);

    switch string(obj.ShowDropDown.Value)

        case "peak summary"
            rows = idx(cols);
            h(end+1) = scatter(ax, obj.View.PeakX(rows), obj.View.PeakY(rows), 42, ...
                sty.Color, "filled", ...
                MarkerFaceAlpha = 0.7, ...
                DisplayName = groupName);
            roles(end+1) = "marker";

        case "sections"
            for iCol = 1:numel(cols)
                h(end+1) = line(ax, x, Y(:, cols(iCol)), ...
                    Color = sty.Color, ...
                    LineStyle = sty.LineStyle, ...
                    LineWidth = 1, ...
                    DisplayName = groupName, ...
                    HandleVisibility = visibility(iCol == 1)); %#ok<AGROW>
                roles(end+1) = "line"; %#ok<AGROW>
            end

        case "group mean"
            if obj.SectionsCheckBox.Value
                for iCol = 1:numel(cols)
                    h(end+1) = line(ax, x, Y(:, cols(iCol)), ...
                        Color = [sty.Color 0.25], ...
                        LineStyle = sty.LineStyle, ...
                        LineWidth = 0.5, ...
                        HandleVisibility = "off"); %#ok<AGROW>
                    roles(end+1) = "faint"; %#ok<AGROW>
                end
            end

            M = Y(:, cols);
            n = sum(isfinite(M), 2);
            m = mean(M, 2, "omitnan");
            [lo, hi] = obj.bandOf(M, n, m);

            banded = n >= 2 & isfinite(m) & isfinite(lo) & isfinite(hi);

            if any(banded)
                xb = x(banded);
                lob = lo(banded);
                hib = hi(banded);

                h(end+1) = fill(ax, [xb; flipud(xb)], [lob; flipud(hib)], ...
                    sty.Color, ...
                    FaceAlpha = 0.2, ...
                    EdgeColor = "none", ...
                    HandleVisibility = "off");
                roles(end+1) = "band";
            end

            h(end+1) = line(ax, x(n >= 1), m(n >= 1), ...
                Color = sty.Color, ...
                LineStyle = sty.LineStyle, ...
                LineWidth = 2, ...
                DisplayName = sprintf("%s (n=%d)", groupName, numel(cols)));
            roles(end+1) = "line";
    end

    obj.markStyled(h, roles, groupField, groupName, color);

end
