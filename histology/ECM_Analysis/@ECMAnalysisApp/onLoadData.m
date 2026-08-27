        function onLoadData(obj)
            % combine_values_csv lives in the histology_browser repo.
            if exist("combine_values_csv", "file") ~= 2
                uialert(obj.Fig, "combine_values_csv was not found. Add the " + ...
                    "histology_browser repository to the MATLAB path.", "Missing Dependency");
                return
            end

            rootPath = string(obj.RootPathField.Value);
            metadataPath = strtrim(string(obj.MetadataPathField.Value));

            if rootPath == "" || ~isfolder(rootPath)
                uialert(obj.Fig, "Select a valid root folder first.", "Invalid Root Folder");
                return
            end

            d = uiprogressdlg(obj.Fig, ...
                "Title", "Loading ECM Data", ...
                "Message", "Starting...", ...
                "Cancelable", "on", ...
                "Indeterminate", "off", ...
                "Value", 0);

            obj.LoadButton.Enable = "off";
            c = onCleanup(@() obj.finishLoadUI(d));

            try
                if metadataPath == ""
                    S = combine_values_csv(rootPath, ...
                        continueOnError = true, ...
                        progressFcn = @(i,n,f) obj.updateProgress(d, i, n, f), ...
                        cancelRequestedFcn = @() d.CancelRequested);
                else
                    S = combine_values_csv(rootPath, ...
                        metadataCSV = metadataPath, ...
                        continueOnError = true, ...
                        progressFcn = @(i,n,f) obj.updateProgress(d, i, n, f), ...
                        cancelRequestedFcn = @() d.CancelRequested);
                end

                obj.Data = S;
                obj.LoadStatusLabel.Text = obj.makeLoadSummaryText(S);
                obj.DiagnosticsTable.Data = obj.buildDiagnosticsTable(S);
                obj.updateDiagnosticsStatus();
                obj.refreshGroupChoices();
                obj.savePreferences();
                obj.onRecompute();
            catch ME
                uialert(obj.Fig, ME.message, "Load Failed");
                obj.LoadStatusLabel.Text = "Load failed.";
            end

            clear c
        end
