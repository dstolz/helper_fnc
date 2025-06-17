function results = extract_ECM_profiles(tiffFile, Window, ImgRotation, NumSegments, polyOrder, polyDistanceVec)
% extract_ECM_profiles: Extracts ECM intensity profiles from histological images.
%   results = extract_ECM_profiles(tiffFile, 'Name', Value, ...)
%   Uses bfmatlab, parabola_offset, extract_equal_area_profiles, colorcet, use_fig.
%
%   Inputs (Name,Value):
%     'Window'        - Analysis window, [min max] (default: [-1000 200])
%     'ImgRotation'   - Image rotation in degrees (default: 0)
%     'NumSegments'   - Number of analysis segments (default: 50)
%     'polyOrder'     - Polynomial order for fitting surface (default: 2)
%     'polyDistanceVec'  - Vector of distances for polynomial fitting (default: [])
%
%   Outputs:
%     results: structure with extracted data and key outputs

arguments
    tiffFile (1,:) char {mustBeNonempty}
    Window   (1,2) double = [-1000 200]
    ImgRotation (1,1) double {mustBeMember(ImgRotation,[-90 0 90])}= 0
    NumSegments (1,1) double = 50
    polyOrder (1,1) double {mustBePositive,mustBeInteger} = 2
    polyDistanceVec (:,1) double
end

addpath('C:/src/bfmatlab')

% Load image and OME metadata
dataCell = bfopen(tiffFile);

    
% Parse OME metadata to struct
allKeys = dataCell{2}.keySet().toArray();
info = struct();
for i = 1:length(allKeys)
    key = char(allKeys(i));
    value = dataCell{2}.get(key);
    info.(matlab.lang.makeValidName(key)) = value;
end

% Get spatial metadata (microns)
x_res = info.GlobalXResolution;
y_res = info.GlobalYResolution;


% Extract channels and rotate if needed
imgPV = dataCell{1}{1,1};
imgECM = dataCell{1}{2,1};
if ImgRotation ~= 0
    imgPV  = imrotate(imgPV, ImgRotation);
    imgECM = imrotate(imgECM, ImgRotation);
    tx = x_res;
    x_res = y_res;
    y_res = tx;
end

% Combine channels (PV + ECM)
img = imgPV + imgECM;
img = adapthisteq(img);
img = imgaussfilt(img,20);

pixIntensityThreshold = graythresh(img);
ind = img < pixIntensityThreshold;
ind(round(size(ind,1)/2):end,:) = false; % Only keep upper half
rp = regionprops(ind, {'Area','PixelList','PixelIdxList','Centroid'});

cnt = vertcat(rp(:).Centroid);
[~,i] = min(cnt(:,2)); % top-most
rp = rp(i);

idxOutside = rp.PixelIdxList;
ind = false(size(img));
ind(idxOutside) = true;

x = rp.PixelList(:,1);
y = rp.PixelList(:,2);
xi = unique(x);
yi = nan(size(xi));
for j = 1:length(yi)
    xind = x == xi(j);
    yi(j) = max(y(xind));
end

x_img = x_res*(0:size(img,2)-1);
y_img = y_res*(0:size(img,1)-1);

% Surface coordinates
x_surface = xi * x_res;
y_surface = yi * y_res;

% Set X=0 using ginput
use_fig('histology');
ax = gca;
imagesc(x_img, y_img, imgPV);
axis image;
clim([min(imgPV(:)), 0.2*max(imgPV(:))]);
[xz,~] = ginput(1);
x_img = x_img - xz;
x_surface = x_surface - xz;

% Limit analysis window
ind_analysisX = x_surface >= Window(1) & x_surface <= Window(2);
x_zeroOffset = find(ind_analysisX,1);
x_surface(~ind_analysisX) = [];
y_surface(~ind_analysisX) = [];

% Parabola calculation
parabolaStart = 0;
parabolaVec = linspace(parabolaStart, ParabolaLast, ParabolaN);
dpv = abs(diff(parabolaVec(1:2)))/2 * 1.7;
polynomialOrder = 2;
pf = polyfit(x_surface, y_surface, polynomialOrder);
pv = polyval(pf, x_surface);
residual = pv - y_surface;
isOutlier = isoutlier(residual);
x_surface(isOutlier) = [];
y_surface(isOutlier) = [];
pf = polyfit(x_surface, y_surface, polynomialOrder);
pv = polyval(pf, x_surface);
[x_parabOffset, y_parabOffset, L_arc] = parabola_offset(pf, x_surface([1 end]), parabolaVec);
segSpacing = L_arc ./ NumSegments;

