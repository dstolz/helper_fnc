function launchPhy(obj, resultsDir, label)
%launchPhy  Run `phy template-gui params.py` detached in RESULTSDIR.
%   RESULTSDIR must be the folder that holds params.py (for the SpikeInterface
%   engine that is <kilosort4>/si/sorter_output). LABEL names the source in
%   the log (e.g. the dataset name). The launch command comes from the "Phy
%   command" field; phy lives in its own conda env (see INSTALL.md), so the
%   default (when the field is blank) runs it via `conda run -n phy phy`,
%   the same "conda run -n <env>" dispatch used for Kilosort4/SpikeInterface
%   (see IntanDataset.runKilosort). phy reads params.py relative to its
%   working directory, so the launcher cd's into the results dir first.
%
%   See also IntanKilosortApp.onLaunchPhy, IntanKilosortApp.onReviewOpenPhy.

resultsDir = char(resultsDir);
paramsPy   = fullfile(resultsDir, 'params.py');
if ~isfile(paramsPy)
    uialert(obj.Fig, sprintf(['No Kilosort4 results for "%s".' newline ...
        'Expected params.py in:' newline '%s'], label, resultsDir), "phy");
    return
end

phyCmd = strtrim(char(obj.PhyCmdField.Value));
if isempty(phyCmd); phyCmd = 'conda run -n phy phy'; end

% Launch detached. phy resolves params.py against the working directory.
inner = sprintf('%s template-gui params.py', phyCmd);
if ispc
    % start returns immediately; cmd /s /c keeps the inner quotes verbatim.
    cmd = sprintf('start "phy" cmd /s /c "cd /d "%s" && %s"', resultsDir, inner);
else
    cmd = sprintf('cd "%s" && %s &', resultsDir, inner);
end

obj.log("Launching phy for %s in %s", label, resultsDir);
obj.log("  %s", inner);
status = system(cmd);
if status ~= 0
    obj.log("  phy launch returned status %d", status);
    uialert(obj.Fig, sprintf(['phy launch returned status %d.' newline ...
        'Check that the Phy command (''%s'') is valid and on PATH.'], ...
        status, phyCmd), "phy");
    return
end
obj.setStatus(sprintf("Launched phy for %s.", label));
end
