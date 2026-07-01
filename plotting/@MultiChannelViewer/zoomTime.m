function zoomTime(obj, factor, anchorSeconds)
%zoomTime  Scale the time window by FACTOR, keeping anchorSeconds fixed.
%   factor > 1 zooms out; factor < 1 zooms in. anchorSeconds defaults to the
%   left edge of the current window when omitted.
arguments
    obj
    factor (1,1) double {mustBePositive}
    anchorSeconds (1,1) double = obj.TimeWindowStart
end
obj.TimeWindowStart = anchorSeconds - (anchorSeconds - obj.TimeWindowStart) * factor;
obj.TimeWindowDuration = obj.TimeWindowDuration * factor;
obj.render();
end
