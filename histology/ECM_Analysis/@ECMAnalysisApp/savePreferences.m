        function savePreferences(obj)
            % Save current UI settings as preferences for next session.
            % Uses MATLAB's setpref to persist user choices.
            
            prefGroup = 'ECMAnalysisApp';
            
            % Save folder paths
            setpref(prefGroup, 'LastRootPath', obj.RootPathField.Value);
            setpref(prefGroup, 'LastMetadataPath', obj.MetadataPathField.Value);
            
            % Save analysis parameters
            setpref(prefGroup, 'PeakMin', obj.PeakMinField.Value);
            setpref(prefGroup, 'PeakMax', obj.PeakMaxField.Value);
            setpref(prefGroup, 'SmoothingMethod', obj.SmoothMethodDropDown.Value);
            setpref(prefGroup, 'SmoothingWindow', obj.SmoothWindowField.Value);
            setpref(prefGroup, 'ErrorMetric', obj.ErrorMetricDropDown.Value);
            setpref(prefGroup, 'NormalizeMode', obj.NormalizeDropDown.Value);
            setpref(prefGroup, 'PlotType', obj.PlotTypeDropDown.Value);
            setpref(prefGroup, 'PlotColor', obj.PlotColorDropDown.Value);
            setpref(prefGroup, 'PlotLineWidth', obj.PlotLineWidthField.Value);

            % Save facet visualization settings
            setpref(prefGroup, 'FacetLayout', obj.FacetLayoutDropDown.Value);
            setpref(prefGroup, 'FacetMaxRows', obj.FacetMaxRowsField.Value);
            setpref(prefGroup, 'FacetMaxCols', obj.FacetMaxColsField.Value);
        end
