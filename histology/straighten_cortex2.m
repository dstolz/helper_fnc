% Refactored straighten_cortex2 to process all channels
function M = straighten_cortex2(tiffFile, opts)
% straighten_cortex2: Extracts intensity profiles from all channels of histological images.
%
%   M = straighten_cortex2(tiffFile, opts) extracts ECM intensity profiles
%   from an OME-TIFF image. The function detects the cortical surface in a
%   reference channel, fits a polynomial to the boundary, and samples intensity
%   values along the normal at multiple distances from the surface, for all channels.
%
%   Inputs:
%     tiffFile        Path to input OME-TIFF file (char)
%     opts            Struct with fields:
%       refChannel        Reference channel index (default: 1)
%       surfaceWindow     [min max] analysis window (μm, default: [-Inf Inf])
%       numSegments       Number of profile segments (default: 50)
%       polyOrder         Polynomial order for surface fit (default: 2)
%       imgRotation       Rotation angle in degrees CCW (default: [])
%       surfaceXY         [x y] pixel for reference point (default: [])
%       minMaskArea       Minimum area (pixels) for surface mask (default: 10000)
%       profileWidth      Width for profile extraction (default: 600)
%
%   Output:
%     M    Struct with fields:
%             .data      (channel, profile, segment) array of ECM intensity values
%             .x         x coordinates (cortical distance, microns)
%             .y         y coordinates (profile depth, microns)

arguments
    tiffFile (1,:) char {mustBeFile}
    opts.refChannel   (1,1) double {mustBePositive,mustBeInteger} = 1
    opts.surfaceWindow   (1,2) double = [-inf inf]
    opts.numSegments     (1,1) double = 50
    opts.polyOrder       (1,1) double {mustBePositive,mustBeInteger} = 2
    opts.imgRotation     double = []
    opts.surfaceXY       double = []
    opts.minMaskArea     (1,1) double = 10000
    opts.profileWidth    (1,1) double = 600
end

[~,tiffFn] = fileparts(tiffFile);
dataCell = bfopen(tiffFile);

% Parse OME metadata to struct
allKeys = dataCell{2}.keySet().toArray();
info = struct();
for i = 1:length(allKeys)
    key = char(allKeys(i));
    value = dataCell{2}.get(key);
    info.(matlab.lang.makeValidName(key)) = value;
end

nChannels = size(dataCell{1},1);
imgRef = dataCell{1}{opts.refChannel,1};

x_res = info.GlobalXResolution;
y_res = info.GlobalYResolution;

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




% Apply rotation and flip to all channels
imgAll = cell(nChannels,1);
for ch = 1:nChannels
    img = dataCell{1}{ch,1};
    if opts.imgRotation ~= 0
        img = imrotate(img, opts.imgRotation);
    end
    if isfield(opts,'imgFlipped') && ~isempty(opts.imgFlipped)
        if opts.imgFlipped(1)
            img = flip(img,1);
        end
        if opts.imgFlipped(2)
            img = flip(img,2);
        end
    end
    imgAll{ch} = img;
end






% Use reference channel for surface detection
imgRef = imgAll{opts.refChannel};

bw = imgRef > 0;
bwo = bwareaopen(bw,5);
i = bw & ~bwo;
imgRef(i) = 0;
for ch = 1:nChannels
    imgAll{ch}(i) = 0;
end

zind = all(imgRef == 0,1);
imgRef(:,zind) = [];
for ch = 1:nChannels
    imgAll{ch}(:,zind) = [];
end

imgRef = [zeros(1,size(imgRef,2),'like',imgRef); imgRef];
for ch = 1:nChannels
    imgAll{ch} = [zeros(1,size(imgAll{ch},2),'like',imgAll{ch}); imgAll{ch}];
end

imgRefProcessed = imgaussfilt(imgRef,20);
adj = ThresholdAdjuster(imgRefProcessed,gca,1/max(imgRefProcessed(:)));
pixIntensityThreshold = adj.ThresholdOriginal;

ind = imgRefProcessed < pixIntensityThreshold;
ind(size(ind,1)-round(size(ind,1)/3):end,:) = false;
rp = regionprops(ind, {'Area','PixelList','PixelIdxList','Centroid'});
a = [rp.Area];
rp(a < opts.minMaskArea) = [];

if isempty(opts.surfaceXY)
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
end

dists = arrayfun(@(s) min(hypot(s.PixelList(:,1) - opts.surfaceXY(1), s.PixelList(:,2) - opts.surfaceXY(2))), rp);
[~,i] = min(dists);
rp = rp(i);
x = rp.PixelList(:,1);
xi = unique(x,'stable');
yi = zeros(size(xi));
nind = ~ind;
for i = 1:length(xi)
    yi(i) = find(nind(:,i),1);
end
x_surface = (xi-1);
y_surface = (yi-1);


pwin = opts.surfaceWindow + opts.surfaceXY(1);
ind_analysisX = x_surface >= pwin(1) & x_surface <= pwin(2);
x_surface(~ind_analysisX) = [];
y_surface(~ind_analysisX) = [];

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

pf = fit(x_surface(:),y_surface(:), ft, fopts );
x_out = linspace(min(x_surface),max(x_surface),1000);
y_out = feval(pf,x_out);


line(x_out,y_out,Color = "w")
drawnow

M.data = straightenLine(cat(3,imgAll{:}), x_out, y_out, width = opts.profileWidth, align = 'top');

M.y = -(0:size(M.data,1)-1) .* y_res;
M.x = (x_out - opts.surfaceXY(1)) .* x_res;
