function onVizButtonDown(obj)
%onVizButtonDown  Begin a drag gesture on the Visualize axes.
%   In artifact-marking mode a plain left-press ('normal') starts a rubber-band
%   that defines an artifact period (see finishVizArtDrag). Otherwise a
%   middle-button (or Shift+left, both reported as 'extend') press starts a
%   drag-to-pan: the starting pointer pixel and viewport are recorded so
%   onVizButtonMotion can translate motion into time (and, in traces mode,
%   amplitude) panning.

if ~vizActive(obj); return; end
if ~obj.cursorOverAxes(); return; end

% Artifact marking takes the plain left button when its mode is on.
if obj.VizArtMode && strcmp(obj.Fig.SelectionType, 'normal')
    obj.VizArtDrag = struct( ...
        'active', true, ...
        'x0',     obj.VizAxes.CurrentPoint(1, 1), ...
        'axPix',  getpixelposition(obj.VizAxes, true));
    obj.Fig.WindowButtonMotionFcn = @(~, ~) obj.onVizArtMotion();
    return
end

if ~strcmp(obj.Fig.SelectionType, 'extend'); return; end

obj.VizPan = struct( ...
    'active',   true, ...
    'startPix', obj.Fig.CurrentPoint, ...
    'axPix',    getpixelposition(obj.VizAxes, true), ...
    'tLeft0',   obj.VizView.tLeft, ...
    'yOff0',    obj.VizView.yOffset);
obj.Fig.WindowButtonMotionFcn = @(~, ~) obj.onVizButtonMotion();
end
