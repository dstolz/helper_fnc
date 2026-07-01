function setDigitalData(obj, data, names)
%setDigitalData  Replace or clear the optional digital/event track group.
%   obj.setDigitalData(data, names) swaps in a new [nSamples x nDigital]
%   digital/event matrix (same nSamples as the main data). obj.setDigitalData([])
%   clears the tracks (the row stays, just empty).
%
%   The digital-track row is only created when DigitalData is supplied to the
%   CONSTRUCTOR (see MultiChannelViewer/buildLayout) -- a group cannot be
%   introduced for the first time after construction, since that would require
%   rebuilding the axes layout out from under any already-attached callbacks.

arguments
    obj
    data (:,:) {mustBeNumericOrLogical} = []
    names (1,:) string = string.empty(1,0)
end

if isempty(obj.DigitalAxes) || ~isvalid(obj.DigitalAxes)
    if isempty(data); return; end
    error('MultiChannelViewer:NoDigitalRow', ...
        ['This instance was constructed without DigitalData, so no digital-track ', ...
         'row exists to update. Pass DigitalData at construction time to reserve one.']);
end

if isempty(data)
    obj.Digital = struct([]);
    cla(obj.DigitalAxes);
    obj.DigitalLines = gobjects(0, 1);
else
    if isempty(obj.Data) || ~isfield(obj.Data, 'X') || isempty(obj.Data.X)
        error('MultiChannelViewer:NoMainData', 'Load the main data before attaching digital tracks.');
    end
    if size(data, 1) ~= obj.Data.nSamp
        error('MultiChannelViewer:SampleMismatch', ...
            'DigitalData must have the same number of samples (%d) as the main data.', obj.Data.nSamp);
    end
    nDig = size(data, 2);
    if isempty(names)
        names = "dig" + string(1:nDig);
    elseif numel(names) ~= nDig
        error('MultiChannelViewer:NameCountMismatch', ...
            'DigitalNames must have one entry per digital channel (%d).', nDig);
    end
    obj.Digital = struct('X', double(data ~= 0), 'nCh', nDig, 'Names', string(names));
end

if ~obj.Initializing
    obj.render();
end
end
