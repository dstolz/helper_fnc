function onLoadConfig(obj)
%onLoadConfig  Load a Kilosort config JSON and apply it to the UI.

defaultDir = char(obj.defaultConfigFolder());
[f, p] = uigetfile({'*.json', 'Kilosort config (*.json)'}, ...
    "Load Kilosort configuration", defaultDir);
figure(obj.Fig);
if isequal(f, 0); return; end

try
    cfg = jsondecode(fileread(fullfile(p, f)));
catch ME
    uialert(obj.Fig, "Could not read config: " + string(ME.message), "Load config");
    return
end

obj.applyKilosortConfig(cfg);
obj.savePreferences();
obj.KSProgressLabel.Text = sprintf("Loaded config from %s", fullfile(p, f));
end
