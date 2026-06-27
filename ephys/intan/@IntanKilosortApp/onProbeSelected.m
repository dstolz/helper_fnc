function onProbeSelected(obj)
%onProbeSelected  Show probe metadata and run the simple channel-count check.

pf = obj.selectedProbeFile();
if pf == "" || ~isfile(pf)
    obj.ProbeInfoLabel.Text = "Select a probe.";
    obj.ProbeCheckLabel.Text = "";
    cla(obj.ProbePreviewAxes);
    return
end

[nProbe, info] = probeChannelCount(pf);

% Compare against the currently selected dataset.
d = obj.currentDataset();
exclude = double.empty(1,0);
if ~isempty(d); exclude = IntanDataset.parseChannelList(d.ExcludeChannels); end

plotProbeArrangement(obj.ProbePreviewAxes, pf, exclude);
[~, pn, pe] = fileparts(pf);
obj.ProbeInfoLabel.Text = sprintf("%s%s\nn_chan: %s\n%s", pn, pe, ...
    num2str(nProbe), info);

if isempty(d) || isnan(d.NumChannels)
    obj.ProbeCheckLabel.Text = "Select a dataset (Datasets tab) to check channel count.";
    obj.ProbeCheckLabel.FontColor = [0.4 0.4 0.4];
    return
end

% Excluded channels are dropped from the probe at run time; report how many
% sites Kilosort will actually sort.
exTxt = "";
if ~isempty(exclude)
    exTxt = sprintf(" | %d excluded -> %d sorted", ...
        numel(exclude), d.NumChannels - numel(exclude));
end

if isnan(nProbe)
    obj.ProbeCheckLabel.Text = "Could not read channel count from probe JSON." + exTxt;
    obj.ProbeCheckLabel.FontColor = [0.85 0.5 0];
elseif nProbe == d.NumChannels
    obj.ProbeCheckLabel.Text = sprintf("OK: probe %d ch matches '%s' (%d ch)%s.", ...
        nProbe, d.Name, d.NumChannels, exTxt);
    obj.ProbeCheckLabel.FontColor = [0 0.5 0];
else
    obj.ProbeCheckLabel.Text = sprintf("MISMATCH: probe %d ch vs '%s' %d ch%s.", ...
        nProbe, d.Name, d.NumChannels, exTxt);
    obj.ProbeCheckLabel.FontColor = [0.8 0 0];
end
end


function [n, info] = probeChannelCount(pf)
%probeChannelCount  Return n_chan (else numel(chanMap)) and a short summary.
n = NaN;
try
    probe = jsondecode(fileread(pf));
catch ME
    info = "invalid JSON: " + string(ME.message);
    return
end
if isfield(probe, 'n_chan')
    n = probe.n_chan;
elseif isfield(probe, 'chanMap')
    n = numel(probe.chanMap);
end
parts = strings(0,1);
if isfield(probe, 'chanMap'); parts(end+1) = "chanMap: " + numel(probe.chanMap); end
if isfield(probe, 'kcoords')
    parts(end+1) = "shanks: " + numel(unique(probe.kcoords));
end
info = strjoin(parts, "  |  ");
end


function plotProbeArrangement(ax, pf, exclude)
%plotProbeArrangement  Scatter the probe sites (xc/yc), colored by shank.
%   EXCLUDE (1-based .bin channels) marks dropped sites with a gray X.
if nargin < 3; exclude = double.empty(1,0); end
cla(ax);
try
    probe = jsondecode(fileread(pf));
catch
    title(ax, "Channel arrangement (unreadable)");
    return
end
if ~isfield(probe, 'xc') || ~isfield(probe, 'yc') ...
        || isempty(probe.xc) || isempty(probe.yc)
    title(ax, "Channel arrangement (no xc/yc)");
    return
end

xc = double(probe.xc(:));
yc = double(probe.yc(:));
n  = min(numel(xc), numel(yc));
xc = xc(1:n); yc = yc(1:n);

if isfield(probe, 'kcoords') && numel(probe.kcoords) >= n
    kcoords = double(probe.kcoords(1:n));
else
    kcoords = zeros(n, 1);
end

% Map each site to its 1-based .bin channel (chanMap value + 1; identity if
% no chanMap) so the excluded set can be highlighted.
if isfield(probe, 'chanMap') && numel(probe.chanMap) >= n
    binCh = double(probe.chanMap(1:n)) + 1;
else
    binCh = (1:n).';
end
isExcl = ismember(binCh, exclude(:));

hold(ax, "on");
shanks = unique(kcoords);
cmap = lines(max(numel(shanks), 1));
for s = 1:numel(shanks)
    m = kcoords == shanks(s) & ~isExcl;
    scatter(ax, xc(m), yc(m), 36, cmap(s,:), "filled", ...
        "MarkerEdgeColor", [0.2 0.2 0.2], ...
        "DisplayName", sprintf("shank %g", shanks(s)));
end
if any(isExcl)
    scatter(ax, xc(isExcl), yc(isExcl), 48, [0.5 0.5 0.5], "x", ...
        "LineWidth", 1.5, "DisplayName", "excluded");
end
hold(ax, "off");

axis(ax, "equal");
grid(ax, "on");
title(ax, sprintf("Channel arrangement (%d sites, %d excluded)", n, nnz(isExcl)));
xlabel(ax, "x (\mum)");
ylabel(ax, "y (\mum)");
if numel(shanks) > 1 || any(isExcl)
    legend(ax, "Location", "eastoutside");
end
end
