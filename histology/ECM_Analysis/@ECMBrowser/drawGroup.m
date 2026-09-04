function h = drawGroup(obj, ax, x, Y, idx, cols, groupField, groupName, color, slot)
    %DRAWGROUP Draw one group's sections into one tile.
    % Only the first artist of a group carries a DisplayName, so the
    % legend lists groups rather than every section in them.
    %
    % SLOT is the group's place along the x axis, counted from one over
    % every group in the layout rather than over the ones this tile
    % happens to hold. It is what the metric summary plots against, and
    % taking it from the layout is what keeps a group over the same tick
    % from tile to tile, whether or not its neighbors reached them.
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

        case "metric summary"
            v = section_metrics(x, Y(:, cols), string(obj.MetricDropDown.Value));

            % One point per section at the group's own place on the
            % axis, spread across the slot so that two sections of the
            % same value do not land on top of one another. Spread by
            % position in the group rather than at random, so that a
            % redraw puts every point back where it was and a figure
            % saved twice is the same figure twice.
            at = slot + obj.MetricSpread * obj.MetricJitter * spread(numel(v));

            h(end+1) = scatter(ax, at, v, 42, ...
                sty.Color, "filled", ...
                MarkerFaceAlpha = 0.7, ...
                DisplayName = groupName);
            roles(end+1) = "marker";

            % The group's mean ruled through its points, with whatever
            % the Error band control names drawn up and down from it.
            % Both are drawn out of the legend: the points already carry
            % the group's name, and a key listing it three times says
            % nothing the first entry did not.
            [m, lo, hi] = obj.metricBand(v);

            if isfinite(lo) && isfinite(hi)
                h(end+1) = line(ax, [slot slot], [lo hi], ...
                    Color = sty.Color, ...
                    LineWidth = 1.5, ...
                    HandleVisibility = "off");
                roles(end+1) = "rule";
            end

            if isfinite(m)
                h(end+1) = line(ax, slot + obj.MetricSpread * [-1 1], [m m], ...
                    Color = sty.Color, ...
                    LineWidth = 2, ...
                    HandleVisibility = "off");
                roles(end+1) = "rule";
            end

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

function offsets = spread(n)
%SPREAD Where each of N points sits across the width of one group's slot.
% As a fraction of the half-width, so that one point sits on the group's
% tick and any more of them fill the slot evenly out to its edges.

if n < 2
    offsets = 0;
    return
end

offsets = linspace(-1, 1, n).';

end
