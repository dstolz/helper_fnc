        function onExportSummary(obj)
            if isempty(obj.Analysis) || ~isfield(obj.Analysis, "grouped")
                uialert(obj.Fig, "No summary data to export.", "Export Error");
                return
            end

            [f, p] = uiputfile("*.csv", "Save summary table as");
            if isequal(f, 0)
                return
            end
            writetable(obj.Analysis.grouped, fullfile(p, f));
        end
