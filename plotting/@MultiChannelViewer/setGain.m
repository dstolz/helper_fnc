function setGain(obj, factor)
%setGain  Multiply AmpGain by FACTOR, clamped to [1e-3, 1e4].
arguments
    obj
    factor (1,1) double {mustBePositive}
end
obj.AmpGain = min(max(obj.AmpGain * factor, 1e-3), 1e4);
obj.render();
end
