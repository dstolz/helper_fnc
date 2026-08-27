function onScan(obj)
%onScan  Build an IntanKilosortProject from the parent dir, gather metadata.

root = string(obj.RootPathField.Value);
if root == "" || ~isfolder(root)
    uialert(obj.Fig, "Select a valid parent directory first.", "Scan");
    return
end

obj.savePreferences();
obj.ScanButton.Enable = "off";
cleanup = onCleanup(@() set(obj.ScanButton, "Enable", "on"));

dlg = uiprogressdlg(obj.Fig, "Title", "Scanning", ...
    "Message", "Discovering *.rhd folders...", "Indeterminate", "on");
drawnow;

try
    % Discovery is cheap (AutoMetadata=false per folder inside discover()).
    P = IntanKilosortProject(root);

    % Push shared config (probe/python/etc) from current UI before metadata.
    obj.applyConfigToProject(P);

    if P.NumDatasets == 0
        close(dlg);
        obj.Project = P;
        obj.refreshDatasetsTable();
        obj.populateDatasetMenu();
        obj.populateArtifactDatasets();
        obj.populateReviewDatasets();
        obj.ScanStatusLabel.Text = sprintf("No *.rhd folders found under %s", root);
        obj.setStatus(sprintf("Scan complete: no *.rhd recordings found under %s.", root), ...
            "Pick a different parent folder and Scan again.");
        return
    end

    % Header-only metadata, one dataset at a time, with progress.
    dlg.Indeterminate = "off";
    n = P.NumDatasets;
    for i = 1:n
        if dlg.CancelRequested; break; end
        dlg.Value = i / n;
        dlg.Message = sprintf("Reading headers %d/%d: %s", i, n, P.Datasets(i).Name);
        try
            P.Datasets(i).refreshMetadata();
        catch ME
            warning('IntanKilosortApp:MetaFailed', ...
                'Metadata failed for %s: %s', P.Datasets(i).Name, ME.message);
        end
    end
    close(dlg);

    % Restore each dataset's saved probe / channel-exclusion assignments from
    % its on-disk manifest (if any), then refresh the manifest so it reflects
    % the freshly parsed metadata and current Kilosort4 output state. The
    % Datasets table is then built from this restored state.
    for i = 1:n
        try
            P.Datasets(i).applyManifest();
            P.Datasets(i).writeManifest();
        catch ME
            warning('IntanKilosortApp:ManifestFailed', ...
                'Manifest update failed for %s: %s', P.Datasets(i).Name, ME.message);
        end
    end

    obj.Project = P;
    obj.refreshDatasetsTable();
    obj.populateDatasetMenu();
    obj.populateArtifactDatasets();
    obj.applyArtifactConfigToProject();   % seed every dataset with the tab's config
    obj.ScanStatusLabel.Text = sprintf("Found %d dataset(s) under %s", n, root);
    obj.setStatus(sprintf("Scanned %s: found %d dataset(s).", root, n));
catch ME
    if isvalid(dlg); close(dlg); end
    uialert(obj.Fig, ME.message, "Scan failed");
    obj.setStatus("Scan failed: " + string(ME.message), ...
        "Check the parent folder path and try Scan again.");
end
end
