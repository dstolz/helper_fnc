function render(obj)
%render  Draw the current viewport (visible time window x visible channel
%   window) of the cached data, in the current Mode. Only the visible sample
%   range and visible channel range are ever sliced/decimated, and existing
%   graphics objects are reused (XData/YData/CData updated in place) so
%   panning/zooming/scrolling never recreates graphics except when the mode or
%   the number of visible channels changes.

if obj.Initializing; return; end
if isempty(obj.Data) || ~isfield(obj.Data, 'X') || isempty(obj.Data.X); return; end
if isempty(obj.Axes) || ~isvalid(obj.Axes); return; end

D = obj.Data;
Fs = D.Fs; nSamp = D.nSamp; nCh = D.nCh;

% --- clamp the time viewport to the cached span ---
tWin = min(max(obj.TimeWindowDuration, 5 / Fs), nSamp / Fs);
maxLeft = max(0, nSamp / Fs - tWin);
tLeft = min(max(obj.TimeWindowStart, 0), maxLeft);
obj.TimeWindowDuration = tWin;
obj.TimeWindowStart = tLeft;

% --- clamp the channel viewport to the loaded channel count ---
nvc = min(max(round(obj.NumVisibleChannels), 1), nCh);
maxFirst = max(1, nCh - nvc + 1);
fvc = min(max(round(obj.FirstVisibleChannel), 1), maxFirst);
obj.NumVisibleChannels = nvc;
obj.FirstVisibleChannel = fvc;

i0 = max(1, floor(tLeft * Fs) + 1);
i1 = min(nSamp, i0 + max(1, round(tWin * Fs)) - 1);
chIdx = fvc:(fvc + nvc - 1);

% --- map display position -> data column, per ChannelOrder (identity if unset) ---
order = obj.ChannelOrder;
if numel(order) == nCh
    dataIdx = order(chIdx);
else
    dataIdx = chIdx;
end

seg = D.X(i0:i1, dataIdx);          % [m x nvc], visible samples/channels only
tt  = (i0-1:i1-1).' / Fs;           % [m x 1] absolute time (s)

% --- (re)build the main axes' graphics when the mode changes ---
if obj.DrawnMode ~= obj.Mode
    cla(obj.Axes, 'reset');
    obj.Lines = gobjects(0, 1);
    obj.Image = gobjects(0);
    if ~isempty(obj.Colorbar) && isvalid(obj.Colorbar)
        delete(obj.Colorbar);
    end
    obj.Colorbar = gobjects(0);
    obj.DrawnMode = obj.Mode;
    xlabel(obj.Axes, "Time (s)");
    hold(obj.Axes, 'on');
end

if obj.Mode == "heatmap"
    obj.renderHeatmap(seg, tt, dataIdx);
else
    obj.renderTraces(seg, tt, dataIdx);
end
obj.DrawnChannelWindow = [fvc, nvc];

xlim(obj.Axes, [tt(1), tt(end)]);
title(obj.Axes, sprintf("%.3f-%.3f s (win %.3f s)  |  gain x%.2f  |  ch %d-%d of %d  |  Fs=%g Hz", ...
    tLeft, tLeft + tWin, tWin, obj.AmpGain, fvc, fvc + nvc - 1, nCh, Fs), "Interpreter", "none");

if obj.HasDigitalTracks
    obj.renderDigital(tt, i0, i1);
    xlim(obj.DigitalAxes, [tt(1), tt(end)]);
end
if obj.HasAuxTracks
    obj.renderAux(tt, i0, i1);
    xlim(obj.AuxAxes, [tt(1), tt(end)]);
end

if ~isempty(obj.PostRenderFcn)
    obj.PostRenderFcn();
end
drawnow limitrate
end
