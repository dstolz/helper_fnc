function drawVizArtifacts(obj)
%drawVizArtifacts  Redraw the artifact regions on the Visualize axes.
%   Clears any previously drawn xregion handles and repaints both:
%     - automatically detected artifacts (orange) for the loaded window, cached
%       in obj.VizDetectedIntervals (window-relative seconds);
%     - manually marked periods (red) from the current dataset's ManualArtifacts,
%       converted from recording-relative to the displayed time axis.
%   Passed to obj.Viewer as PostRenderFcn, so it runs after every render (pan,
%   zoom, scroll, mode change) and the regions always survive.

ax = obj.VizAxes;

% Drop the previous regions (some handles may already be invalid after a
% mode-change cla inside the viewer).
old = obj.VizArtPatches;
for k = 1:numel(old)
    if isgraphics(old(k)); delete(old(k)); end
end
obj.VizArtPatches = gobjects(0, 1);

h = gobjects(0, 1);

% Detected artifacts (orange) - already in displayed-window seconds.
det = obj.VizDetectedIntervals;
for k = 1:size(det, 1)
    h(end+1, 1) = xregion(ax, det(k, 1), det(k, 2), ...
        'FaceColor', [0.95 0.6 0.1], 'FaceAlpha', 0.15); %#ok<AGROW>
end

% Manual artifacts (red) - recording-relative, shifted onto the displayed axis.
d = obj.currentVizDataset();
if ~isempty(d) && ~isempty(d.ManualArtifacts)
    tOff = obj.VizTimeOffset;
    iv = d.ManualArtifacts - tOff;        % -> displayed-axis seconds
    for k = 1:size(iv, 1)
        h(end+1, 1) = xregion(ax, iv(k, 1), iv(k, 2), ...
            'FaceColor', [0.85 0.2 0.2], 'FaceAlpha', 0.18); %#ok<AGROW>
    end
end

obj.VizArtPatches = h;
end
