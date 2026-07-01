function setMode(obj, m)
%setMode  Switch between "traces" and "heatmap" display modes.
arguments
    obj
    m (1,1) string {mustBeMember(m, ["traces","heatmap"])}
end
obj.Mode = m;
obj.render();
end
