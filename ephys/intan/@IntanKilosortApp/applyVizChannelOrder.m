function applyVizChannelOrder(obj)
%applyVizChannelOrder  Apply or clear the Viewer's channel display order per
%   the "Sort by probe map" checkbox, using the probe assigned to the
%   currently-loaded Visualize dataset (IntanDataset.ProbeFile) and the
%   channel list last plotted (obj.VizChannels). Safe to call any time -- a
%   no-op when there is no live Viewer -- and never re-reads or re-filters
%   data, so it can run directly off the checkbox as well as after every Plot.

if isempty(obj.Viewer) || ~isvalid(obj.Viewer); return; end

sortOn = ~isempty(obj.VizSortByProbeCheckBox) && isvalid(obj.VizSortByProbeCheckBox) ...
    && logical(obj.VizSortByProbeCheckBox.Value);
if ~sortOn
    obj.Viewer.setChannelOrder([]);
    return
end

d = obj.currentVizDataset();
pf = "";
if ~isempty(d); pf = string(d.ProbeFile); end

order = probeDepthOrder(pf, obj.VizChannels);
obj.Viewer.setChannelOrder(order);
end


function order = probeDepthOrder(pf, chans)
%probeDepthOrder  Permutation of 1:numel(chans) that sorts the given 1-based
%   .bin channel list by probe shank/depth (ascending kcoords, then yc), per
%   the probe .json's chanMap/xc/yc/kcoords (the same fields plotProbeArrangement
%   in onProbeSelected.m reads). Channels not present in the probe map are
%   pushed to the end, in their original relative order. Falls back to
%   identity order (1:numel(chans)) when the probe file is missing, unreadable,
%   or lacks geometry.
n = numel(chans);
order = 1:n;
if pf == "" || ~isfile(pf); return; end
try
    probe = jsondecode(fileread(pf));
catch
    return
end
if ~isfield(probe, 'yc') || isempty(probe.yc); return; end

yc = double(probe.yc(:));
nSite = numel(yc);
if isfield(probe, 'kcoords') && numel(probe.kcoords) >= nSite
    kc = double(probe.kcoords(1:nSite));
else
    kc = zeros(nSite, 1);
end
if isfield(probe, 'chanMap') && numel(probe.chanMap) >= nSite
    binCh = double(probe.chanMap(1:nSite)) + 1;
else
    binCh = (1:nSite).';
end

shank = Inf(n, 1);
depth = Inf(n, 1);
for k = 1:n
    site = find(binCh == chans(k), 1);
    if ~isempty(site)
        shank(k) = kc(site);
        depth(k) = yc(site);
    end
end
[~, order] = sortrows([shank, depth, (1:n).'], [1 2 3]);
order = order(:).';
end
