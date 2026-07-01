function setSpacing(obj, value)
%setSpacing  Set the fixed per-channel trace spacing (0 = auto from Clim0).
arguments
    obj
    value (1,1) double {mustBeNonnegative}
end
obj.TraceSpacing = value;
obj.render();
end
