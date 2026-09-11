function onLaunchPhy(obj)
%onLaunchPhy  Open phy's template-gui on the selected dataset's KS4 results.
%   Resolves the kilosort4 results directory for the dataset last selected in
%   the Datasets tab and hands it to launchPhy, which checks for params.py and
%   launches phy detached so the app stays responsive.
%
%   See also IntanKilosortApp.launchPhy, IntanKilosortApp.onRunBatch,
%   IntanDataset.runKilosort.

d = obj.currentDataset();
if isempty(d)
    uialert(obj.Fig, "Select a dataset row in the Datasets tab first.", "phy");
    return
end

% Keep each dataset's OutputDir in sync with the current Output root so the
% results path matches what Kilosort4 actually wrote.
obj.applyConfigToProject();

% Resolve the folder that actually holds params.py. For the SpikeInterface
% engine this is <kilosort4>/si/sorter_output (see kilosortResultsDir); for the
% legacy engine it is <kilosort4> directly.
obj.launchPhy(d.kilosortResultsDir(), d.Name);
end
