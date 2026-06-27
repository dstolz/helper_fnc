function buildUI(obj)
%buildUI  Create the figure and the five tabs.

pos = [120 90 1180 760];   % default; overridden by saved pref in loadPreferences
obj.Fig = uifigure("Name", "Intan -> Kilosort4", "Position", pos);
obj.Fig.CloseRequestFcn = @(~,~) obj.onClose();

obj.Tabs = uitabgroup(obj.Fig, "Units", "normalized", "Position", [0 0 1 1]);

obj.TabDatasets  = uitab(obj.Tabs, "Title", "Datasets");
obj.TabVisualize = uitab(obj.Tabs, "Title", "Visualize");
obj.TabArtifacts = uitab(obj.Tabs, "Title", "Artifacts");
obj.TabProbe     = uitab(obj.Tabs, "Title", "Probe");
obj.TabKilosort  = uitab(obj.Tabs, "Title", "Kilosort");
obj.TabReview    = uitab(obj.Tabs, "Title", "Review");

obj.buildDatasetsTab();
obj.buildVisualizeTab();
obj.buildArtifactsTab();
obj.buildProbeTab();
obj.buildKilosortTab();
obj.buildReviewTab();
end
