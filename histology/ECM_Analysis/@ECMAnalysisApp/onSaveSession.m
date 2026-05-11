        function onSaveSession(obj)
            [f, p] = uiputfile("*.mat", "Save session as");
            if isequal(f, 0)
                return
            end

            SessionData = obj.Data; %#ok<NASGU>
            SessionAnalysis = obj.Analysis; %#ok<NASGU>
            UIState = obj.getUIState(); %#ok<NASGU>
            save(fullfile(p, f), "SessionData", "SessionAnalysis", "UIState", "-v7");
        end
