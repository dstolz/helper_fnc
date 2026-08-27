function applyVizChannelColor(obj)
%applyVizChannelColor  Apply or clear the Viewer's "color by shank" trace
%   coloring per the "Color channels by shank" checkbox, using the probe
%   assigned to the currently-loaded Visualize dataset (IntanDataset.ProbeFile)
%   and the channel list last plotted (obj.VizChannels). Safe to call any time
%   -- a no-op when there is no live Viewer -- and never re-reads or
%   re-filters data, so it can run directly off the checkbox as well as after
%   every Plot.

if isempty(obj.Viewer) || ~isvalid(obj.Viewer); return; end

colorOn = ~isempty(obj.VizColorByShankCheckBox) && isvalid(obj.VizColorByShankCheckBox) ...
    && logical(obj.VizColorByShankCheckBox.Value);
if ~colorOn
    obj.Viewer.setColorByGroup(false);
    return
end

d = obj.currentVizDataset();
pf = "";
if ~isempty(d); pf = string(d.ProbeFile); end

groups = probeShankGroups(pf, obj.VizChannels);
obj.Viewer.setChannelGroups(groups);
obj.Viewer.setColorByGroup(true);
end


function groups = probeShankGroups(pf, chans)
%probeShankGroups  Shank id (kcoords) per 1-based .bin channel in CHANS, per
%   the probe .json's chanMap/kcoords (the same fields plotProbeArrangement in
%   onProbeSelected.m and probeDepthOrder in applyVizChannelOrder.m read).
%   Channels not present in the probe map get shank id 0 (grouped together).
%   Falls back to all-zero groups (a single color) when the probe file is
%   missing, unreadable, or lacks a kcoords field.
n = numel(chans);
groups = zeros(1, n);
if pf == "" || ~isfile(pf); return; end
try
    probe = jsondecode(fileread(pf));
catch
    return
end
if ~isfield(probe, 'kcoords') || isempty(probe.kcoords); return; end

kc = double(probe.kcoords(:));
nSite = numel(kc);
if isfield(probe, 'chanMap') && numel(probe.chanMap) >= nSite
    binCh = double(probe.chanMap(1:nSite)) + 1;
else
    binCh = (1:nSite).';
end

for k = 1:n
    site = find(binCh == chans(k), 1);
    if ~isempty(site)
        groups(k) = kc(site);
    end
end
end
