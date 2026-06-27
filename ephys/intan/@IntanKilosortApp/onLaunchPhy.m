function onLaunchPhy(obj)
%onLaunchPhy  Open phy's template-gui on the selected dataset's KS4 results.
%   Resolves the kilosort4 results directory for the dataset last selected in
%   the Datasets tab, checks that a params.py exists there, then launches phy
%   detached so the app stays responsive. The launch command comes from the
%   "Phy command" field (default "phy"); phy reads params.py relative to its
%   working directory, so the launcher cd's into the results dir first.
%
%   See also IntanKilosortApp.onRunBatch, IntanDataset.runKilosort.

d = obj.currentDataset();
if isempty(d)
    uialert(obj.Fig, "Select a dataset row in the Datasets tab first.", "phy");
    return
end

% Keep each dataset's OutputDir in sync with the current Output root so the
% results path matches what Kilosort4 actually wrote.
obj.applyConfigToProject();

resultsDir = fullfile(char(d.outputFolder()), 'kilosort4');
paramsPy   = fullfile(resultsDir, 'params.py');
if ~isfile(paramsPy)
    uialert(obj.Fig, sprintf(['No Kilosort4 results for "%s".' newline ...
        'Expected params.py in:' newline '%s'], d.Name, resultsDir), "phy");
    return
end

phyCmd = strtrim(char(obj.PhyCmdField.Value));
if isempty(phyCmd); phyCmd = 'phy'; end

% Launch detached. phy resolves params.py against the working directory.
inner = sprintf('%s template-gui params.py', phyCmd);
if ispc
    % start returns immediately; cmd /s /c keeps the inner quotes verbatim.
    cmd = sprintf('start "phy" cmd /s /c "cd /d "%s" && %s"', resultsDir, inner);
else
    cmd = sprintf('cd "%s" && %s &', resultsDir, inner);
end

obj.log("Launching phy for %s in %s", d.Name, resultsDir);
obj.log("  %s", inner);
status = system(cmd);
if status ~= 0
    obj.log("  phy launch returned status %d", status);
    uialert(obj.Fig, sprintf(['phy launch returned status %d.' newline ...
        'Check that the Phy command (''%s'') is valid and on PATH.'], ...
        status, phyCmd), "phy");
end
end
