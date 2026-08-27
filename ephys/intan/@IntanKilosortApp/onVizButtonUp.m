function onVizButtonUp(obj)
%onVizButtonUp  End an in-progress drag gesture (artifact marking or pan).
%   Finalizes an artifact-marking gesture first (it owns the plain left
%   button); otherwise delegates to obj.Viewer, which owns the pan gesture and
%   clears its own WindowButtonMotionFcn.

if isstruct(obj.VizArtDrag) && isfield(obj.VizArtDrag, 'active') && obj.VizArtDrag.active
    obj.finishVizArtDrag();
    return
end

if ~isempty(obj.Viewer) && isvalid(obj.Viewer)
    obj.Viewer.onButtonUp();
end
end
