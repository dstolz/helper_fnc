function [M,results] = straighten_cortex(tiffFile, opts)
% straighten_cortex -- intensity profiles from histological images.
%
%   [M, RESULTS] = straighten_cortex(TIFFFILE, OPTS) analyzes an OME-TIFF image
%   to extract equal-area ECM intensity profiles along the cortical surface. The
%   function fits a polynomial surface to the boundary between PV and ECM channels,
%   computes parabolic offsets, and samples intensity metrics across specified
%   distances from the surface.
%
%   Input Arguments
%   ---------------
%   TIFFFILE         Path to input OME-TIFF file (char vector). Required.
%                    First channel is used as anatomical reference.
%                    Second channel is used as data image.
%
%   OPTIONS (struct with fields):
%     surfaceWindow     1×2 double [min max] analysis window in micrometers
%                       relative to the detected surface (default: [-Inf, Inf]).
%     numSegments       Scalar integer specifying number of segments per profile
%                       (default: 50).
%     polyOrder         Positive integer polynomial order for surface fitting
%                       (default: 2).
%     profileLocations  N×1 double vector of distances (μm) along the surface
%                       normal for profile extraction (default: (0:-100:-1000)').
%     imgRotation       Scalar rotation angle in degrees CCW; empty for interactive
%                       selection (default: []).
%     surfaceXY         1×2 double [x y] approximate pixel coordinate of reference
%                       surface point; empty to manually pick via GUI (default: []).
%     metrics           1×K cell array of strings specifying metrics to compute per
%                       segment, e.g. {'sum','mean'} (default: {'sum'}).
%     minMaskArea       Scalar minimum area (pixels) to consider for surface mask
%                       (default: 10000).
%     segmentHeight     Scalar height (μm) of each segment; computed from
%                       profileLocations if empty (default: []).
%     segmentSpacing    Scalar or vector spacing (μm) between segments; computed
%                       from numSegments if empty (default: []).
%
%   Output Arguments
%   ----------------
%   M        Profiles-by-segments matrix of raw ECM intensity values.
%   RESULTS  Struct with fields:
%      options   The OPTIONS structure used for analysis.
%      params    Struct including TIFF file name, OME metadata, and spatial
%                resolutions (x_res, y_res).
%      images    Struct containing raw and processed images (PV, ECM, combined,
%                processed) and pixel-to-micron coordinate axes (x, y).
%      surface   Struct with:
%        polyfit.coefficients  Polynomial coefficients for surface fit.
%        polyfit.fittedValues  Fitted y-values along the surface.
%        coordinates.surfaceXY Reference surface point [x y].
%        coordinates.x_surface Surface x-coordinates (μm).
%        coordinates.y_surface Surface y-coordinates (μm).
%        coordinates.x_offset  Parabolic offset x-coordinates (μm).
%        coordinates.y_offset  Parabolic offset y-coordinates (μm).
%        coordinates.L_arc     Arc length along each profile (μm).
%      surfaces  Cell arrays per profile:
%        dataECM    Raw ECM intensity profiles.
%        distsECM   Distances along each profile (μm).
%        edgeCoords Coordinates of profile edges in μm.
%        positions  Pixel positions used for sampling.
%      M         Struct with fields x (cortical distances) and y (profile distances).
%
%   Example:
%     opts = struct( ...
%       'surfaceWindow', [-500, 300], ...
%       'numSegments', 100, ...
%       'profileLocations', (0:-50:-500)', ...
%       'imgRotation', 90);
%     [M, results] = straighten_cortex('slice1.ome.tiff', opts);
%
%   Dependencies:
%     bfmatlab (Bio-Formats), parabola_offset, extract_equal_area_profiles,
%     colorcet, use_fig, imrotate, adapthisteq, imgaussfilt, regionprops.
%
% see also, parabola_offset, extract_equal_area_profiles

arguments
    tiffFile (1,:) char {mustBeFile}

    opts.surfaceWindow   (1,2) double = [-inf inf]
    opts.numSegments (1,1) double = 50
    opts.polyOrder (1,1) double {mustBePositive,mustBeInteger} = 2
    opts.profileLocations (:,1) double = 0:-100:-1000
    opts.imgRotation double = []                 % empty = interactive rotation
    opts.metrics (1,:) = {'sum'}
    opts.surfaceXY   double = []
    opts.minMaskArea (1,1) double = 10000;
    opts.segmentHeight double = []
    opts.segmentSpacing double = []
end

[~,tiffFn] = fileparts(tiffFile);


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
imgRef  = dataCell{1}{1,1};
imgData = dataCell{1}{2,1};





% Determine rotation
if isempty(opts.imgRotation)

    use_fig('histology');
    rot = InteractiveRotator(imgRef);
    rot.TargetAxis = gca;

    disableDefaultInteractivity(gca);

    rot.start();

   
    opts.imgRotation = rot.Angle;
    opts.imgFlipped = rot.Flipped;

    delete(rot);

    enableDefaultInteractivity(gca);

end




% Apply transformations
if opts.imgRotation ~= 0
    imgRef  = imrotate(imgRef, opts.imgRotation);
    imgData = imrotate(imgData, opts.imgRotation);
end

if opts.imgFlipped(1)
    imgRef = flip(imgRef,1);
    imgData = flip(imgData,1);
end
if opts.imgFlipped(2)
    imgRef = flip(imgRef,2);
    imgData = flip(imgData,2);
end


% clean isolated pixels
bw = imgRef > 0;
bwo = bwareaopen(bw,5);
i = bw & ~bwo;
imgRef(i) = 0;
imgData(i) = 0;


% Trim sides to meet data
zind = all(imgRef == 0,1);
imgRef(:,zind) = [];
imgData(:,zind) = [];

% make sure the top has some padding
imgRef = [zeros(1,size(imgRef,2),'like',imgRef); imgRef];
imgData = [zeros(1,size(imgData,2),'like',imgData); imgData];


% imgRefProcessed = adapthisteq(imgRef);
imgRefProcessed = imgaussfilt(imgRef,20);

% Manually determine image threshold
% adj = ThresholdAdjuster(imgRef,gca,1/max(imgRef(:))); % NOTE: WILL TAKE A LONG TIME TO THRESHOLD IMAGES WITH COMPLEX CONTOURS
adj = ThresholdAdjuster(imgRefProcessed,gca,1/max(imgRefProcessed(:)));
pixIntensityThreshold = adj.ThresholdOriginal;




ind = imgRefProcessed < pixIntensityThreshold;
ind(size(ind,1)-round(size(ind,1)/3):end,:) = false; % Only keep upper half
rp = regionprops(ind, {'Area','PixelList','PixelIdxList','Centroid'});

a = [rp.Area];
rp(a < opts.minMaskArea) = [];


if isempty(opts.surfaceXY)
    % Set X=0 using ginput
    fprintf('Set reference point at surface\n')
    use_fig('histology');
    imagesc(imgRef);
    title(tiffFn, Interpreter = 'none');
    subtitle('Select x = 0 at surface');
    axis image;
    colorcet('L8');
    clim([min(imgRef(:)), 0.2*max(imgRef(:))]);
    [x,y] = ginput(1);
    opts.surfaceXY = [x y];




    % find region nearest to user input
    dists = arrayfun(@(s) min(hypot(s.PixelList(:,1) - opts.surfaceXY(1), s.PixelList(:,2) - opts.surfaceXY(2))), rp);
    [~,i] = min(dists);
    rp = rp(i);

    x = rp.PixelList(:,1);
    y = rp.PixelList(:,2);
    
    xi = unique(x,'stable');
    yi = zeros(size(xi));
    nind = ~ind;
    for i = 1:length(xi)
        yi(i) = find(nind(:,i),1);
    end


    % adjust x coordinates to zero at specified location
    xi = xi - 1 - opts.surfaceXY(1);
    % yi = yi - 1 - opts.surfaceXY(2);


    % Surface coordinates
    x_surface = (xi-1) * x_res;
    y_surface = (yi-1) * y_res;

end



x_img = 0:size(imgRefProcessed,2)-1;
y_img = 0:size(imgRefProcessed,1)-1;

x_img = x_img - opts.surfaceXY(1);
% y_img = y_img - opts.surfaceXY(2);

x_img = x_res*x_img;
y_img = y_res*y_img;



% Limit analysis window
% NOTE: This is not actually what we want. We really probably want the arc
% length. We'll just include more than we need and then trim to size after
% we've calculated arc lengths
pwin = opts.surfaceWindow;
ind_analysisX = x_surface >= pwin(1) & x_surface <= pwin(2);

x_surface(~ind_analysisX) = [];
y_surface(~ind_analysisX) = [];






% surface fitting
warning('off','curvefit:fit:iterationLimitReached');
ft = fittype("poly"+opts.polyOrder);
fopts = fitoptions('Method', 'LinearLeastSquares');
fopts.Normalize = 'on';
fopts.Robust = 'LAR';
fopts.Upper = Inf(1,opts.polyOrder+1);
fopts.Lower = [0, -Inf(1,opts.polyOrder)];
[pf, gof] = fit(x_surface(:),y_surface(:), ft, fopts );
pv = feval(pf,x_surface);
residual = pv - y_surface;
if gof.adjrsquare < 0.95
    fprintf(2,'Polynomial may be poorly fitted to surface. adjusted r^2 = %.4f\n',gof.adjrsquare)
end

isOut = isoutlier(residual);
x_surface(isOut) = [];
y_surface(isOut) = [];

% refit surface excluding outliers
% pf = polyfit(x_surface, y_surface, opts.polyOrder);.
[pf, gof] = fit(x_surface(:),y_surface(:), ft, fopts );
[x_off, y_off,L_arc] = parabola_offset(pf, x_surface([1 end]), opts.profileLocations);
warning('on','curvefit:fit:iterationLimitReached');

% compute segment spacing
avg_res = mean([x_res,y_res]);
if isempty(opts.segmentHeight)
    segmentHeight = abs(diff(opts.profileLocations(1:2)));
end

if isempty(opts.segmentSpacing)
    segSpacing = L_arc ./ opts.numSegments;
end


% overlay surface
use_fig('histology');
imagesc(x_img,y_img,imgRef);
title(tiffFn, Interpreter = 'none');
axis image;
colorcet('L8');
clim([min(imgRef(:)), 0.2*max(imgRef(:))]);
line(x_surface,y_surface,Color = 'r',Marker = '.',LineStyle = 'none');
line(x_off(:,1),y_off(:,1),Color = 'w');
line(0,feval(pf,0),LineWidth = 2, Marker = 'o',MarkerSize = 10,Color = 'm');
drawnow


% intensity analysis along parabolas
nProfiles = size(x_off,2);
dataECM = cell(nProfiles,1);
distsECM = cell(nProfiles,1);
pos = cell(nProfiles,1);
edgeCoords = cell(nProfiles,1);
sx = opts.surfaceXY(1);
met = opts.metrics;

parfor_progress(nProfiles);
% for i = 1:nProfiles
parfor i = 1:nProfiles
    % x = x_off(:,i)/x_res + x_zeroOffset + opts.surfaceXY(1);
    x = x_off(:,i)/x_res + sx;
    y = y_off(:,i)/y_res;

    x(isnan(x)) = [];
    y(isnan(y)) = [];

    [dataECM{i},distsECM{i},edgeCoords{i},~,pos{i}] = extract_equal_area_profiles( ...
        imgData, x, y, ...
        height = segmentHeight / avg_res, ...
        segmentSpacing = segSpacing(i) / avg_res, ...
        approach = 'below', ...
        metrics = met);

    edgeCoords{i}(:,[1 3]) = (edgeCoords{i}(:,[1 3]) - sx) * x_res;
    edgeCoords{i}(:,[2 4]) = edgeCoords{i}(:,[2 4]) * y_res;
    parfor_progress;
end
parfor_progress(0);









% Plotting results
use_fig('histology');
tl = tiledlayout('flow');
tl.Padding = "none";
tl.TileSpacing = "compact";

title(tl,tiffFn,Interpreter="none");


nexttile
imagesc(x_img, y_img, imgData);
axis image
clim([min(imgData(:)), 0.2*max(imgData(:))]);
line(x_surface, y_surface, 'Color','r','LineWidth',1);
line(x_off(:,1),y_off(:,1),'Color',[.8 .8 .8],'LineWidth',2);
line(0,feval(pf,0),LineWidth = 2, Marker = 'o',MarkerSize = 10,Color = 'm');
title('ECM');
cm = colorcet('L5');
colormap(gca,cm);





nexttile
imagesc(x_img, y_img, imgData);
axis image
clim([min(imgData(:)), 0.2*max(imgData(:))]);
line(x_surface, y_surface, 'Color','r','LineWidth',1);
line(x_off(:,1),y_off(:,1),'Color',[.8 .8 .8],'LineWidth',2);
line(0,feval(pf,0),LineWidth = 2, Marker = 'o',MarkerSize = 10,Color = 'm');
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















% Compile output matrix
M = horzcat(dataECM{:})';
xm = linspace(opts.surfaceWindow(1),opts.surfaceWindow(2),size(M,2));
ym = opts.profileLocations / y_res;

% Results visualization
nexttile
imagesc(xm,ym,M);
xline(0,'-w')
set(gca,'ydir','normal');
title('ECM');
xlabel('cortical distance from fiducial (\mum)');
ylabel('distance from surface (\mum)');
colorcet('L16');
colorbar;




















if nargout < 2, return; end

% Structure results with logical grouping into substructures
results = struct();

% Input parameters
results.options = opts;
results.params = struct(...
    'tiffFile', tiffFile, ...
    'info', info, ...
    'x_res', x_res, ...
    'y_res', y_res);

% Raw and processed images
results.images = struct(...
    'PV', imgRef, ...
    'ECM', imgData, ...
    'combined', imgRef, ...
    'processed', imgRefProcessed,...
    'x', x_img, ...
    'y', y_img);

% Surface fitting and coordinates
results.surface = struct();
results.surface.polyfit = struct(...
    'polyCoefficients', pf, ...
    'fittedValues', pv);

results.surface.coordinates = struct(...
    'surfaceXY', opts.surfaceXY, ...
    'x_surface', x_surface, ...
    'y_surface', y_surface, ...
    'x_parabOffset', x_off, ...
    'y_parabOffset', y_off, ...
    'L_arc', L_arc);

% surfaces data
results.surfaces = struct(...
    'dataECM', {dataECM}, ...
    'distsECM', {distsECM}, ...
    'edgeCoords', {edgeCoords}, ...
    'positions', {pos});

% Visualization outputs
results.M = struct(...
    'x', xm, ...
    'y', ym);



end
