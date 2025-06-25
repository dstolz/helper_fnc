function rotate_interactive(src,evt)
% Interactive image rotation with customizable options via src.UserData.options

% Load or initialize options struct
if isfield(src.UserData,'options')
    opts = src.UserData.options;
else
    opts = struct();
end

% Retrieve current angle
angle = src.UserData.angle;

% Determine adjustment step sizes
if isfield(opts,'step') && isstruct(opts.step)
    defaultStep = getField(opts.step,'default',1);
    coarseStep   = getField(opts.step,'coarse',5);
    fineStep     = getField(opts.step,'fine',0.1);
else
    defaultStep = 1; coarseStep = 5; fineStep = 0.1;
end

% Modifier keys
mods = evt.Modifier;
if ismember('shift',mods)
    step = coarseStep;
elseif ismember('control',mods)
    step = fineStep;
else
    step = defaultStep;
end


bigStep = getField(opts,'bigStep',90);

% Key handling
opts.keys = getField(opts,'keys',[]);
switch evt.Key
    case getField(opts.keys,'left','leftarrow')
        angle = angle - step;
    case getField(opts.keys,'right','rightarrow')
        angle = angle + step;
    case getField(opts.keys,'up','uparrow')
        angle = angle + bigStep;
    case getField(opts.keys,'down','downarrow')
        angle = angle - bigStep;
    case getField(opts.keys,'accept','return')
        uiresume(src);
        return;
    otherwise
        return;
end

% Normalize angle
angle = mod(angle,360);

% Load image
image = src.UserData.image;

% Interpolation method
interpMethod = getField(opts,'interpMethod','bilinear');

% Rotate and display
rotated = imrotate(image,angle,interpMethod);
imagesc(rotated);
axis image;

% Axes
if ~getField(opts,'showAxes',false)
    xticks([]);
    yticks([]);
end

% Grid overlay
opts.grid = getField(opts,'grid',[]);
if getField(opts,'showGrid',true)
    nLines = getField(opts.grid,'lines',5);
    style  = getField(opts.grid,'style',':w');
    sz = size(image);
    yline(linspace(1,sz(1),nLines),style);
    xline(linspace(1,sz(2),nLines),style);
end

% Title and subtitle
titleText = sprintf(getField(opts,'titleFormat','Rotation: %.2f°'),angle);
title(titleText,'FontWeight',getField(opts,'titleFontWeight','bold'));
if isfield(opts,'subtitleLines')
    subtitle(opts.subtitleLines);
else
    subtitlef("←/→: ±%.1f° (Shift=±%.1f°, Ctrl=±%.3f°)\n↑/↓: ±%.1f°  •  Enter: accept", ...
        defaultStep,coarseStep,fineStep,bigStep);
end

% Colormap and contrast
colorcet(getField(opts,'colormap','L8'));
if isfield(opts,'clim')
    clim(opts.clim);
else
    clim([min(image(:)),0.2*max(image(:))]);
end

% Store updated angle
src.UserData.angle = angle;
end

% Helper: safe field access
function val = getField(s,fieldName,defaultVal)
if isfield(s,fieldName)
    val = s.(fieldName);
else
    val = defaultVal;
end
end
