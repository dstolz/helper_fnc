function [M,results] = extract_ECM_profiles(tiffFile, opts)
% extract_ECM_profiles Extracts extracellular matrix (ECM) intensity profiles from histological images.
%   [M, results] = extract_ECM_profiles(tiffFile, opts)
%
%   INPUTS:
%     tiffFile              - Char vector: path to an OME-TIFF file. Required.
%     opts.profileWindow    - 1×2 double: [min max] analysis window in μm (relative to surfaceXY). Default: [-Inf Inf].
%     opts.numSegments      - Scalar integer: number of equal-area segments per profile. Default: 50.
%     opts.polyOrder        - Positive integer: polynomial order for surface fitting. Default: 2.
%     opts.profileLocations - N×1 double: distances (μm) along normal for profile extraction. Default: (0:-100:-1000)'.
%     opts.imgRotation      - Scalar: image rotation in degrees CCW. [] for interactive selection. Default: [].
%     opts.metrics          - 1×K cell array of strings: metrics to compute per segment (e.g. {'sum','mean'}). Default: {'sum'}.
%     opts.surfaceXY        - 1x2: approximate coordinate of surface 0. Specify as empty to manually pick. Default: [].
%     opts.bfmatlabPath     - Char vector: path to bfmatlab toolbox. Default: 'C:/src/bfmatlab'.
%     opts.minMaskArea      - Scalar: minimum mask area (pixels) to keep. Default: 10000.
%
%   OUTPUTS:
%     M       - (profiles × segments) matrix of raw ECM intensity values.
%     results - Struct with fields:
%               .options  - the opts struct used
%               .params   - file name, OME metadata, x_res, y_res
%               .images   - PV, ECM, combined, processed images and x/y coords
%               .surface  - .polyfit (coefficients & fitted values) and .coordinates (x_surface, y_surface, parabola offsets)
%               .profiles - cell arrays: dataECM, distsECM, edgeCoords, positions
%               .M        - struct with .x and .y axes for the output matrix
%
%   EXAMPLE:
%     opts = struct( ...
%       'profileWindow',[-500 300], ...
%       'numSegments',100, ...
%       'profileLocations',(0:-50:-500)', ...
%       'imgRotation',90);
%     [M, results] = extract_ECM_profiles('slice1.ome.tiff', opts);
%
%   DEPENDENCIES:
%     bfmatlab (Bio-Formats), parabola_offset, extract_equal_area_profiles,
%     colorcet, use_fig
%
%   See also polyfit, imrotate, adapthisteq, imgaussfilt


arguments
    tiffFile (1,:) char {mustBeNonempty}

    opts.profileWindow   (1,2) double = [-inf inf]
    opts.numSegments (1,1) double = 50
    opts.polyOrder (1,1) double {mustBePositive,mustBeInteger} = 2
    opts.profileLocations (:,1) double = 0:-100:-1000
    opts.imgRotation double = []                 % empty = interactive rotation
    opts.metrics (1,:) = {'sum'}
    opts.surfaceXY   double = []
    opts.bfmatlabPath            (1,:) char = 'C:/src/bfmatlab'
    opts.minMaskArea (1,1) = 10000;
end

addpath(opts.bfmatlabPath)

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
imgPV = dataCell{1}{1,1};
imgECM = dataCell{1}{2,1};





% Determine rotation
if isempty(opts.imgRotation)
    % Interactive rotate
    fig = use_fig('histology');
    imagesc(imgPV);
    axis image
    colorcet('L8');
    clim([min(imgPV(:)), 0.2*max(imgPV(:))]);
    xticks([]);
    yticks([]);
    sz = size(imgPV);
    yline(linspace(1,sz(1),5),':w');
    xline(linspace(1,sz(2),5),':w');

    % Main title shows current angle
    title('Rotation: 0°', 'FontWeight', 'bold');
    
    % Subtitle explains all controls
    subtitle(["←/→: ±step° (Shift=±5°, Ctrl=±0.1°)"; ...
              "↑/↓: ±90°  •  Enter: accept"]);

    h = zoom(fig);
    h.Enable = 'off';

    fig.UserData.angle = 0;
    fig.UserData.imgPV = imgPV;

    fig.WindowKeyPressFcn = @(src,evt) onKey(src,evt);
    uiwait(fig);

    opts.imgRotation = fig.UserData.angle;
    
    % close(fig);

    h.Enable = 'on';
end

