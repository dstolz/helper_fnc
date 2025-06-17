% ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-952/SUBJ-ID-952_2C_R/SUBJ-ID-952_2C_R_WFA-PV_Z3_250609_proj.tif';
% ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-952/SUBJ-ID-952_2B_R/SUBJ-ID-952_2B_R_WFA-PV_Z3_250609_proj.tif';
ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-957/SUBJ-ID-957_2B_R/SUBJ-ID-957_2B_R_WFA-PV_Z3_250609_proj.tif';
% ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-976/SUBJ-ID-976_2B_R/SUBJ-ID-976_2B_R_WFA-PV_Z3_250609_proj.tif';

% [fn,pth] = uigetfile('*proj.tif');
% ffn = fullfile(pth,fn);


window = [-1000 200];

imgRotation = 90;

addpath('C:/src/bfmatlab')

dataCell = bfopen(ffn);


% parse info
allKeys = dataCell{2}.keySet().toArray();
info = struct();

for i = 1:length(allKeys)
    key = char(allKeys(i));
    value = dataCell{2}.get(key);
    info.(matlab.lang.makeValidName(key)) = value;
end


if ~isempty(imgRotation)
    imgPV = imrotate(dataCell{1}{1,1},imgRotation);
    imgECM = imrotate(dataCell{1}{2,1},imgRotation);
end

% xCutoff = 3500;
% imgPV = imgPV(:,1:xCutoff);

% img = imgPV; % PV
img = imgPV + imgECM; % PV + ECM

img = adapthisteq(img);
img = imgaussfilt(img,20);


pixIntensityThreshold = graythresh(img);
ind = img < pixIntensityThreshold;

% cut image in half to prevent incorrect assignemnt of top
ind(round(size(ind,1)/2):end,:) = false;

rp = regionprops(ind,{'Area','PixelList','PixelIdxList','Centroid'});

% imagesc(ind)

cnt = vertcat(rp(:).Centroid);
[~,i] = min(cnt(:,2)); % top most

rp = rp(i);

idxOutside = rp.PixelIdxList;
ind = false(size(img));

ind(idxOutside) = true;

x = rp.PixelList(:,1);
y = rp.PixelList(:,2);
xi = unique(x);
yi = nan(size(xi));
for i = 1:length(yi)
    xind = x == xi(i);
    yi(i) = max(y(xind));
end

x_res = info.GlobalXResolution;
y_res = info.GlobalYResolution;

% surface coordinates
x_surface = xi*x_res;
y_surface = yi*y_res;

% image x,y in microns
x_img = x_res*(0:info.GlobalImageLength-1);
y_img = y_res*(0:info.GlobalImageWidth-1);


% Set X = 0
use_fig('histology')
ax = gca;

imagesc(x_img,y_img,imgPV);
axis image
clim([min(imgPV(:)) .2*max(imgPV(:))])

[xz,~]= ginput(1);

x_img = x_img - xz;
x_surface = x_surface - xz;


% limit analysis
ind_analysisX = x_surface >= window(1) & x_surface <= window(2);

x_zeroOffset = find(ind_analysisX,1);
x_surface(~ind_analysisX) = [];
y_surface(~ind_analysisX) = [];



% process ----------------------------------
% pixels --- TO DO: make in resolution
parabolaStart = 0;
parabolaN     = 50;
parabolaLast  = -600;

parabolaVec = linspace(parabolaStart,parabolaLast,parabolaN);

numSegments = 50;

% there's got to be a better way to determine the height for the trapezoids
dpv = diff(parabolaVec);
dpv = abs(dpv(1))/2;
dpv = dpv * 1.7;

% 

% fit polynomial to brain surface
polynomialOrder = 2;
pf = polyfit(x_surface,y_surface,polynomialOrder);
pv = polyval(pf,x_surface);

res = pv - y_surface;
isOutlier = isoutlier(res);
x_surface(isOutlier) = [];
y_surface(isOutlier) = [];

pf = polyfit(x_surface,y_surface,polynomialOrder);
pv = polyval(pf,x_surface);

% create parabolas offsetted from primary
[x_parabOffset,y_parabOffset,L_arc] = parabola_offset(pf, x_surface([1 end]), parabolaVec);


segSpacing = L_arc ./ numSegments;



dataECM = cell(size(x_parabOffset,2),1);
distsECM = dataECM;
pos = dataECM;
edgeCoords = dataECM;
parfor_progress(size(y_parabOffset,2));
% for i = 1:size(y_parabOffset,2)
parfor i = 1:size(y_parabOffset,2)
    x = x_parabOffset(:,i)./x_res + x_zeroOffset + xz;
    y = y_parabOffset(:,i)./y_res;

    [dataECM{i},distsECM{i},edgeCoords{i},~,pos{i}] = extract_equal_area_profiles(imgECM, x, y, ...
        height = dpv, ...
        segmentSpacing = segSpacing(i), ...
        metrics = {'sum'});

    edgeCoords{i}(:,[1 3]) = (edgeCoords{i}(:,[1 3]) - xz - x_zeroOffset) .* x_res;
    edgeCoords{i}(:,[2 4]) = edgeCoords{i}(:,[2 4]) .* y_res;
    parfor_progress;
