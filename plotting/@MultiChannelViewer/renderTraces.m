function renderTraces(obj, seg, tt, chIdx)
%renderTraces  Stacked min/max-decimated traces, one line per visible channel.
%   Reuses existing line objects across redraws (XData/YData updated in
%   place); only recreates the line array when the visible-channel count
%   changes (mode toggle, channel-window resize) or a mode switch cleared the
%   axes. Line colors are recomputed every call (see ColorByGroup).

ax = obj.Axes;
nvc = numel(chIdx);

spacing = obj.TraceSpacing;
if spacing <= 0; spacing = 2 * obj.Data.Clim0; end
offsets = (0:nvc-1) * spacing;

[te, Ye] = obj.decimateMinMax(tt, seg, obj.PixelBudget);
Yplot = double(Ye) * obj.AmpGain + offsets + obj.YOffset;
colors = traceColors(obj, chIdx);

needRebuild = isempty(obj.Lines) || numel(obj.Lines) ~= nvc || any(~isvalid(obj.Lines));
if needRebuild
    delete(findobj(ax, 'Type', 'line'));
    obj.Lines = gobjects(nvc, 1);
    for k = 1:nvc
        obj.Lines(k) = plot(ax, te, Yplot(:, k), ...
            'LineWidth', 0.5, 'Color', colors(k, :));
    end
else
    for k = 1:nvc
        set(obj.Lines(k), 'XData', te, 'YData', Yplot(:, k), 'Color', colors(k, :));
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


function colors = traceColors(obj, dataIdx)
%traceColors  Per-line RGB color for each displayed channel (DATAIDX are
%   data-column/raw-channel indices). Colors by ChannelGroups (e.g. probe
%   shank) when ColorByGroup is enabled and a group id is set for every
%   channel; otherwise cycles through the default 7-color palette by
%   display position, as before ColorByGroup existed.
nvc = numel(dataIdx);
if obj.ColorByGroup && numel(obj.ChannelGroups) == obj.NumChannels
    g = obj.ChannelGroups(dataIdx);
    [~, ~, gi] = unique(g);
    cmap = lines(numel(unique(g)));
    colors = cmap(gi, :);
else
    co = lines(7);
    colors = co(mod((0:nvc-1), 7) + 1, :);
end
end
