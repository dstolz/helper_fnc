        function plotHeatmap(obj, ax)
            T = obj.Analysis.aligned;
            if isempty(T)
                title(ax, "No aligned data");
                return
            end

            xVals = unique(T.aligned_distance);
            files = unique(string(T.Filename));
            H = nan(numel(files), numel(xVals));

            for i = 1:numel(files)
                idx = string(T.Filename) == files(i);
                Tx = T(idx, :);
                [~, loc] = ismember(Tx.aligned_distance, xVals);
                H(i, loc) = Tx.intensity_smoothed;
            end

            [~, cmap] = obj.resolvePlotColors(256);
            imagesc(ax, xVals, 1:numel(files), H);
            colormap(ax, cmap);
            set(ax, "YDir", "normal")
            colorbar(ax)
            title(ax, "Heatmap by file")
            xlabel(ax, "Aligned distance")
            ylabel(ax, "File index")
        end
