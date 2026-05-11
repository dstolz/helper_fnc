        function s = getUIState(obj)
            s = struct();
            s.RootPath = string(obj.RootPathField.Value);
            s.MetadataPath = string(obj.MetadataPathField.Value);
            s.GroupVars = string(obj.GroupVarsList.Value);
            s.PeakRange = [obj.PeakMinField.Value, obj.PeakMaxField.Value];
            s.SmoothingMethod = string(obj.SmoothMethodDropDown.Value);
            s.SmoothingWindow = obj.SmoothWindowField.Value;
            s.ErrorMetric = string(obj.ErrorMetricDropDown.Value);
            s.NormalizeMode = string(obj.NormalizeDropDown.Value);
            s.PlotType = string(obj.PlotTypeDropDown.Value);
            s.PlotColor = string(obj.PlotColorDropDown.Value);
            s.PlotLineWidth = obj.PlotLineWidthField.Value;
            s.FacetVars = string(obj.FacetVarsList.Value);
            s.FacetLayout = string(obj.FacetLayoutDropDown.Value);
            s.FacetMaxRows = obj.FacetMaxRowsField.Value;
            s.FacetMaxCols = obj.FacetMaxColsField.Value;
        end
