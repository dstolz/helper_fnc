function renderAux(obj, tt, i0, i1)
%renderAux  Stacked traces for the optional auxiliary analog tracks.
%   Always-all-shown (no channel-window scrolling). Each channel is normalized
%   by its own robust amplitude scale (Aux.Clim0) before stacking, so tracks in
%   different physical units (e.g. accelerometer vs. temperature) don't
%   visually clash.

ax = obj.AuxAxes;
seg = obj.Aux.X(i0:i1, :);
nAux = obj.Aux.nCh;

[te, Ye] = obj.decimateMinMax(tt, seg, obj.PixelBudget);
scale = obj.Aux.Clim0;                  % [1 x nAux], robust per-channel scale
scale(~isfinite(scale) | scale <= 0) = 1;
Ynorm = double(Ye) ./ scale;
offsets = (0:nAux-1) * 2.2;
Yplot = Ynorm + offsets;

needRebuild = isempty(obj.AuxLines) || numel(obj.AuxLines) ~= nAux ...
    || any(~isvalid(obj.AuxLines));
if needRebuild
    cla(ax);
    hold(ax, 'on');
    obj.AuxLines = gobjects(nAux, 1);
    co = lines(7);
    for k = 1:nAux
        obj.AuxLines(k) = plot(ax, te, Yplot(:, k), ...
            'LineWidth', 0.75, 'Color', co(mod(k-1, 7) + 1, :));
    end
else
    for k = 1:nAux
        set(obj.AuxLines(k), 'XData', te, 'YData', Yplot(:, k));
    end
end

ax.YTick = offsets;
ax.YTickLabel = cellstr(obj.Aux.Names);
ylim(ax, [-1.3, offsets(end) + 1.3]);
xlabel(ax, "Time (s)");
end
