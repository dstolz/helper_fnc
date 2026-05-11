        function refreshGroupChoices(obj)
            if isempty(obj.Data) || ~isfield(obj.Data, "combined") || isempty(obj.Data.combined)
                obj.GroupChoices = strings(0, 1);
                obj.GroupVarsList.Items = {};
                obj.GroupVarsList.Value = {};
                obj.FacetVarsList.Items = {};
                obj.FacetVarsList.Value = {};
                return
            end

            vars = string(obj.Data.combined.Properties.VariableNames);
            defaults = ["SubjectID", "Atlas Plate #", "Hemisphere"];
            defaultExisting = defaults(ismember(defaults, vars));

            obj.GroupChoices = vars;
            obj.GroupVarsList.Items = cellstr(vars);

            if isempty(defaultExisting)
                obj.GroupVarsList.Value = cellstr(vars(1:min(3, numel(vars))));
            else
                obj.GroupVarsList.Value = cellstr(defaultExisting);
            end

            % Also populate facet variables list
            obj.FacetVarsList.Items = cellstr(vars);
            if ismember("SubjectID", vars)
                obj.FacetVarsList.Value = {'SubjectID'};
            else
                obj.FacetVarsList.Value = cellstr(vars(1));
            end
        end
