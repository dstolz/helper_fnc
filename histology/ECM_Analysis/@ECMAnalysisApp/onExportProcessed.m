        function onExportProcessed(obj)
            if isempty(obj.Analysis) || ~isfield(obj.Analysis, "aligned")
                uialert(obj.Fig, "No processed data to export.", "Export Error");
                return
            end

            [f, p] = uiputfile("*.csv", "Save processed table as");
            if isequal(f, 0)
                return
            end
            writetable(obj.Analysis.aligned, fullfile(p, f));
        end
