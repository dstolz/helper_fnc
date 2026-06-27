function onDatasetCellSelection(obj, evt)
%onDatasetCellSelection  Track the last-clicked row as the active dataset.
%   Used by the Visualize and Probe tabs as the single-dataset target.

if isempty(evt.Indices)
    return
end
obj.SelectedRow = evt.Indices(1);

% Keep the Visualize dataset dropdown in sync with the clicked row.
if ~isempty(obj.Project) && obj.SelectedRow >= 1 ...
        && obj.SelectedRow <= obj.Project.NumDatasets
    data = obj.VizDatasetDropDown.ItemsData;
    if iscell(data) && any(cellfun(@(x) isequal(x, obj.SelectedRow), data))
        obj.VizDatasetDropDown.Value = obj.SelectedRow;
        obj.populateVizFiles();
    end
end

% Reflect the newly selected dataset's per-recording channel exclusions.
obj.syncExcludeField();

% Refresh the probe channel-count check against the newly selected dataset.
obj.onProbeSelected();
end
