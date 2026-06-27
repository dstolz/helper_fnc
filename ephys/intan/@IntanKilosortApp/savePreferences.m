function savePreferences(obj)
%savePreferences  Persist paths, Kilosort config, and figure geometry.

g = obj.PrefGroup;

% --- figure position & size ---
if isvalid(obj.Fig)
    setpref(g, 'FigurePosition', obj.Fig.Position);
end

% --- paths ---
setpref(g, 'RootPath',    char(obj.RootPathField.Value));
setpref(g, 'ProbeFolder', char(obj.ProbeFolderField.Value));
setpref(g, 'PhyCmd',      char(obj.PhyCmdField.Value));
setpref(g, 'ReviewFolder', char(obj.ReviewFolderField.Value));

% --- visualize options ---
setpref(g, 'VizChannels', char(obj.VizChannelsField.Value));
setpref(g, 'VizDuration', obj.VizDurField.Value);
setpref(g, 'VizHighpass', char(obj.VizHighpassField.Value));
setpref(g, 'VizLowpass',  char(obj.VizLowpassField.Value));
setpref(g, 'VizOrder',    obj.VizOrderField.Value);
setpref(g, 'VizReference', char(obj.VizRefDropDown.Value));
setpref(g, 'VizDetrend',  obj.VizDetrendCheckBox.Value);
setpref(g, 'VizSpacing',  obj.VizSpacingField.Value);

% --- artifact detection options ---
setpref(g, 'ArtMethod',       char(obj.ArtMethodDropDown.Value));
setpref(g, 'ArtThreshold',    obj.ArtThresholdField.Value);
setpref(g, 'ArtRmsWindowMs',  obj.ArtRmsWindowField.Value);
setpref(g, 'ArtMergeGapMs',   obj.ArtMergeGapField.Value);
setpref(g, 'ArtPadMs',        obj.ArtPadField.Value);
setpref(g, 'ArtMinChannels',  obj.ArtMinChannelsField.Value);
setpref(g, 'ArtFilter',      logical(obj.ArtFilterCheckBox.Value));
setpref(g, 'ArtHighpass',    obj.ArtHighpassField.Value);
setpref(g, 'ArtEnable',      logical(obj.ArtEnableCheckBox.Value));

% --- execution mode ---
setpref(g, 'ExecBlocking', logical(obj.ExecModeDropDown.Value));

% --- kilosort config ---
setpref(g, 'KilosortConfig', obj.gatherKilosortConfig());
end
