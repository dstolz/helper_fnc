        function onRenderPlot(obj)
            if isempty(obj.Analysis) || ~isfield(obj.Analysis, "aligned")
                uialert(obj.Fig, "Load and recompute first.", "No Analysis Data");
                return
            end

            obj.showPlotAxes();

            ax = obj.PlotAxes;
            hold(ax, "off");
            cla(ax);
            hold(ax, "on")

            [co, cmap] = obj.resolvePlotColors(12);
            ax.ColorOrder = co;
            colormap(ax, cmap);

            mode = string(obj.PlotTypeDropDown.Value);

            switch mode
                case "Raw + Smoothed Overlay"
                    obj.plotOverlay(ax);
                case "Grouped Mean +/- Error"
                    obj.plotGroupedMean(ax);
                case "Peak Summary"
                    obj.plotPeakSummary(ax);
                case "Heatmap"
                    obj.plotHeatmap(ax);
                case "Per-Subject Facets"
                    obj.plotFacetsFigure();
                    title(ax, "Per-subject facets opened in separate figure")
                    xlabel(ax, "")
                    ylabel(ax, "")
                case "Tiled Facets"
                    obj.onRenderTiledFacets(false);
                    return
            end

            lw = max(0.25, obj.PlotLineWidthField.Value);
            xline(ax, 0, "HandleVisibility", "off", "LineWidth", max(0.25, 0.75 * lw));
            grid(ax, "on")
            box(ax, "on")
            hold(ax, "off")
            obj.savePreferences();
        end
