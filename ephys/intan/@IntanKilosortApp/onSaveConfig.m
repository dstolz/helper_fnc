function onSaveConfig(obj)
%onSaveConfig  Write the current Kilosort config to a JSON file for reuse.

cfg = obj.gatherKilosortConfig();

defaultDir = char(obj.defaultConfigFolder());
if ~isfolder(defaultDir); mkdir(defaultDir); end
[f, p] = uiputfile({'*.json', 'Kilosort config (*.json)'}, ...
    "Save Kilosort configuration", fullfile(defaultDir, "ks4_config.json"));
figure(obj.Fig);
if isequal(f, 0); return; end

try
    txt = jsonencode(cfg, 'PrettyPrint', true);
catch
    txt = jsonencode(cfg);
end
fid = fopen(fullfile(p, f), 'w');
if fid < 0
    uialert(obj.Fig, "Could not open file for writing.", "Save config");
    return
end
fwrite(fid, txt, 'char');
fclose(fid);

obj.KSProgressLabel.Text = sprintf("Saved config to %s", fullfile(p, f));
end
