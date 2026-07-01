function tf = cursorOverAxes(obj)
%cursorOverAxes  True when the pointer is inside any owned axes (pixel coords).
%   Checked before every mouse gesture so the viewer only reacts when the
%   pointer is actually over one of its axes (main, digital, or auxiliary),
%   even when its figure is shared with other content.

tf = testAxes(obj, obj.Axes);
if ~tf; tf = testAxes(obj, obj.DigitalAxes); end
if ~tf; tf = testAxes(obj, obj.AuxAxes); end
end


function tf = testAxes(obj, ax)
%testAxes  True when the pointer is inside AX's pixel bounding box.
if isempty(ax) || ~isvalid(ax) || isempty(obj.Figure) || ~isvalid(obj.Figure)
    tf = false;
    return
end
pp = getpixelposition(ax, true);
cp = obj.Figure.CurrentPoint;
tf = cp(1) >= pp(1) && cp(1) <= pp(1) + pp(3) && cp(2) >= pp(2) && cp(2) <= pp(2) + pp(4);
end
