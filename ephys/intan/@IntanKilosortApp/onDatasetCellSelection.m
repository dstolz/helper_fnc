function onDatasetCellSelection(obj, evt)
%onDatasetCellSelection  Track the last-clicked row as the active dataset.
%   Used by the Visualize and Probe tabs as the single-dataset target.

if isempty(evt.Indices)
    return
end
obj.SelectedRow = evt.Indices(1);

% Keep the "Dataset" menu (indexed by dataset order, not table row order) in
% sync with the clicked row via its DatasetIdx.
d = obj.currentDataset();
if ~isempty(d)
    T = obj.DatasetsTable.Data;
    obj.selectDataset(T.DatasetIdx(obj.SelectedRow));
end

% Reflect the newly selected dataset's per-recording channel exclusions.
obj.syncExcludeField();

% Refresh the probe channel-count check against the newly selected dataset.
obj.onProbeSelected();

% Enable/disable "Open in phy" for the newly selected dataset.
obj.updatePhyButtonState();
end
