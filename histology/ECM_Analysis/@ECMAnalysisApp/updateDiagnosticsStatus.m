        function updateDiagnosticsStatus(obj)
            D = obj.DiagnosticsTable.Data;

            if ~istable(D) || isempty(D)
                obj.DiagnosticsStatusLabel.Text = "Diagnostics: none";
                return
            end

            vars = string(D.Properties.VariableNames);
            if ismember("Severity", vars)
                sev = string(D.Severity);
            else
                sev = repmat("error", height(D), 1);
            end

            nErr = sum(sev == "error");
            nWarn = sum(sev == "warning");
            nOther = height(D) - nErr - nWarn;
            obj.DiagnosticsStatusLabel.Text = sprintf("Diagnostics: %d errors, %d warnings, %d other", nErr, nWarn, nOther);
        end