% Apply rotation
if opts.imgRotation ~= 0
    imgPV  = imrotate(imgPV, opts.imgRotation);
    imgECM = imrotate(imgECM, opts.imgRotation);
end





% Combine channels (PV + ECM)
imgProj = imgPV;
% imgProj = imgPV + imgECM;
imgProjProcessed = adapthisteq(imgProj);
imgProjProcessed = imgaussfilt(imgProjProcessed,20);



pixIntensityThreshold = graythresh(imgProjProcessed);
ind = imgProjProcessed < pixIntensityThreshold;
ind(round(size(ind,1)/2):end,:) = false; % Only keep upper half
rp = regionprops(ind, {'Area','PixelList','PixelIdxList','Centroid'});

a = [rp.Area];
rp(a < opts.minMaskArea) = [];


if isempty(opts.surfaceXY)
    % Set X=0 using ginput
    use_fig('histology');
    imagesc(imgPV);
    title(tiffFn, Interpreter = 'none');
    subtitle('Select x = 0 at surface');
    axis image;
    colorcet('L8');
    clim([min(imgPV(:)), 0.2*max(imgPV(:))]);
    [x,y] = ginput(1);
    opts.surfaceXY = [x y];
end



% find region nearest to user input
dists = arrayfun(@(s) min(hypot(s.PixelList(:,1) - opts.surfaceXY(1), s.PixelList(:,2) - opts.surfaceXY(2))), rp);
[~,i] = min(dists);
rp = rp(i);

x = rp.PixelList(:,1);
y = rp.PixelList(:,2);
xi = unique(x);
yi = nan(size(xi));
for j = 1:length(yi)
    xind = x == xi(j);
    yi(j) = max(y(xind));
end



x_img = 0:size(imgProjProcessed,2)-1;
y_img = 0:size(imgProjProcessed,1)-1;

x_img = x_img - opts.surfaceXY(1);
% y_img = y_img - opts.surfaceXY(2);

x_img = x_res*x_img;
y_img = y_res*y_img;


% adjust x coordinates to zero at specified location
xi = xi - 1 - opts.surfaceXY(1);
% yi = yi - 1 - opts.surfaceXY(2);


% Surface coordinates
x_surface = (xi-1) * x_res;
y_surface = (yi-1) * y_res;







% Limit analysis window
% NOTE: This is not actually what we want. We really probably want the arc
% length. We'll just include more than we need and then trim to size after
% we've calculated arc lengths
pwin = opts.profileWindow;
% pwins = sign(pwin);
% pwin = pwins .* (abs(pwin) * 2);
ind_analysisX = x_surface >= pwin(1) & x_surface <= pwin(2);
x_zeroOffset = find(ind_analysisX,1);
x_surface(~ind_analysisX) = [];
y_surface(~ind_analysisX) = [];






% surface fitting
pf = polyfit(x_surface, y_surface, opts.polyOrder);
pv = polyval(pf, x_surface);
residual = pv - y_surface;
isOut = isoutlier(residual);
x_surface(isOut) = [];
y_surface(isOut) = [];

% refit surface excluding outliers
pf = polyfit(x_surface, y_surface, opts.polyOrder);

[x_off, y_off,L_arc] = parabola_offset(pf, x_surface([1 end]), opts.profileLocations);

% ds = hypot(diff(x_off,1,1), diff(y_off,1,1));
% s_full = [zeros(1,size(ds,2)); cumsum(ds,1)];
% [~, idx0] = min(abs(x_off));
% s = s_full - s_full(idx0);
% ind = s < opts.profileWindow(1) | s > opts.profileWindow(2);
% x_off(ind) = nan;
% y_off(ind) = nan;
% 
% % recompute arc length
% ds = hypot(diff(x_off,1,1), diff(y_off,1,1));
% s = [zeros(1,size(ds,2)); cumsum(ds,1,"omitmissing")];
% L_arc = max(s,[],1);




% compute segment spacing
segHeight = abs(diff(opts.profileLocations(1:2)))/2 * 1.7; % based on a heuristic
segSpacing = L_arc ./ opts.numSegments;



% overlay surface
use_fig('histology');
imagesc(x_img,y_img,imgPV);
title(tiffFn, Interpreter = 'none');
axis image;
colorcet('L8');
clim([min(imgPV(:)), 0.2*max(imgPV(:))]);
line(x_surface,y_surface,Color = 'r',Marker = '.',LineStyle = 'none');
line(x_off(:,1),y_off(:,1),Color = 'w');
drawnow



