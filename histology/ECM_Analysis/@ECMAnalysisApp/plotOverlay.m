        function plotOverlay(obj, ax)
            T = obj.Analysis.aligned;
            if isempty(T)
                title(ax, "No aligned data");
                return
            end

            files = unique(string(T.Filename));
            labels = obj.makeConciseLegendLabels(files);
            lw = max(0.25, obj.PlotLineWidthField.Value);
            for i = 1:numel(files)
                idx = string(T.Filename) == files(i);
                plot(ax, T.aligned_distance(idx), T.intensity_raw(idx), "Color", [0.8 0.8 0.8], "LineWidth", max(0.25, 0.75 * lw), "HandleVisibility", "off");
                plot(ax, T.aligned_distance(idx), T.intensity_smoothed(idx), "LineWidth", lw, "DisplayName", labels(i));
            end

            title(ax, "Raw + Smoothed Overlay")
            xlabel(ax, "Aligned distance")
            ylabel(ax, "Intensity")
            if numel(files) <= 20
                legend(ax, "Interpreter", "none", "Location", "best")
            end
        end
