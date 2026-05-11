        function D = buildDiagnosticsTable(~, S)
            D = table();

            if isfield(S, "diagnostics") && istable(S.diagnostics) && ~isempty(S.diagnostics)
                base = S.diagnostics;

                if ~ismember("Severity", string(base.Properties.VariableNames))
                    base.Severity = repmat("error", height(base), 1);
                end

                D = base;
            end

            if ~isfield(S, "combined") || ~istable(S.combined)
                return
            end

            vars = string(S.combined.Properties.VariableNames);
            expected = ["distance_pixel_index", "intensity", "Filename", "SubjectID", "Atlas Plate #", "Hemisphere"];
            missing = expected(~ismember(expected, vars));

            if isempty(missing)
                return
            end

            warnRows = table();
            warnRows.FileIndex = nan(numel(missing), 1);
            warnRows.FilePath = repmat("", numel(missing), 1);
            warnRows.Filename = repmat("", numel(missing), 1);
            warnRows.Identifier = repmat("ECMAnalysis:MissingRecommendedColumn", numel(missing), 1);
            warnRows.Message = "Recommended column missing: " + missing(:);
            warnRows.Stage = repmat("schema", numel(missing), 1);
            warnRows.Severity = repmat("warning", numel(missing), 1);

            if isempty(D)
                D = warnRows;
            else
                D = [D; warnRows];
            end
        end
