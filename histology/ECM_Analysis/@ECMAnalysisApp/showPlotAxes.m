        function showPlotAxes(obj)
            obj.PlotAxes.Visible = "on";
            if ~isempty(obj.FacetPanel) && isvalid(obj.FacetPanel)
                obj.FacetPanel.Visible = "off";
            end
        end
