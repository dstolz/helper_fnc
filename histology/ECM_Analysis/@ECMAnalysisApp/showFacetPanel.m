        function showFacetPanel(obj)
            obj.PlotAxes.Visible = "off";
            if ~isempty(obj.FacetPanel) && isvalid(obj.FacetPanel)
                obj.FacetPanel.Visible = "on";
            end
        end
