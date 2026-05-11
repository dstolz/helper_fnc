        function onExportFig(obj)
            [f, p] = uiputfile("*.fig", "Save current plot as FIG");
            if isequal(f, 0)
                return
            end
            h = figure("Visible", "off");
            ax = axes(h);
            copyobj(allchild(obj.PlotAxes), ax);
            ax.XLim = obj.PlotAxes.XLim;
            ax.YLim = obj.PlotAxes.YLim;
            ax.XGrid = obj.PlotAxes.XGrid;
            ax.YGrid = obj.PlotAxes.YGrid;
            xlabel(ax, obj.PlotAxes.XLabel.String);
            ylabel(ax, obj.PlotAxes.YLabel.String);
            title(ax, obj.PlotAxes.Title.String);
            if ~isempty(obj.PlotAxes.Legend)
                legend(ax, "show");
            end
            savefig(h, fullfile(p, f));
            close(h);
        end
