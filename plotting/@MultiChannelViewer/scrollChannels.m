function scrollChannels(obj, deltaChannels)
%scrollChannels  Shift FirstVisibleChannel by deltaChannels (rounded).
%   Positive = later channels. Clamped to valid bounds in render(); a no-op
%   in effect when NumVisibleChannels >= NumChannels.
arguments
    obj
    deltaChannels (1,1) double
end
obj.FirstVisibleChannel = round(obj.FirstVisibleChannel + deltaChannels);
obj.render();
end
