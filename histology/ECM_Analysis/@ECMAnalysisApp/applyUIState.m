        function applyUIState(obj, s)
            if isfield(s, "RootPath")
                obj.RootPathField.Value = char(s.RootPath);
            end
            if isfield(s, "MetadataPath")
                obj.MetadataPathField.Value = char(s.MetadataPath);
            end
            if isfield(s, "PeakRange") && numel(s.PeakRange) == 2
                obj.PeakMinField.Value = double(s.PeakRange(1));
                obj.PeakMaxField.Value = double(s.PeakRange(2));
            end
            if isfield(s, "SmoothingMethod")
                obj.SmoothMethodDropDown.Value = char(s.SmoothingMethod);
            end
            if isfield(s, "SmoothingWindow")
                obj.SmoothWindowField.Value = double(s.SmoothingWindow);
            end
            if isfield(s, "ErrorMetric")
                obj.ErrorMetricDropDown.Value = char(s.ErrorMetric);
            end
            if isfield(s, "NormalizeMode")
                obj.NormalizeDropDown.Value = char(s.NormalizeMode);
            end
            if isfield(s, "PlotType")
                plotType = string(s.PlotType);
                if ismember(plotType, string(obj.PlotTypeDropDown.Items))
                    obj.PlotTypeDropDown.Value = char(plotType);
                end
            end
            if isfield(s, "PlotColor")
                plotColor = string(s.PlotColor);
                if ismember(plotColor, string(obj.PlotColorDropDown.Items))
                    obj.PlotColorDropDown.Value = char(plotColor);
                end
            end
            if isfield(s, "PlotLineWidth")
                obj.PlotLineWidthField.Value = double(s.PlotLineWidth);
            end
            if isfield(s, "GroupVars")
                savedVars = cellstr(s.GroupVars);
                valid = savedVars(ismember(savedVars, obj.GroupVarsList.Items));
                if ~isempty(valid)
                    obj.GroupVarsList.Value = valid;
                end
            end
            if isfield(s, "FacetVars")
                facetVars = s.FacetVars;
                if ~isempty(facetVars) && ~all(facetVars == "")
                    valid = cellstr(facetVars(ismember(facetVars, string(obj.FacetVarsList.Items))));
                    if ~isempty(valid)
                        obj.FacetVarsList.Value = valid;
                    end
                end
            end
            if isfield(s, "FacetLayout")
                facetLayout = s.FacetLayout;
                if ismember(facetLayout, obj.FacetLayoutDropDown.Items)
                    obj.FacetLayoutDropDown.Value = char(facetLayout);
                end
            end
            if isfield(s, "FacetMaxRows")
                obj.FacetMaxRowsField.Value = double(s.FacetMaxRows);
            end
            if isfield(s, "FacetMaxCols")
                obj.FacetMaxColsField.Value = double(s.FacetMaxCols);
            end
        end
