function renderDigital(obj, tt, i0, i1)
%renderDigital  Stacked step-like traces for the optional digital/event tracks.
%   Always-all-shown (no channel-window scrolling); uses the same min/max
%   decimation as the main traces, which naturally preserves brief pulses.

ax = obj.DigitalAxes;
seg = obj.Digital.X(i0:i1, :);
nDig = obj.Digital.nCh;

[te, Ye] = obj.decimateMinMax(tt, seg, obj.PixelBudget);
offsets = (0:nDig-1) * 1.2;
Yplot = double(Ye) + offsets;

needRebuild = isempty(obj.DigitalLines) || numel(obj.DigitalLines) ~= nDig ...
    || any(~isvalid(obj.DigitalLines));
if needRebuild
    cla(ax);
    hold(ax, 'on');
    obj.DigitalLines = gobjects(nDig, 1);
    co = lines(7);
    for k = 1:nDig
        obj.DigitalLines(k) = plot(ax, te, Yplot(:, k), ...
            'LineWidth', 1.2, 'Color', co(mod(k-1, 7) + 1, :));
    end
else
    for k = 1:nDig
        set(obj.DigitalLines(k), 'XData', te, 'YData', Yplot(:, k));
    end
end

ax.YTick = offsets + 0.5;
ax.YTickLabel = cellstr(obj.Digital.Names);
ylim(ax, [-0.5, offsets(end) + 1.7]);
ax.XTickLabel = [];
end
