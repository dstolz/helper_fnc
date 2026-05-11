        function onRecompute(obj)
            if isempty(obj.Data) || ~isfield(obj.Data, "combined") || isempty(obj.Data.combined)
                return
            end

            selectedGroups = string(obj.GroupVarsList.Value);
            if isempty(selectedGroups)
                uialert(obj.Fig, "Select at least one grouping variable.", "Missing Grouping");
                return
            end

            try
                obj.Analysis = ecm_prepare_analysis_data(obj.Data, ...
                    groupVars = selectedGroups, ...
                    peakRange = [obj.PeakMinField.Value, obj.PeakMaxField.Value], ...
                    smoothingMethod = string(obj.SmoothMethodDropDown.Value), ...
                    smoothingWindow = obj.SmoothWindowField.Value, ...
                    errorMetric = string(obj.ErrorMetricDropDown.Value), ...
                    normalizeMode = string(obj.NormalizeDropDown.Value));

                obj.updateValidationStatus();
                obj.savePreferences();
            catch ME
                uialert(obj.Fig, ME.message, "Recompute Failed");
            end
        end
