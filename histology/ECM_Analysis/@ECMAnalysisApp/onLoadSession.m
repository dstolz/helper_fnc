        function onLoadSession(obj)
            [f, p] = uigetfile("*.mat", "Load session MAT file");
            if isequal(f, 0)
                return
            end

            S = load(fullfile(p, f));

            if isfield(S, "SessionData")
                obj.Data = S.SessionData;
            elseif isfield(S, "Data")
                obj.Data = S.Data;
            end
            if isfield(S, "SessionAnalysis")
                obj.Analysis = S.SessionAnalysis;
            elseif isfield(S, "Analysis")
                obj.Analysis = S.Analysis;
            end

            % Populate list items BEFORE applyUIState so saved Value selections
            % are valid against the items list.
            obj.refreshGroupChoices();

            if isfield(S, "UIState")
                obj.applyUIState(S.UIState);
            end

            if isfield(obj.Data, "diagnostics")
                obj.DiagnosticsTable.Data = obj.buildDiagnosticsTable(obj.Data);
                obj.updateDiagnosticsStatus();
            end
            obj.updateValidationStatus();

            if ~isempty(obj.Analysis) && isfield(obj.Analysis, "aligned")
                obj.onRenderPlot();
            end
        end
