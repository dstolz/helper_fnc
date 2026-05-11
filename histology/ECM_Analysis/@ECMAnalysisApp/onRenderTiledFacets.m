        function onRenderTiledFacets(obj, useInline)
            if isempty(obj.Analysis) || ~isfield(obj.Analysis, "aligned")
                uialert(obj.Fig, "Load and recompute first.", "No Analysis Data");
                return
            end

            if useInline
                obj.showFacetPanel();
            else
                obj.showPlotAxes();
                ax = obj.PlotAxes;
                hold(ax, "off");
                cla(ax);
            end

            obj.plotTiledFacets(useInline);

            if ~useInline
                ax = obj.PlotAxes;
                title(ax, "Tiled facets opened in separate figure")
                xlabel(ax, "")
                ylabel(ax, "")
                lw = max(0.25, obj.PlotLineWidthField.Value);
                xline(ax, 0, "HandleVisibility", "off", "LineWidth", max(0.25, 0.75 * lw));
                grid(ax, "on")
                box(ax, "on")
                hold(ax, "off")
            end
            obj.savePreferences();
        end
