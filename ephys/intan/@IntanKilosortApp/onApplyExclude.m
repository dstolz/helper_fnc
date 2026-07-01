function onApplyExclude(obj, scope)
%onApplyExclude  Set per-recording channel exclusions from the Probe tab field.
%   scope = "selected" -> the row last clicked in the Datasets tab (also the
%                         path taken when the edit field is committed)
%   scope = "all"      -> every dataset in the project
%
%   The field holds 1-based channels to drop from Kilosort4 sorting (e.g.
%   "1,5,32-40"). Channels are validated against each dataset's NumChannels;
%   out-of-range entries are dropped with a warning in the status label. The
%   exclusions live on IntanDataset.ExcludeChannels and are applied as a derived
%   probe at run time (see IntanDataset.runKilosort); nothing on disk changes here.

if isempty(obj.Project) || obj.Project.NumDatasets == 0
    return
end

ch = IntanDataset.parseChannelList(obj.ExcludeChannelsField.Value);

switch scope
    case "selected"
        d = obj.currentDataset();
        if isempty(d)
            % Triggered by editing the field with no dataset selected: guide,
            % don't pop a modal (this fires on every commit).
            obj.ScanStatusLabel.Text = ...
                "Select a dataset row (Datasets tab) to apply channel exclusions.";
            obj.setStatus("Channel exclusions not applied: no dataset selected.", ...
                "Click a dataset row on the Datasets tab, then re-enter exclusions.");
            return
        end
        targets = d;
    case "all"
        targets = obj.Project.Datasets;
    otherwise
        return
end

nTrim = 0;
for k = 1:numel(targets)
    t = targets(k);
    keep = ch;
    if ~isnan(t.NumChannels)
        keep = ch(ch <= t.NumChannels);
        nTrim = nTrim + (numel(ch) - numel(keep));
    end
    t.ExcludeChannels = keep;
    t.writeManifest();   % persist the updated exclusions
end

% Reflect the (possibly trimmed) list for the active dataset and redraw.
obj.syncExcludeField();
obj.refreshDatasetsTable();
obj.onProbeSelected();   % refresh the channel-count check / preview marks

if scope == "all"
    msg = sprintf("Excluded %d channel(s) on %d dataset(s).", numel(ch), numel(targets));
else
    msg = sprintf("Excluded %d channel(s) on '%s'.", ...
        numel(targets(1).ExcludeChannels), targets(1).Name);
end
if nTrim > 0
    msg = msg + sprintf(" (%d out-of-range entr(y/ies) ignored.)", nTrim);
end
obj.ScanStatusLabel.Text = msg;
obj.setStatus(msg);
end
