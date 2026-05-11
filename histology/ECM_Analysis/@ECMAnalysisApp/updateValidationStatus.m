        function updateValidationStatus(obj)
            if isempty(obj.Analysis) || ~isfield(obj.Analysis, "validation")
                obj.ValidationStatusLabel.Text = "Validation: not run";
                return
            end

            v = obj.Analysis.validation;
            if isempty(v.missingGroupVars)
                obj.ValidationStatusLabel.Text = "Validation: required analysis/group columns resolved";
            else
                obj.ValidationStatusLabel.Text = "Validation warning: missing group vars -> " + join(v.missingGroupVars, ", ");
            end
        end
