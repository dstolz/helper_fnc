function setAuxData(obj, data, names)
%setAuxData  Replace or clear the optional auxiliary analog track group.
%   obj.setAuxData(data, names) swaps in a new [nSamples x nAux] continuous
%   analog matrix (same nSamples as the main data), computing a robust
%   per-channel amplitude scale used to normalize each track's display height.
%   obj.setAuxData([]) clears the tracks (the row stays, just empty).
%
%   The auxiliary-track row is only created when AuxData is supplied to the
%   CONSTRUCTOR (see MultiChannelViewer/buildLayout) -- a group cannot be
%   introduced for the first time after construction, since that would require
%   rebuilding the axes layout out from under any already-attached callbacks.

arguments
    obj
    data (:,:) double = []
    names (1,:) string = string.empty(1,0)
end

if isempty(obj.AuxAxes) || ~isvalid(obj.AuxAxes)
    if isempty(data); return; end
    error('MultiChannelViewer:NoAuxRow', ...
        ['This instance was constructed without AuxData, so no auxiliary-track ', ...
         'row exists to update. Pass AuxData at construction time to reserve one.']);
end

if isempty(data)
    obj.Aux = struct([]);
    cla(obj.AuxAxes);
    obj.AuxLines = gobjects(0, 1);
else
    if isempty(obj.Data) || ~isfield(obj.Data, 'X') || isempty(obj.Data.X)
        error('MultiChannelViewer:NoMainData', 'Load the main data before attaching auxiliary tracks.');
    end
    if size(data, 1) ~= obj.Data.nSamp
        error('MultiChannelViewer:SampleMismatch', ...
            'AuxData must have the same number of samples (%d) as the main data.', obj.Data.nSamp);
    end
    nAux = size(data, 2);
    if isempty(names)
        names = "aux" + string(1:nAux);
    elseif numel(names) ~= nAux
        error('MultiChannelViewer:NameCountMismatch', ...
            'AuxNames must have one entry per auxiliary channel (%d).', nAux);
    end

    med = median(data, 1, 'omitnan');
    clim0 = 5 * median(abs(data - med), 1, 'omitnan');
    flat = ~isfinite(clim0) | clim0 <= 0;
    if any(flat)
        fallback = max(abs(data(:, flat)), [], 1, 'omitnan');
        clim0(flat) = fallback;
    end
    clim0(~isfinite(clim0) | clim0 <= 0) = 1;

    obj.Aux = struct('X', double(data), 'nCh', nAux, 'Names', string(names), 'Clim0', clim0);
end

if ~obj.Initializing
    obj.render();
end
end
