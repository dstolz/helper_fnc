function setVisibleChannelCount(obj, n)
%setVisibleChannelCount  Change how many channels are shown at once.
%   Clamped to [1, NumChannels] in render(); FirstVisibleChannel is re-clamped
%   there too so the channel window stays within bounds.
arguments
    obj
    n (1,1) double {mustBePositive, mustBeInteger}
end
obj.NumVisibleChannels = n;
obj.render();
end
