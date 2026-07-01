function onButtonUp(obj)
%onButtonUp  End an in-progress pan gesture and stop tracking pointer motion.

if ~isstruct(obj.Pan) || ~isfield(obj.Pan, 'active') || ~obj.Pan.active
    return
end
obj.Pan.active = false;
if ~isempty(obj.Figure) && isvalid(obj.Figure)
    obj.Figure.WindowButtonMotionFcn = '';
end
end
