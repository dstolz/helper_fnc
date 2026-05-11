        function plotPeakSummary(obj, ax)
            P = obj.Analysis.peaks;
            if isempty(P)
                title(ax, "No peak summary");
                return
            end

            ptColor = ax.ColorOrder(1, :);
            scatter(ax, P.PeakX, P.PeakY, 40, ptColor, "filled");
            title(ax, "Peak Summary")
            xlabel(ax, "Peak location")
            ylabel(ax, "Peak intensity")
        end
