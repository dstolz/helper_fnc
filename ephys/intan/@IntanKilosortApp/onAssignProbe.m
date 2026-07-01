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
ch = IntanDataset.parseChannelList(obj.ExcludeChannelsField.Value);
nTrim = 0;
for k = 1:numel(targets)
    targets(k).ProbeFile = pf;
    if ~isnan(nProbe) && ~isnan(targets(k).NumChannels) && nProbe ~= targets(k).NumChannels
        mismatch = mismatch + 1;
    end
    if scope == "all"
        keep = ch;
        if ~isnan(targets(k).NumChannels)
            keep = ch(ch <= targets(k).NumChannels);
            nTrim = nTrim + (numel(ch) - numel(keep));
        end
        targets(k).ExcludeChannels = keep;
    end
end

for k = 1:numel(targets)
    targets(k).writeManifest();   % persist the new probe (+ exclusions) assignment
end

obj.refreshDatasetsTable();
[~, pn, pe] = fileparts(pf);
msg = sprintf("Assigned %s to %d dataset(s).", pn + pe, numel(targets));
if scope == "all" && ~isempty(ch)
    msg = msg + sprintf(" Excluded %d channel(s) on all.", numel(ch));
end
if mismatch > 0
    msg = msg + sprintf(" Warning: %d have a channel-count mismatch.", mismatch);
end
if nTrim > 0
    msg = msg + sprintf(" (%d out-of-range channel entr(y/ies) ignored.)", nTrim);
end
obj.ScanStatusLabel.Text = msg;
obj.setStatus(msg);
end


function n = localProbeCount(pf)
n = NaN;
try
    probe = jsondecode(fileread(pf));
    % n_chan, but never fewer than the mapped sites (a 0-based map's max index
    % yields an n_chan one short of numel(chanMap)); fall back to map length.
    nMap = NaN;
    if isfield(probe, 'chanMap'); nMap = numel(probe.chanMap); end
    if isfield(probe, 'n_chan');  n = double(probe.n_chan);    end
    if ~isnan(nMap); n = max([n, nMap], [], 'omitnan'); end
catch
end
end
