function renderTraces(obj, seg, tt, chIdx)
%renderTraces  Stacked min/max-decimated traces, one line per visible channel.
%   Reuses existing line objects across redraws (XData/YData updated in
%   place); only recreates the line array when the visible-channel count
%   changes (mode toggle, channel-window resize) or a mode switch cleared the
%   axes.

ax = obj.Axes;
nvc = numel(chIdx);

spacing = obj.TraceSpacing;
if spacing <= 0; spacing = 2 * obj.Data.Clim0; end
offsets = (0:nvc-1) * spacing;

[te, Ye] = obj.decimateMinMax(tt, seg, obj.PixelBudget);
Yplot = double(Ye) * obj.AmpGain + offsets + obj.YOffset;

needRebuild = isempty(obj.Lines) || numel(obj.Lines) ~= nvc || any(~isvalid(obj.Lines));
if needRebuild
    delete(findobj(ax, 'Type', 'line'));
    obj.Lines = gobjects(nvc, 1);
    co = lines(7);
    for k = 1:nvc
        obj.Lines(k) = plot(ax, te, Yplot(:, k), ...
            'LineWidth', 0.5, 'Color', co(mod(k-1, 7) + 1, :));
    end
else
    for k = 1:nvc
        set(obj.Lines(k), 'XData', te, 'YData', Yplot(:, k));
    end
end

unitSuffix = "";
if obj.Units ~= ""; unitSuffix = " " + obj.Units; end
ax.YDir = "normal";
ax.YTick = offsets + obj.YOffset;
ax.YTickLabel = cellstr(obj.ChannelNames(chIdx));
ylabel(ax, "Channel (stacked" + unitSuffix + " offset)");
ylim(ax, [obj.YOffset - spacing, obj.YOffset + offsets(end) + spacing]);
end