% ECM analysis along parabolas
nProfiles = size(x_off,2);
dataECM = cell(nProfiles,1);
distsECM = cell(nProfiles,1);
pos = cell(nProfiles,1);
edgeCoords = cell(nProfiles,1);
parfor_progress(nProfiles);
% for i = 1:nProfiles
parfor i = 1:nProfiles
    x = x_off(:,i)/x_res + x_zeroOffset + opts.surfaceXY(1);
    y = y_off(:,i)/y_res;

    x(isnan(x)) = [];
    y(isnan(y)) = [];

    [dataECM{i},distsECM{i},edgeCoords{i},~,pos{i}] = extract_equal_area_profiles( ...
        imgECM, x, y, ...
        height = segHeight, ...
        segmentSpacing = segSpacing(i), ...
        metrics = opts.metrics);
    edgeCoords{i}(:,[1 3]) = (edgeCoords{i}(:,[1 3]) - opts.surfaceXY(1) - x_zeroOffset) * x_res;
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
imagesc(x_img, y_img, imgECM);
axis image
clim([min(imgECM(:)), 0.2*max(imgECM(:))]);
line(x_surface, y_surface, 'Color','r','LineWidth',1);
line(x_off(:,1),y_off(:,1),'Color',[.8 .8 .8],'LineWidth',2);
title('ECM');
cm = colorcet('L5');
colormap(gca,cm);





nexttile
imagesc(x_img, y_img, imgECM);
axis image
clim([min(imgECM(:)), 0.2*max(imgECM(:))]);
line(x_surface, y_surface, 'Color','r','LineWidth',1);
line(x_off(:,1),y_off(:,1),'Color',[.8 .8 .8],'LineWidth',2);
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
xm = linspace(0,mean(L_arc),size(M,1))-opts.surfaceXY(1)*x_res; % ????
ym = opts.profileLocations / y_res;

% Results visualization
nexttile
imagesc(xm,ym,M);
xline(0,'-w')
set(gca,'ydir','normal');
title('ECM');
xlabel('rostrocaudal distance (\mum)');
ylabel('lateromedial distance (\mum)');
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
    'PV', imgPV, ...
    'ECM', imgECM, ...
    'combined', imgProj, ...
    'processed', imgProjProcessed,...
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

% Profiles data
results.profiles = struct(...
    'dataECM', {dataECM}, ...
    'distsECM', {distsECM}, ...
    'edgeCoords', {edgeCoords}, ...
    'positions', {pos});

% Visualization outputs
results.M = struct(...
    'x', xm, ...
    'y', ym);



end


function onKey(src,evt)
    % Retrieve current angle
    angle = src.UserData.angle;
    % imgH = src.UserData.imgH;

    
    % Determine adjustment step
    mods = evt.Modifier;
    if ismember('shift', mods)
        step = 5;      % coarse tuning
    elseif ismember('control', mods)
        step = 0.1;    % fine tuning
    else
        step = 1;      % default
    end

    % Handle keypresses
    switch evt.Key
        case 'leftarrow'
            angle = angle - step;
        case 'rightarrow'
            angle = angle + step;
        case 'uparrow'      % rotate CCW by 90°
            angle = angle + 90;
        case 'downarrow'    % rotate CW by 90°
            angle = angle - 90;
        case 'return'
            uiresume(src);
            return
        otherwise
            return
    end

    angle = mod(angle,360);

    % Apply rotation and refresh display
    imgPV = src.UserData.imgPV;
    rotated = imrotate(imgPV, angle,"bilinear");
    imagesc(rotated);
    axis image
    colorcet('L8');
    clim([min(imgPV(:)), 0.2*max(imgPV(:))]);
    xticks([]);
    yticks([]);
    sz = size(imgPV);
    yline(linspace(1,sz(1),5),':w');
    xline(linspace(1,sz(2),5),':w');

    
    % Main title shows current angle
    title(sprintf('Rotation: %.2f°', angle), 'FontWeight', 'bold');
    
    % Subtitle explains all controls
    subtitle(["←/→: ±step° (Shift=±5°, Ctrl=±0.1°)"; ...
              "↑/↓: ±90°  •  Enter: accept"]);
    
    % Colormap and contrast
    colorcet('L8');
    clim([min(imgPV(:)), 0.2*max(imgPV(:))]);
    
    % Store updated angle
    src.UserData.angle = angle;
end
