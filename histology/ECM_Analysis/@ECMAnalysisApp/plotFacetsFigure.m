        function plotFacetsFigure(obj)
            T = obj.Analysis.aligned;
            if isempty(T)
                uialert(obj.Fig, "No aligned data for facets.", "Facet Plot");
                return
            end

            if ~ismember("SubjectID", string(T.Properties.VariableNames))
                uialert(obj.Fig, "SubjectID not available for faceting.", "Facet Plot");
                return
            end

            subs = unique(string(T.SubjectID));

            if isvalid_handle(obj.FacetFigure)
                close(obj.FacetFigure);
            end

            obj.FacetFigure = figure("Name", "Per-Subject Facets", "Color", "w");
            tl = tiledlayout(obj.FacetFigure, "flow");
            tl.TileSpacing = "compact";
            tl.Padding = "compact";

            [co, cmap] = obj.resolvePlotColors(12);
            colororder(obj.FacetFigure, co);
            colormap(obj.FacetFigure, cmap);
            lw = max(0.25, obj.PlotLineWidthField.Value);

            for i = 1:numel(subs)
                nexttile(tl);
                idx = string(T.SubjectID) == subs(i);

                if ismember("Filename", string(T.Properties.VariableNames))
                    files = unique(string(T.Filename(idx)));
                    tileCo = co;
                    if size(tileCo, 1) < numel(files)
                        reps = ceil(numel(files) / size(tileCo, 1));
                        tileCo = repmat(tileCo, reps, 1);
                    end

                    for j = 1:numel(files)
                        idf = idx & string(T.Filename) == files(j);
                        plot(T.aligned_distance(idf), T.intensity_smoothed(idf), "Color", tileCo(j,:), "LineWidth", lw);
                        hold on
                    end
                else
                    plot(T.aligned_distance(idx), T.intensity_smoothed(idx), "k-", "LineWidth", lw);
                end

                xline(0, "HandleVisibility", "off", "LineWidth", max(0.25, 0.75 * lw));
                grid on
                box on
                title(subs(i), "Interpreter", "none")
                xlabel("Aligned distance")
                ylabel("Smoothed intensity")
                hold off
            end

            title(tl, "Per-Subject Facets")
        end

function tf = isvalid_handle(h)
%ISVALID_HANDLE True if graphics handle object exists and is valid.

tf = ~isempty(h) && isvalid(h);

end
