function cfg = gatherKilosortConfig(obj)
%gatherKilosortConfig  Collect the Kilosort tab settings into a struct.
%   Returns a struct that round-trips through onSaveConfig/onLoadConfig and the
%   getpref store. The KS4 parameter controls (per kilosortParamSpec) are stored
%   verbatim under cfg.Params keyed by settings name; buildKS4Extra turns them
%   into the typed settings actually passed to Kilosort4.

cfg = struct();
cfg.PythonExe   = char(obj.PythonExeField.Value);
cfg.CondaEnv    = char(obj.CondaEnvField.Value);
cfg.OutputRoot  = char(obj.OutputRootField.Value);

% SpikeInterface preprocessing config (see IntanDataset.SIConfig).
cfg.SIConfig    = obj.gatherSIConfig();

% KS4 parameters, raw as entered in the controls.
cfg.Params = struct();
spec = obj.kilosortParamSpec();
for i = 1:numel(spec)
    name = spec(i).name;
    cfg.Params.(name) = obj.ParamControls.(name).Value;
end

cfg.ExtraSettings = strjoin(string(obj.ExtraSettingsArea.Value(:)), newline);
end
