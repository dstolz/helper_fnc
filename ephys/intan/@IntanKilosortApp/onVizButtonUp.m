function onVizButtonUp(obj)
%onVizButtonUp  End an in-progress drag gesture (artifact marking or pan).
%   Clears the motion callback so ordinary pointer movement stops re-rendering.

% Finalize an artifact-marking gesture first (it owns the plain left button).
if isstruct(obj.VizArtDrag) && isfield(obj.VizArtDrag, 'active') && obj.VizArtDrag.active
    obj.finishVizArtDrag();
    return
end

if ~isstruct(obj.VizPan) || ~isfield(obj.VizPan, 'active') || ~obj.VizPan.active
    return
end
obj.VizPan.active = false;
if isvalid(obj.Fig)
    obj.Fig.WindowButtonMotionFcn = '';
end
end
