function drawVizArtifacts(obj)
%drawVizArtifacts  Redraw the manual artifact regions on the Visualize axes.
%   Clears any previously drawn xregion handles and repaints one shaded region
%   per period in the current dataset's ManualArtifacts, converted from
%   recording-relative seconds to the displayed (loaded-window) time axis.
%   Called at the end of renderViz so the regions survive pan/zoom and the
%   cla() that happens when the plot mode changes.

ax = obj.VizAxes;

% Drop the previous regions (some handles may already be invalid after a cla).
old = obj.VizArtPatches;
for k = 1:numel(old)
    if isgraphics(old(k)); delete(old(k)); end
end
obj.VizArtPatches = gobjects(0, 1);

d = obj.currentVizDataset();
if isempty(d) || isempty(d.ManualArtifacts); return; end

tOff = 0;
if isfield(obj.VizData, 'tOffset'); tOff = obj.VizData.tOffset; end
iv = d.ManualArtifacts - tOff;            % -> displayed-axis seconds

h = gobjects(size(iv, 1), 1);
for k = 1:size(iv, 1)
    h(k) = xregion(ax, iv(k, 1), iv(k, 2), ...
        'FaceColor', [0.85 0.2 0.2], 'FaceAlpha', 0.18);
end
obj.VizArtPatches = h;
end
