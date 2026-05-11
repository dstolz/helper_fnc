        function loadPreferences(obj)
            % Load saved preferences for paths and analysis settings.
            % Uses MATLAB's getpref to restore user choices between sessions.
            
            prefGroup = 'ECMAnalysisApp';
            
            % Load last used folder paths
            if ispref(prefGroup, 'LastRootPath')
                rootPath = getpref(prefGroup, 'LastRootPath');
                if isfolder(rootPath)
                    obj.RootPathField.Value = rootPath;
                end
            end
            
            if ispref(prefGroup, 'LastMetadataPath')
                metaPath = getpref(prefGroup, 'LastMetadataPath');
                if isfile(metaPath) || metaPath == ""
                    obj.MetadataPathField.Value = metaPath;
                end
            end
            
            % Load last used analysis parameters
            if ispref(prefGroup, 'PeakMin')
                obj.PeakMinField.Value = getpref(prefGroup, 'PeakMin');
            end
            
            if ispref(prefGroup, 'PeakMax')
                obj.PeakMaxField.Value = getpref(prefGroup, 'PeakMax');
            end
            
            if ispref(prefGroup, 'SmoothingMethod')
                smoothMethod = getpref(prefGroup, 'SmoothingMethod');
                if ismember(smoothMethod, obj.SmoothMethodDropDown.Items)
                    obj.SmoothMethodDropDown.Value = smoothMethod;
                end
            end
            
            if ispref(prefGroup, 'SmoothingWindow')
                obj.SmoothWindowField.Value = getpref(prefGroup, 'SmoothingWindow');
            end
            
            if ispref(prefGroup, 'ErrorMetric')
                errorMetric = getpref(prefGroup, 'ErrorMetric');
                if ismember(errorMetric, obj.ErrorMetricDropDown.Items)
                    obj.ErrorMetricDropDown.Value = errorMetric;
                end
            end
            
            if ispref(prefGroup, 'NormalizeMode')
                normalizeMode = getpref(prefGroup, 'NormalizeMode');
                if ismember(normalizeMode, obj.NormalizeDropDown.Items)
                    obj.NormalizeDropDown.Value = normalizeMode;
                end
            end
            
            if ispref(prefGroup, 'PlotType')
                plotType = getpref(prefGroup, 'PlotType');
                if ismember(plotType, obj.PlotTypeDropDown.Items)
                    obj.PlotTypeDropDown.Value = plotType;
                end
            end

            if ispref(prefGroup, 'PlotColor')
                plotColor = getpref(prefGroup, 'PlotColor');
                if ismember(plotColor, obj.PlotColorDropDown.Items)
                    obj.PlotColorDropDown.Value = plotColor;
                end
            end

            if ispref(prefGroup, 'PlotLineWidth')
                obj.PlotLineWidthField.Value = getpref(prefGroup, 'PlotLineWidth');
            end

            % Load facet visualization settings
            if ispref(prefGroup, 'FacetLayout')
                facetLayout = getpref(prefGroup, 'FacetLayout');
                if ismember(facetLayout, obj.FacetLayoutDropDown.Items)
                    obj.FacetLayoutDropDown.Value = facetLayout;
                end
            end

            if ispref(prefGroup, 'FacetMaxRows')
                obj.FacetMaxRowsField.Value = getpref(prefGroup, 'FacetMaxRows');
            end

            if ispref(prefGroup, 'FacetMaxCols')
                obj.FacetMaxColsField.Value = getpref(prefGroup, 'FacetMaxCols');
            end
        end
