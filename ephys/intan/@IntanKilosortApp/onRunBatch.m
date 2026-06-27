function onRunBatch(obj, mode)
%onRunBatch  Batch .bin writing and/or Kilosort4 over the selected datasets.
%   mode = "bin"      -> stream a .bin for each selected dataset (IntanDataset.toBin)
%   mode = "kilosort" -> ensure a .bin exists, then spawn Kilosort4
%                        (IntanDataset.runKilosort) for each selected dataset.
%
%   Datasets are those ticked in the Datasets tab "Select" column (or all when
%   none are ticked).
%
%   The Execution dropdown selects how Kilosort4 runs:
%     Non-blocking (default)  each KS4 process is launched detached; the loop
%                             returns quickly and a background timer polls each
%                             run's ks4_status.json, logging completions.
%     Blocking                each KS4 run is waited on in turn (UI freezes).
%   Either way, any missing .bin is written synchronously first (that streaming
%   step is in-process MATLAB work and always blocks). The "Write .bin" button
%   is always synchronous.

if isempty(obj.Project) || obj.Project.NumDatasets == 0
    uialert(obj.Fig, "Scan a parent directory first.", "Batch");
    return
end

idx = obj.selectedDatasetIndices();
if isempty(idx)
    uialert(obj.Fig, "No datasets selected.", "Batch");
    return
end

% Persist config and push shared settings into the project/datasets.
obj.savePreferences();
obj.applyConfigToProject();

dryRun   = obj.DryRunCheckBox.Value;
blocking = logical(obj.ExecModeDropDown.Value);   % false = background (default)
[extra, perr] = obj.buildKS4Extra();
if strlength(perr) > 0
    uialert(obj.Fig, "Kilosort4 settings are invalid: " + perr, "Batch");
    return
end

% Disable run buttons during the synchronous portion of the batch.
obj.WriteBinButton.Enable = "off";
obj.RunKilosortButton.Enable = "off";
cleanup = onCleanup(@() restoreButtons(obj));

n = numel(idx);
dlg = uiprogressdlg(obj.Fig, "Title", titleFor(mode), "Value", 0, "Cancelable", "on");
obj.log("=== %s batch: %d dataset(s)%s ===", upper(mode), n, modeLabel(mode, dryRun, blocking));

nOK = 0; nFail = 0;
launched = emptyRunStruct();
for j = 1:n
    if dlg.CancelRequested
        obj.log("Cancelled by user after %d dataset(s).", j-1);
        break
    end
    d = obj.Project.Datasets(idx(j));
    dlg.Value = (j-1) / n;
    dlg.Message = sprintf("%d/%d: %s", j, n, d.Name);
    obj.KSProgressLabel.Text = sprintf("%s %d/%d: %s", titleFor(mode), j, n, d.Name);
    drawnow;

    try
        if mode == "bin"
            obj.log("[%d/%d] toBin: %s", j, n, d.Name);
            info = d.toBin();   % broadband, unfiltered; KS4 filters internally
            obj.log("    wrote %s (%.1f MB, %d ch, fs=%g)", info.filename, ...
                info.nBytes/1e6, info.nChan, info.fs);
            if isfield(info, 'autoArtifact') && info.autoArtifact.enabled
                obj.log("    auto-blanked %d samples (%.3f%%) in %d interval(s)", ...
                    info.nAutoBlanked, info.autoArtifact.pctDuration, ...
                    info.autoArtifact.nIntervals);
            end
        else  % kilosort
            if ~dryRun && ~isfile(d.BinFile)
                obj.log("[%d/%d] .bin missing -> toBin first: %s", j, n, d.Name);
                d.toBin();
            end
            obj.log("[%d/%d] runKilosort (%s): %s", j, n, ...
                ternary(blocking, "blocking", "background"), d.Name);
            res = d.runKilosort(ExtraSettings=extra, DryRun=dryRun, Wait=blocking);
            if dryRun
                obj.log("    [dry run] wrote %s", res.settingsPath);
            elseif blocking
                obj.log("    status=%d, results in %s", res.status, res.resultsDir);
            else
                obj.log("    launched in background -> %s", res.resultsDir);
                launched(end+1) = struct('Name', d.Name, ...
                    'statusFile', string(res.statusFile), ...
                    'resultsDir', string(res.resultsDir), ...
                    'logFile', string(res.stdoutLog), 'logPos', 0, ...
                    'done', false); %#ok<AGROW>
            end
        end
        nOK = nOK + 1;
    catch ME
        nFail = nFail + 1;
        obj.log("    ERROR (%s): %s", d.Name, ME.message);
    end
    obj.refreshDatasetsTable();
end

if isvalid(dlg); close(dlg); end

if isempty(launched)
    % Synchronous batch (bin / dry run / blocking) is fully finished here.
    obj.KSProgressLabel.Text = sprintf("Done: %d ok, %d failed.", nOK, nFail);
    obj.log("=== finished: %d ok, %d failed ===", nOK, nFail);
else
    % Hand the background runs to the polling monitor.
    obj.KSRuns = [obj.KSRuns, launched];
    obj.startKSMonitor();
    obj.KSProgressLabel.Text = sprintf("Launched %d background run(s); monitoring...", numel(launched));
    obj.log("=== launched %d background run(s); monitoring for completion ===", numel(launched));
end
end


%% ---- helpers ----------------------------------------------------------

function t = titleFor(mode)
if mode == "bin"; t = "Writing .bin"; else; t = "Running Kilosort4"; end
end

function s = modeLabel(mode, dryRun, blocking)
%modeLabel  Short bracketed tag describing the batch mode for the log header.
if mode == "bin"
    s = "";
elseif dryRun
    s = " [DRY RUN]";
elseif blocking
    s = " [BLOCKING]";
else
    s = " [BACKGROUND]";
end
end

function s = emptyRunStruct()
%emptyRunStruct  0x0 struct with the fields tracked for background runs.
s = struct('Name', {}, 'statusFile', {}, 'resultsDir', {}, ...
    'logFile', {}, 'logPos', {}, 'done', {});
end

function restoreButtons(obj)
if isvalid(obj.WriteBinButton);    obj.WriteBinButton.Enable = "on"; end
if isvalid(obj.RunKilosortButton); obj.RunKilosortButton.Enable = "on"; end
end

function out = ternary(c, a, b)
if c; out = a; else; out = b; end
end
