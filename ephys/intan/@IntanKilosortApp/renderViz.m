function renderViz(obj)
%renderViz  Draw the current viewport of the cached data (traces or heatmap).
%   Reads obj.VizData (the cached, already-preprocessed matrix) and obj.VizView
%   (the viewport: tLeft/tWin/ampGain/yOffset/mode) and paints only the visible
%   window. To stay fast while scrolling it (a) slices just the visible samples
%   and (b) decimates them to at most VizPixelBudget points per channel - a
%   min/max envelope for traces (visually lossless for spikes) and per-pixel
%   means for the heatmap. Existing line/image objects are reused (XData/YData/
%   CData updated in place) so panning never recreates graphics.

if isempty(obj.VizData) || ~isfield(obj.VizData, 'X'); return; end

ax = obj.VizAxes;
D  = obj.VizData;
V  = obj.VizView;
Fs = D.Fs; nSamp = D.nSamp;

% --- clamp the viewport to the cached span ---
tWin  = min(max(V.tWin, 5 / Fs), nSamp / Fs);
maxLeft = max(0, nSamp / Fs - tWin);
tLeft = min(max(V.tLeft, 0), maxLeft);
V.tWin = tWin; V.tLeft = tLeft;
obj.VizView = V;

i0  = max(1, floor(tLeft * Fs) + 1);
i1  = min(nSamp, i0 + max(1, round(tWin * Fs)) - 1);
seg = D.X(i0:i1, :);                 % [m x nCh], visible samples only
tt  = (i0-1:i1-1).' / Fs;            % [m x 1] absolute time (s)

% --- (re)build graphics when the mode changes or after a fresh load ---
mode = V.mode;
if obj.VizDrawnMode ~= mode
    cla(ax, 'reset');
    obj.VizLines = [];
    obj.VizImage = [];
    if ~isempty(obj.VizColorbar) && isvalid(obj.VizColorbar)
        delete(obj.VizColorbar);
    end
    obj.VizColorbar = [];
    obj.VizDrawnMode = mode;
    xlabel(ax, "Time (s)");
    hold(ax, 'on');
end

if mode == "heatmap"
    renderHeatmap(obj, ax, seg, tt);
else
    renderTraces(obj, ax, seg, tt);
end

xlim(ax, [tt(1), tt(end)]);
title(ax, sprintf("%s  |  %.3f-%.3f s (win %.3f s)  |  gain x%.2f  |  Fs=%g Hz", ...
    D.name, tLeft, tLeft + tWin, tWin, V.ampGain, Fs), "Interpreter", "none");
obj.drawVizArtifacts();
drawnow limitrate
end


function renderTraces(obj, ax, seg, tt)
%renderTraces  Stacked min/max-decimated traces, one line per channel.
D = obj.VizData; V = obj.VizView;
nCh = D.nCh;

spacing = obj.VizSpacingField.Value;
if spacing <= 0; spacing = 2 * D.clim0; end
offsets = (0:nCh-1) * spacing;

[te, Ye] = decimateMinMax(tt, seg, obj.VizPixelBudget);   % te 1xM, Ye MxnCh
Yplot = Ye * V.ampGain + offsets + V.yOffset;             % broadcast offsets

needRebuild = isempty(obj.VizLines) || numel(obj.VizLines) ~= nCh ...
    || any(~isvalid(obj.VizLines));
if needRebuild
    delete(findobj(ax, 'Type', 'line'));
    obj.VizLines = gobjects(nCh, 1);
    co = lines(7);
    for k = 1:nCh
        obj.VizLines(k) = plot(ax, te, Yplot(:, k), ...
            'LineWidth', 0.5, 'Color', co(mod(k-1, 7) + 1, :));
    end
else
    for k = 1:nCh
        set(obj.VizLines(k), 'XData', te, 'YData', Yplot(:, k));
    end
end

ax.YDir = "normal";
ax.YTick = offsets + V.yOffset;
ax.YTickLabel = compose("ch%d", D.chans(:));
ylabel(ax, "Channel (stacked, uV offset)");
ylim(ax, [V.yOffset - spacing, V.yOffset + offsets(end) + spacing]);
end


function renderHeatmap(obj, ax, seg, tt)
%renderHeatmap  One row per channel, colour = amplitude, columns binned to px.
D = obj.VizData; V = obj.VizView;
nCh = D.nCh;

C = binColumnsMean(seg, obj.VizPixelBudget).';   % [nCh x nCols]
clim = D.clim0 / V.ampGain;                      % larger gain -> tighter clim

if isempty(obj.VizImage) || ~isvalid(obj.VizImage)
    delete(findobj(ax, 'Type', 'image'));
    obj.VizImage = image(ax, [tt(1), tt(end)], [1, nCh], C, ...
        'CDataMapping', 'scaled');
else
    set(obj.VizImage, 'XData', [tt(1), tt(end)], 'YData', [1, nCh], 'CData', C);
end

colormap(ax, obj.VizColormapDropDown.Value);
ax.CLim = [-clim, clim];
if isempty(obj.VizColorbar) || ~isvalid(obj.VizColorbar)
    obj.VizColorbar = colorbar(ax);
    obj.VizColorbar.Label.String = "Amplitude (uV)";
end

ax.YDir = "reverse";                 % channel 1 at the top
ax.YTick = 1:nCh;
ax.YTickLabel = compose("ch%d", D.chans(:));
ylabel(ax, "Channel");
ylim(ax, [0.5, nCh + 0.5]);
end


function [te, Ye] = decimateMinMax(tt, seg, nPix)
%decimateMinMax  Per-pixel min/max envelope of [m x nCh] -> [2*nbin x nCh].
%   Keeps spike extrema while capping the plotted point count. When the window
%   already fits the budget the samples are returned unchanged.
m = size(tt, 1);
nCh = size(seg, 2);
if m <= 2 * nPix
    te = tt(:).';
    Ye = seg;
    return
end
binSize = ceil(m / nPix);
nbin = floor(m / binSize);
use  = nbin * binSize;

T = reshape(tt(1:use), binSize, nbin);
tmid = T(1, :);                              % 1 x nbin
Yr = reshape(seg(1:use, :), binSize, nbin, nCh);
ymin = reshape(min(Yr, [], 1), nbin, nCh);   % nbin x nCh
ymax = reshape(max(Yr, [], 1), nbin, nCh);

te = reshape([tmid; tmid], 1, []);           % 1 x 2*nbin
Ye = zeros(2 * nbin, nCh);
Ye(1:2:end, :) = ymin;
Ye(2:2:end, :) = ymax;
end


function C = binColumnsMean(seg, nPix)
%binColumnsMean  Average [m x nCh] down the time axis to <= nPix rows.
m = size(seg, 1);
nCh = size(seg, 2);
if m <= nPix
    C = seg;
    return
end
binSize = ceil(m / nPix);
nbin = floor(m / binSize);
use  = nbin * binSize;
Yr = reshape(seg(1:use, :), binSize, nbin, nCh);
C = reshape(mean(Yr, 1), nbin, nCh);         % nbin x nCh
end
