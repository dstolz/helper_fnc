function I_out = straightenLine(I, x, y, options)
%STRAIGHTENLINE Straighten a polyline in a 3D (multiplane) image stack.
%
%   I_out = straightenLine(I, x, y, options)
%
%   This function extracts a rectangular "straightened" region from a 3D image stack,
%   following a user-specified polyline (given by x, y coordinates). The resulting
%   output is a 3D image (width x length x nPlanes), where each column corresponds
%   to a sample along the polyline and each row samples across the width
%   perpendicular to the polyline at that location.
%
%   Inputs:
%     I         - Input image stack of size [height x width x nPlanes] (double).
%     x, y      - 1 x N vectors specifying the (subpixel) polyline coordinates.
%                 N is the number of points along the path to straighten.
%     options   - Structure with fields:
%         width   : Width of output (pixels, default 20).
%         align   : Alignment of the output region relative to the polyline:
%                   'center' (default): polyline at center row
%                   'top'   : polyline at top edge of output
%                   'bottom': polyline at bottom edge of output
%
%   Output:
%     I_out     - Straightened image stack of size [width x N x nPlanes].
%
%   Theory:
%     For each segment along the polyline, a perpendicular sampling line is
%     constructed at each point, of length 'width'. Image intensity is sampled
%     using bilinear interpolation at each subpixel location along this line.
%     The orientation of the sampling line is determined by the direction of
%     the polyline at each point.
%
%   Example:
%     I_out = straightenLine(I, x, y, width = 30, align = 'top');
%

arguments
    I (:,:,:) double
    x (1,:) double
    y (1,:) double
    options.width (1,1) double {mustBeInteger, mustBePositive} = 20
    options.align (1,:) char {mustBeMember(options.align,{'center','top','bottom'})} = 'center'
end

width = options.width;
n = numel(x);
nPlanes = size(I,3);
I_out = zeros(width, n, nPlanes);

if n < 2
    error('Need at least 2 points for straightening');
end

x2 = x(1) - (x(2) - x(1));
y2 = y(1) - (y(2) - y(1));

if isempty(gcp('nocreate'))
    parpool('local');
end

switch lower(options.align)
    case 'center'
        offset = (width-1)/2;
    case 'top'
        offset = 0;
    case 'bottom'
        offset = width-1;
end



parfor_progress(n*nPlanes);
for k = 1:nPlanes
    Ik = double(I(:,:,k));
    parfor i = 1:n
        if i == 1
            x1 = x2;
            y1 = y2;
        else
            x1 = x(i-1);
            y1 = y(i-1);
        end
        x2i = x(i);
        y2i = y(i);

        dx = x2i - x1;
        dy = y1 - y2i;
        length_seg = sqrt(dx^2 + dy^2);
        if length_seg == 0
            dx = 0; dy = 1;
        else
            dx = dx / length_seg;
            dy = dy / length_seg;
        end
        cx = x2i - dy * offset;
        cy = y2i - dx * offset;

        px = cx + dy * (0:width-1);
        py = cy + dx * (0:width-1);

        I_out(:,i,k) = interp2(Ik, px, py, 'linear', 0).';
        parfor_progress;
    end
end
parfor_progress(0);
