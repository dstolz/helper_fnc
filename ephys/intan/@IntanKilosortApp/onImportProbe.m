function onImportProbe(obj)
%onImportProbe  Copy an external probe .json into the probe folder.

[f, p] = uigetfile({'*.json', 'Kilosort4 probe (*.json)'}, "Select a probe .json to import");
figure(obj.Fig);
if isequal(f, 0); return; end
src = fullfile(p, f);

folder = string(obj.ProbeFolderField.Value);
if folder == "" || ~isfolder(folder)
    folder = string(obj.defaultProbeFolder());
end
if ~isfolder(folder); mkdir(folder); end

dst = fullfile(folder, f);
if isfile(dst)
    sel = uiconfirm(obj.Fig, sprintf("%s already exists in the probe folder. Overwrite?", f), ...
        "Import probe", "Options", {'Overwrite','Cancel'}, "DefaultOption", 2);
    if sel ~= "Overwrite"; return; end
end

[ok, msg] = copyfile(src, dst);
if ~ok
    uialert(obj.Fig, "Copy failed: " + string(msg), "Import probe");
    return
end
obj.refreshProbeList();
row = find(obj.ProbePaths == string(dst), 1);
if ~isempty(row)
    obj.selectProbeRow(row);
end
end
