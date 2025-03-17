function h = plot_raster(r)
% h = plot_raster(r)
% 
% Plots raster of cell array r in currect axes
xline(0,LineWidth = 2,Color = [0.4 0.4 0.4]);
for i = 1:numel(r)
    h(i) = line(r{i},i*ones(size(r{i})), ...
        Marker = 's', ...
        MarkerFaceColor = 'k', ...
        MarkerSize = 2, ...
        MarkerEdgeColor = 'none', ...
        LineStyle = 'none');
end
xlabel('time (s)')
axis tight
ylim([0.5 numel(r)+0.5])
box on
set(gca,'ydir','reverse','ytick',[])

if nargout == 0, clear h; end