        function onExportDiagnostics(obj)
            D = obj.DiagnosticsTable.Data;

            if ~istable(D) || isempty(D)
                uialert(obj.Fig, "No diagnostics to export.", "Export Diagnostics");
                return
            end

            [f, p] = uiputfile("*.csv", "Save diagnostics table as");
            if isequal(f, 0)
                return
            end

            writetable(D, fullfile(p, f));
        end
