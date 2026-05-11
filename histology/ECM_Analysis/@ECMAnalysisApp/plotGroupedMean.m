        function plotGroupedMean(obj, ax)
            G = obj.Analysis.grouped;
            if isempty(G)
                title(ax, "No grouped data");
                return
            end

            groupVars = obj.Analysis.groupVars;
            keyVars = setdiff(groupVars, "aligned_distance", "stable");

            filenameDisplay = strings(height(G), 1);
            hasFilenameKey = any(keyVars == "Filename") && ismember("Filename", string(G.Properties.VariableNames));
            if hasFilenameKey
                fileCol = string(G.Filename);
                uniqueFiles = unique(fileCol, "stable");
                uniqueLabels = obj.makeConciseLegendLabels(uniqueFiles);
                [isHit, loc] = ismember(fileCol, uniqueFiles);
                filenameDisplay = fileCol;
                filenameDisplay(isHit) = uniqueLabels(loc(isHit));
            end

            if isempty(keyVars)
                key = repmat("All", height(G), 1);
            else
                if keyVars(1) == "Filename" && hasFilenameKey
                    key = filenameDisplay;
                else
                    key = string(G.(keyVars(1)));
                end
                for i = 2:numel(keyVars)
                    if keyVars(i) == "Filename" && hasFilenameKey
                        key = key + " / " + filenameDisplay;
                    else
                        key = key + " / " + string(G.(keyVars(i)));
                    end
                end
            end

            keys = unique(key, "stable");
            lw = max(0.25, obj.PlotLineWidthField.Value);
            for i = 1:numel(keys)
                idx = key == keys(i);
                x = G.aligned_distance(idx);
                y = G.mean_intensity(idx);
                e = G.error_intensity(idx);

                [x, ix] = sort(x);
                y = y(ix);
                e = e(ix);

                colorIdx = mod(i-1, size(ax.ColorOrder, 1)) + 1;
                thisColor = ax.ColorOrder(colorIdx, :);

                fill(ax, [x; flipud(x)], [y-e; flipud(y+e)], thisColor, ...
                    "FaceAlpha", 0.25, "EdgeColor", "none", "HandleVisibility", "off");
                plot(ax, x, y, "LineWidth", lw, "Color", thisColor, "DisplayName", keys(i));
            end

            title(ax, "Grouped Mean +/- Error")
            xlabel(ax, "Aligned distance")
            ylabel(ax, "Smoothed intensity")
            legend(ax, "Interpreter", "none", "Location", "best")
        end
