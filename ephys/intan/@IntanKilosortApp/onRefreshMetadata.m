function onRefreshMetadata(obj)
%onRefreshMetadata  Force re-parse of headers for all datasets, then refresh.

if isempty(obj.Project) || obj.Project.NumDatasets == 0
    uialert(obj.Fig, "Scan a parent directory first.", "Refresh metadata");
    return
end

n = obj.Project.NumDatasets;
dlg = uiprogressdlg(obj.Fig, "Title", "Refreshing metadata", "Value", 0);
for i = 1:n
    if dlg.CancelRequested; break; end
    dlg.Value = i / n;
    dlg.Message = sprintf("%d/%d: %s", i, n, obj.Project.Datasets(i).Name);
    try
        obj.Project.Datasets(i).refreshMetadata();
    catch ME
        warning('IntanKilosortApp:MetaFailed', ...
            'Metadata failed for %s: %s', obj.Project.Datasets(i).Name, ME.message);
    end
end
close(dlg);

obj.refreshDatasetsTable();
obj.populateVizDatasets();
end