end
parfor_progress(0);


% plot -----------------------
use_fig('histology')
tl = tiledlayout('flow');
tl.Padding = "tight";
tl.TileSpacing = "compact";

[~,fn] = fileparts(ffn);
title(tl,fn,Interpreter="none");





nexttile
imagesc(x_img,y_img,imgPV);
axis image
clim([min(imgPV(:)) .2*max(imgPV(:))])
xline(0,'-w');
line(x_surface,y_surface,Color = 'r',LineWidth = 1)
line(x_parabOffset(:,1),y_parabOffset(:,1),Color = [.8 .8 .8],LineWidth = 2)
line(x_parabOffset,y_parabOffset,Color = [.8 .8 .8],LineWidth = 1,LineStyle = ':')
title("PV");
cm = colorcet('L8');
colormap(gca,cm);








nexttile
b = imgPV - imgaussfilt(imgPV,20);
b(b < 0) = 0;
imagesc(x_img,y_img,b); axis image
clim([0 .2*max(b(:))])
xline(0,'-w');
line(x_surface,y_surface,Color = 'r',LineWidth = 1)
line(x_parabOffset(:,1),y_parabOffset(:,1),Color = [.8 .8 .8],LineWidth = 2)

cm = colorcet('L8');
colormap(gca,cm);
title('PV background corrected')






nexttile
imagesc(x_img,y_img,imgECM);
axis image
clim([min(imgECM(:)) .2*max(imgECM(:))])
xline(0,'-w');
line(x_surface,y_surface,Color = 'r',LineWidth = 1)
line(x_parabOffset(:,1),y_parabOffset(:,1),Color = [.8 .8 .8],LineWidth = 2)

title("ECM");
cm = colorcet('L5');
colormap(gca,cm);
hold on;
for i = 1:length(edgeCoords)
    edgePos = edgeCoords{i}(:,[1 2]);
    edgeNeg = edgeCoords{i}(:,[3 4]);

    % edgePos = edgePos .* [x_res y_res];
    % edgeNeg = edgeNeg .* [x_res y_res];

    numSeg = size(edgePos,1)-1;
    cm = lines(numSeg);
    for k = 1:numSeg
        vx = [edgePos(k,1), edgePos(k+1,1), edgeNeg(k+1,1), edgeNeg(k,1)];
        vy = [edgePos(k,2), edgePos(k+1,2), edgeNeg(k+1,2), edgeNeg(k,2)];
        patch(vx, vy, cm(k,:), 'FaceAlpha', 0.4, 'EdgeColor', 'none');
    end
    % line(pos{i}(:,1).*xres,pos{i}(:,2).*yres,Marker = '.',Color = 'w',LineStyle = 'none')
    % line(xpo(:,i),ypo(:,i),Color = [.8 .8 .8],LineWidth = 0.5,LineStyle = '--');
end
hold off



nexttile
imagesc(x_img,y_img,imgECM);
axis image
clim([min(imgECM(:)) .2*max(imgECM(:))])
xline(0,'-w');
line(x_surface,y_surface,Color = 'r',LineWidth = 1)
line(x_parabOffset(:,1),y_parabOffset(:,1),Color = [.8 .8 .8],LineWidth = 2)
title("ECM");
cm = colorcet('L5');
colormap(gca,cm);


linkaxes(findobj(gcf,'type','axes'))







% results======================

use_fig('results')
tl = tiledlayout('flow');
title(tl,fn,Interpreter="none");


M = horzcat(dataECM{:});

Mg = imgaussfilt(M,[2 0.5], ...
    FilterDomain="spatial", ...
    FilterSize=[101 51]);

% xm = linspace(0,mean(L_arc)./x_res,size(M,1));
xm = linspace(0,mean(L_arc),size(M,1));
ym = parabolaVec./y_res;

nexttile
imagesc(xm,ym,M');
set(gca,'ydir','normal')
% axis image

title('ECM')
xlabel('rostrocaudal distance (\mum)')
ylabel('lateromedial distance (\mum)')
colormap(gca,colorcet('L16'))
% clim([0 max(M(:))*0.8])
colorbar

nexttile
imagesc(xm,ym,Mg');
set(gca,'ydir','normal')
% axis image

title('ECM smoothed')
xlabel('rostrocaudal distance (\mum)')
ylabel('lateromedial distance (\mum)')
colormap(gca,colorcet('L16'))
% clim([0 max(M(:))*0.8])
colorbar




%% vvvvvvvvv
