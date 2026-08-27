function onVizButtonDown(obj)
%onVizButtonDown  Begin a drag gesture on the Visualize axes.
%   In artifact-marking mode a plain left-press ('normal') starts a rubber-band
%   that defines an artifact period (see finishVizArtDrag) -- this app-specific
%   gesture takes precedence over ordinary panning. Otherwise the gesture is
%   delegated to obj.Viewer (a MultiChannelViewer), which owns middle-button
%   (or Shift+Left) drag-to-pan.

if ~obj.vizActive(); return; end
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

if isempty(obj.Viewer) || ~isvalid(obj.Viewer); return; end
obj.Viewer.onButtonDown();
end
