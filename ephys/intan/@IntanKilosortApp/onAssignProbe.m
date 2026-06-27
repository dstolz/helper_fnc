function onAssignProbe(obj, scope)
%onAssignProbe  Assign the selected probe .json to one or all datasets.
%   scope = "selected" -> the row last clicked in the Datasets tab
%   scope = "all"      -> every dataset in the project

pf = obj.selectedProbeFile();
if pf == "" || ~isfile(pf)
    uialert(obj.Fig, "Select a probe in the table first.", "Assign probe");
    return
end
if isempty(obj.Project) || obj.Project.NumDatasets == 0
    uialert(obj.Fig, "Scan a parent directory first.", "Assign probe");
    return
end

switch scope
    case "selected"
        d = obj.currentDataset();
        if isempty(d)
            uialert(obj.Fig, "Click a dataset row in the Datasets tab first.", "Assign probe");
            return
        end
        targets = d;
    case "all"
        targets = obj.Project.Datasets;
    otherwise
        return
end

nProbe = localProbeCount(pf);
mismatch = 0;
for k = 1:numel(targets)
    targets(k).ProbeFile = pf;
    if ~isnan(nProbe) && ~isnan(targets(k).NumChannels) && nProbe ~= targets(k).NumChannels
        mismatch = mismatch + 1;
    end
end

obj.refreshDatasetsTable();
[~, pn, pe] = fileparts(pf);
msg = sprintf("Assigned %s to %d dataset(s).", pn + pe, numel(targets));
if mismatch > 0
    msg = msg + sprintf(" Warning: %d have a channel-count mismatch.", mismatch);
end
obj.ScanStatusLabel.Text = msg;
end


function n = localProbeCount(pf)
n = NaN;
try
    probe = jsondecode(fileread(pf));
    if isfield(probe, 'n_chan'); n = probe.n_chan;
    elseif isfield(probe, 'chanMap'); n = numel(probe.chanMap);
    end
catch
end
end
