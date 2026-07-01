function panTime(obj, dtSeconds)
%panTime  Shift the time window by dtSeconds (positive = forward in time).
arguments
    obj
    dtSeconds (1,1) double
end
obj.TimeWindowStart = obj.TimeWindowStart + dtSeconds;
obj.render();
end
