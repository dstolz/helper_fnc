function delete(obj)
%delete  Handle-class cleanup: detach the KeyMap and close an owned figure.
%   A caller-supplied Parent/Figure is left untouched.
if ~isempty(obj.KeyMapObj) && isvalid(obj.KeyMapObj) && obj.KeyMapObj.Attached
    obj.KeyMapObj.detach();
end
if obj.OwnsFigure && ~isempty(obj.Figure) && isvalid(obj.Figure)
    close(obj.Figure);
end
end
