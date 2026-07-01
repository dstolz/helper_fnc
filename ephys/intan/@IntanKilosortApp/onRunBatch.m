function onRunBatch(obj, mode)
%onRunBatch  Batch SpikeInterface -> Kilosort4 over the selected datasets.
%   For each selected dataset, IntanDataset.runSpikeInterface reads the recording
%   with SpikeInterface, attaches the probe, applies the SIConfig preprocessing
%   chain (bad-channel detection, artifact silencing, optional CMR/filter), and
%   runs Kilosort4 through run_sorter. There is no separate .bin step: the
%   conversion is owned by SpikeInterface end to end.
%
%   Datasets are those ticked in the Datasets tab "Select" column (or all when
%   none are ticked). The Execution dropdown selects how each run executes:
%     Non-blocking (default)  each pipeline is launched detached; the loop
%                             returns quickly and a background timer polls each
%                             run's ks4_status.json, logging completions.
%     Blocking                each run is waited on in turn (UI freezes).
%   Dry run writes si_config.json + run_si_ks4.py without spawning.

mode = string(mode);   %#ok<NASGU>  % retained for signature/compat (always kilosort)

if isempty(obj.Project) || obj.Project.NumDatasets == 0
    uialert(obj.Fig, "Scan a parent directory first.", "Batch");
    return
end

idx = obj.selectedDatasetIndices();
if isempty(idx)
    uialert(obj.Fig, "No datasets selected.", "Batch");
    return
end

% Persist config and push shared settings (python/conda/output/SIConfig) down.
obj.savePreferences();
obj.applyConfigToProject();
obj.applyArtifactConfigToProject();   % artifact detector config -> every dataset

dryRun   = obj.DryRunCheckBox.Value;
blocking = logical(obj.ExecModeDropDown.Value);   % false = background (default)
[extra, perr] = obj.buildKS4Extra();
if strlength(perr) > 0
    uialert(obj.Fig, "Kilosort4 settings are invalid: " + perr, "Batch");
    return
end

% Guard the run button during the synchronous portion of the batch.
if isvalid(obj.RunKilosortButton); obj.RunKilosortButton.Enable = "off"; end
cleanup = onCleanup(@() restoreButtons(obj));

n = numel(idx);
dlg = uiprogressdlg(obj.Fig, "Title", "Running Kilosort4", "Value", 0, "Cancelable", "on");
obj.log("=== Kilosort4 batch: %d dataset(s)%s ===", n, modeLabel(dryRun, blocking));

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
    obj.KSProgressLabel.Text = sprintf("Running Kilosort4 %d/%d: %s", j, n, d.Name);
    drawnow;

    try
        obj.log("[%d/%d] runSpikeInterface (%s): %s", j, n, ...
            ternary(blocking, "blocking", "background"), d.Name);
        res = d.runSpikeInterface(ExtraSettings=extra, DryRun=dryRun, Wait=blocking);
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
        nOK = nOK + 1;
    catch ME
        nFail = nFail + 1;
        obj.log("    ERROR (%s): %s", d.Name, ME.message);
    end
    d.writeManifest();   % record the new Kilosort4 output in the manifest
    obj.refreshDatasetsTable();
end

if isvalid(dlg); close(dlg); end

if isempty(launched)
    % Synchronous batch (dry run / blocking) is fully finished here.
    obj.KSProgressLabel.Text = sprintf("Done: %d ok, %d failed.", nOK, nFail);
    obj.log("=== finished: %d ok, %d failed ===", nOK, nFail);
    obj.setStatus(sprintf("Kilosort4 batch finished: %d ok, %d failed.", nOK, nFail), ...
        "Open the Review tab (or 'Open in phy') to inspect results.");
else
    % Hand the background runs to the polling monitor.
    obj.KSRuns = [obj.KSRuns, launched];
    obj.startKSMonitor();
    obj.KSProgressLabel.Text = sprintf("Launched %d background run(s); monitoring...", numel(launched));
    obj.log("=== launched %d background run(s); monitoring for completion ===", numel(launched));
    obj.setStatus(sprintf("Launched %d background run(s); monitoring...", numel(launched)), ...
        "Watch the Kilosort log; results open on the Review tab when done.");
end
end


%% ---- helpers ----------------------------------------------------------

function s = modeLabel(dryRun, blocking)
%modeLabel  Short bracketed tag describing the batch mode for the log header.
if dryRun
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
if isvalid(obj.RunKilosortButton); obj.RunKilosortButton.Enable = "on"; end
end

function out = ternary(c, a, b)
if c; out = a; else; out = b; end
end
