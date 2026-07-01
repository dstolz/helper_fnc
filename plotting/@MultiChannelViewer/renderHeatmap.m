function renderHeatmap(obj, seg, tt, chIdx)
%renderHeatmap  One row per visible channel, colour = amplitude, columns
%   binned to the pixel budget. Reuses the existing image object across
%   redraws (CData/XData/YData updated in place).

ax = obj.Axes;
nvc = numel(chIdx);

C = obj.binColumnsMean(seg, obj.PixelBudget).';   % [nvc x nCols]
clim = obj.Data.Clim0 / obj.AmpGain;
if ~isfinite(clim) || clim <= 0; clim = 1; end

if isempty(obj.Image) || ~isvalid(obj.Image)
    delete(findobj(ax, 'Type', 'image'));
    obj.Image = image(ax, [tt(1), tt(end)], [1, nvc], C, 'CDataMapping', 'scaled');
else
    set(obj.Image, 'XData', [tt(1), tt(end)], 'YData', [1, nvc], 'CData', C);
end

colormap(ax, obj.Colormap);
ax.CLim = [-clim, clim];
if isempty(obj.Colorbar) || ~isvalid(obj.Colorbar)
    obj.Colorbar = colorbar(ax);
end
unitSuffix = "";
if obj.Units ~= ""; unitSuffix = " (" + obj.Units + ")"; end
obj.Colorbar.Label.String = char("Amplitude" + unitSuffix);

ax.YDir = "reverse";                 % channel 1 at the top
ax.YTick = 1:nvc;
ax.YTickLabel = cellstr(obj.ChannelNames(chIdx));
ylabel(ax, "Channel");
ylim(ax, [0.5, nvc + 0.5]);
end