% ECM analysis along parabolas
nProfiles = size(x_parabOffset,2);
dataECM = cell(nProfiles,1);
distsECM = cell(nProfiles,1);
pos = cell(nProfiles,1);
edgeCoords = cell(nProfiles,1);
parfor_progress(nProfiles);
parfor i = 1:nProfiles
    x = x_parabOffset(:,i)/x_res + x_zeroOffset + xz;
    y = y_parabOffset(:,i)/y_res;
    [dataECM{i},distsECM{i},edgeCoords{i},~,pos{i}] = extract_equal_area_profiles( ...
        imgECM, x, y, height = dpv, segmentSpacing = segSpacing(i), metrics = {'sum'});
    edgeCoords{i}(:,[1 3]) = (edgeCoords{i}(:,[1 3]) - xz - x_zeroOffset) * x_res;
    edgeCoords{i}(:,[2 4]) = edgeCoords{i}(:,[2 4]) * y_res;
    parfor_progress;
end
parfor_progress(0);

% Plotting results
use_fig('histology');
tl = tiledlayout('flow');
[~,fn] = fileparts(ffn);
title(tl,fn,Interpreter="none");

nexttile
imagesc(x_img, y_img, imgPV);
axis image
clim([min(imgPV(:)), 0.2*max(imgPV(:))]);
xline(0,'-w');
line(x_surface, y_surface, 'Color','r','LineWidth',1);
line(x_parabOffset(:,1),y_parabOffset(:,1),'Color',[.8 .8 .8],'LineWidth',2);
line(x_parabOffset, y_parabOffset,'Color',[.8 .8 .8],'LineWidth',1,'LineStyle',':');
title('PV');
cm = colorcet('L8');
colormap(gca,cm);

nexttile
b = imgPV - imgaussfilt(imgPV,20);
b(b < 0) = 0;
imagesc(x_img, y_img, b);
axis image
clim([0, 0.2*max(b(:))]);
xline(0,'-w');
line(x_surface, y_surface, 'Color','r','LineWidth',1);
line(x_parabOffset(:,1),y_parabOffset(:,1),'Color',[.8 .8 .8],'LineWidth',2);
cm = colorcet('L8');
colormap(gca,cm);
title('PV background corrected');

nexttile
imagesc(x_img, y_img, imgECM);
axis image
clim([min(imgECM(:)), 0.2*max(imgECM(:))]);
xline(0,'-w');
line(x_surface, y_surface, 'Color','r','LineWidth',1);
line(x_parabOffset(:,1),y_parabOffset(:,1),'Color',[.8 .8 .8],'LineWidth',2);
title('ECM');
cm = colorcet('L5');
colormap(gca,cm);
hold on;
for i = 1:length(edgeCoords)
    edgePos = edgeCoords{i}(:,[1 2]);
    edgeNeg = edgeCoords{i}(:,[3 4]);
    numSeg = size(edgePos,1)-1;
    cmlines = lines(numSeg);
    for k = 1:numSeg
        vx = [edgePos(k,1), edgePos(k+1,1), edgeNeg(k+1,1), edgeNeg(k,1)];
        vy = [edgePos(k,2), edgePos(k+1,2), edgeNeg(k+1,2), edgeNeg(k,2)];
        patch(vx, vy, cmlines(k,:), 'FaceAlpha', 0.4, 'EdgeColor', 'none');
    end
end
hold off

nexttile
imagesc(x_img, y_img, imgECM);
axis image
clim([min(imgECM(:)), 0.2*max(imgECM(:))]);
xline(0,'-w');
line(x_surface, y_surface, 'Color','r','LineWidth',1);
line(x_parabOffset(:,1),y_parabOffset(:,1),'Color',[.8 .8 .8],'LineWidth',2);
title('ECM');
cm = colorcet('L5');
colormap(gca,cm);
linkaxes(findobj(gcf,'type','axes'));

% Compile output matrix
M = horzcat(dataECM{:});
Mg = imgaussfilt(M,[2 0.5],'FilterDomain','spatial','FilterSize',[101 51]);
xm = linspace(0,mean(L_arc),size(M,1));
ym = parabolaVec / y_res;

% Results visualization
use_fig('results');
tl = tiledlayout('flow');
title(tl,fn,Interpreter="none");
nexttile
imagesc(xm,ym,M');
set(gca,'ydir','normal');
title('ECM');
xlabel('rostrocaudal distance (\mum)');
ylabel('lateromedial distance (\mum)');
colormap(gca,colorcet('L16'));
colorbar;
nexttile
imagesc(xm,ym,Mg');
set(gca,'ydir','normal');
title('ECM smoothed');
xlabel('rostrocaudal distance (\mum)');
ylabel('lateromedial distance (\mum)');
colormap(gca,colorcet('L16'));
colorbar;

% Structure results
results = struct;
results.dataECM = dataECM;
results.distsECM = distsECM;
results.edgeCoords = edgeCoords;
results.xm = xm;
results.ym = ym;
results.M = M;
results.Mg = Mg;
results.imgPV = imgPV;
results.imgECM = imgECM;
results.info = info;
results.x_surface = x_surface;
results.y_surface = y_surface;
results.x_parabOffset = x_parabOffset;
results.y_parabOffset = y_parabOffset;
results.L_arc = L_arc;
results.fn = fn;
results.x_img = x_img;
results.y_img = y_img;

