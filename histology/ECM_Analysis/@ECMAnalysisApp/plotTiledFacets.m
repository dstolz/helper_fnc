        function plotTiledFacets(obj, useInline)
            T = obj.Analysis.aligned;
            if isempty(T)
                uialert(obj.Fig, "No aligned data for tiled facets.", "Tiled Facet Plot");
                return
            end

            facetVars = string(obj.FacetVarsList.Value);
            if isempty(facetVars)
                uialert(obj.Fig, "Select at least one facet variable.", "Tiled Facet Plot");
                return
            end

            varNames = string(T.Properties.VariableNames);
            missingVars = facetVars(~ismember(facetVars, varNames));
            if ~isempty(missingVars)
                uialert(obj.Fig, sprintf("Variables not found: %s", strjoin(missingVars, ", ")), "Tiled Facet Plot");
                return
            end

            layoutType = string(obj.FacetLayoutDropDown.Value);
            maxRows    = obj.FacetMaxRowsField.Value;
            maxCols    = obj.FacetMaxColsField.Value;

            % Build composite key and find groups
            groupingCols = cell(1, numel(facetVars));
            for i = 1:numel(facetVars)
                groupingCols{i} = T.(facetVars(i));
            end
            key = string(groupingCols{1});
            for i = 2:numel(groupingCols)
                key = key + " / " + string(groupingCols{i});
            end
            [groupIds, groupLabels] = findgroups(key);
            nGroups = max(groupIds);

            [themeCo, themeCmap] = obj.resolvePlotColors(12);
            lw = max(0.25, obj.PlotLineWidthField.Value);

            % Compute grid dimensions
            switch layoutType
                case "horizontal"
                    nCols = min(nGroups, maxCols);
                    nRows = ceil(nGroups / nCols);
                case "vertical"
                    nRows = min(nGroups, maxRows);
                    nCols = ceil(nGroups / nRows);
                case "grid"
                    nRows = min(maxRows, ceil(sqrt(nGroups)));
                    nCols = min(maxCols, ceil(nGroups / nRows));
                otherwise % flow
                    nCols = ceil(sqrt(nGroups));
                    nRows = ceil(nGroups / nCols);
            end

            % Create axes — uiaxes in FacetPanel (inline) or nexttile in new figure
            if useInline
                delete(obj.FacetPanel.Children);
                W   = obj.FacetPanel.Position(3);
                H   = obj.FacetPanel.Position(4);
                pad = 10;
                gap = 6;
                axW = (W - 2*pad - max(0, nCols-1)*gap) / nCols;
                axH = (H - 2*pad - max(0, nRows-1)*gap) / nRows;
                axList = gobjects(nGroups, 1);
                for i = 1:nGroups
                    row    = ceil(i / nCols);
                    col    = mod(i-1, nCols) + 1;
                    left   = pad + (col-1)*(axW + gap);
                    bottom = H - pad - row*(axH + gap) + gap;
                    axList(i) = uiaxes(obj.FacetPanel, "Position", [left bottom axW axH]);
                    axList(i).ColorOrder = themeCo;
                    colormap(axList(i), themeCmap);
                end
            else
                if ~isempty(obj.FacetFigure) && isvalid(obj.FacetFigure)
                    close(obj.FacetFigure);
                end
                obj.FacetFigure = figure("Name", "Tiled Facets", "Color", "w");
                if layoutType == "flow"
                    tl = tiledlayout(obj.FacetFigure, "flow");
                else
                    tl = tiledlayout(obj.FacetFigure, nRows, nCols);
                end
                tl.TileSpacing = "compact";
                tl.Padding     = "compact";
                colororder(obj.FacetFigure, themeCo);
                colormap(obj.FacetFigure, themeCmap);
                axList = gobjects(nGroups, 1);
                for i = 1:nGroups
                    axList(i) = nexttile(tl);
                    axList(i).ColorOrder = themeCo;
                end
            end

            % Plot each group
            for i = 1:nGroups
                ax  = axList(i);
                idx = groupIds == i;
                if ~any(idx); continue; end

                hold(ax, "on");

                if ismember("Filename", varNames)
                    files = unique(string(T.Filename(idx)));
                    labels = obj.makeConciseLegendLabels(files);
                    co    = themeCo;
                    if size(co, 1) < numel(files)
                        reps = ceil(numel(files) / size(co, 1));
                        co = repmat(co, reps, 1);
                    end

                    for j = 1:numel(files)
                        idf = idx & string(T.Filename) == files(j);
                        if any(idf)
                            plot(ax, T.aligned_distance(idf), T.intensity_smoothed(idf), ...
                                "Color", co(j,:), "LineWidth", lw, "DisplayName", labels(j));
                        end
                    end
                    if numel(files) > 1
                        legend(ax, "AutoUpdate", "off", "Location", "best", ...
                            "Interpreter", "none", "FontSize", 7);
                    end
                else
                    plot(ax, T.aligned_distance(idx), T.intensity_smoothed(idx), "k-", "LineWidth", lw);
                end

                xline(ax, 0, "k--", "HandleVisibility", "off", "LineWidth", max(0.25, 0.75 * lw));
                grid(ax, "on");
                box(ax, "on");
                title(ax, groupLabels(i), "Interpreter", "none", "FontSize", 10);
                hold(ax, "off");
            end

            % Axis labels
            if useInline
                % Label only outer edges to avoid clutter
                for i = 1:nGroups
                    row        = ceil(i / nCols);
                    col        = mod(i-1, nCols) + 1;
                    isBottom   = row == nRows || i + nCols > nGroups;
                    isLeftEdge = col == 1;
                    if isBottom
                        xlabel(axList(i), "Aligned distance", "FontSize", 9);
                    end
                    if isLeftEdge
                        ylabel(axList(i), "Smoothed intensity", "FontSize", 9);
                    end
                end
            else
                xlabel(tl, "Aligned distance");
                ylabel(tl, "Smoothed intensity");
                title(tl, sprintf("Facets: %s", strjoin(facetVars, " × ")));
            end
        end
