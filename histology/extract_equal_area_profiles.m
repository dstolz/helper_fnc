% extract_equal_area_profiles
% Extract trapezoidal profiles along a 2D curve and compute image metrics.
%
% SYNTAX
%   [metricResults, midpoints, edgeCoords, idxAll, positions, normals] = ...
%       extract_equal_area_profiles(I, x, y, opts)
%
% DESCRIPTION
%   Divides a curve defined by coordinate vectors (x,y) into equally spaced
%   segments along its arclength. For each segment, constructs a trapezoid of
%   specified height oriented perpendicular to the curve, samples the image I
%   within that trapezoid, and computes one or more statistical metrics
%   (e.g., sum, mean) over the enclosed pixel values.
%
% INPUTS
%   I               - MxN numeric image matrix to sample.
%   x, y            - Column vectors of the same length defining the 2D curve
%                     coordinates in image space.
%
% OPTIONS (opts)
%   height          - Scalar or [numSamplesx1] vector specifying the half-height
%                     of each trapezoid (distance from curve to trapezoid edge)
%                     in pixels. Default: 10.
%   segmentSpacing  - Scalar center-to-center distance between adjacent
%                     trapezoids along the curve (in pixels). Default: 10.
%   metrics         - Cell array of function names (strings) for metrics to
%                     compute on sampled pixels, e.g. {'sum','mean'}. Default: {'sum'}.
%   visualize       - Logical flag (true/false) to overlay trapezoid patches on
%                     the image for inspection. Default: false.
%   approach        - String specifying trapezoid placement relative to the
%                     curve normals:
%                       'middle' (symmetric about the curve, default),
%                       'above'  (entirely on the normal side),
%                       'below'  (entirely on the opposite side).
%
% OUTPUTS
%   metricResults   - [numSegments x numMetrics] array of computed metric values.
%   midpoints           - [numSegments x 1] arclength positions of segment centers.
%   edgeCoords      - [numSamples x 4] concatenated edge coordinate pairs
%                     [xPos,yPos,xNeg,yNeg] for each sample point.
%   idxAll          - Cell array (numSegments x 1) of linear image indices
%                     within each trapezoid mask.
%   positions       - [numSamples x 2] (x,y) coordinates of sampled points on curve.
%   normals         - [numSamples x 2] unit normal vectors at each sample.
%
% EXAMPLE
%   % Compute mean intensity above the curve with 20px spacing:
%   [M,d] = extract_equal_area_profiles(I,x,y,'height',5,'segmentSpacing',20,'metrics',{{'mean'}},...
%                 'visualize',true,'approach','above');
function [metricResults, midpoints, edgeCoords, idxAll, positions, normals] = extract_equal_area_profiles(I, x, y, opts)
arguments
    I                  {mustBeNumeric, mustBeNonempty}
    x   (:,1) double   {mustBeNonempty}
    y   (:,1) double   {mustBeNonempty}

    opts.height         (:,1) double {mustBePositive} = 10
    opts.segmentSpacing (1,1) double {mustBePositive} = 10
    opts.metrics        cell = {'sum'}
    opts.visualize      (1,1) logical = false
    opts.approach       (1,1) string {mustBeMember(opts.approach, {'middle','above','below'})} = "middle"
end

% Ensure column vectors
x = x(:);
y = y(:);

% Compute cumulative arclength in physical units
dx_phys = diff(x);
dy_phys = diff(y);
segLens = hypot(dx_phys, dy_phys);
sSamples = [0; cumsum(segLens)];
totalLen = sSamples(end);

% Determine sample positions at specified spacing
s = (0:opts.segmentSpacing:totalLen)';
if s(end) < totalLen
    s(end+1) = totalLen;
end

% Sample positions on curve
positions(:,1) = interp1(sSamples, x, s);
positions(:,2) = interp1(sSamples, y, s);

% Midpoints between sample centers
midpoints = (s(1:end-1) + s(2:end)) / 2;

% Compute normals at sampled positions
dx = gradient(x);       dy = gradient(y);
mag = hypot(dx, dy);    mag(mag==0) = 1;
tx = dx ./ mag;         ty = dy ./ mag;
tpx = interp1(sSamples, tx, s);
tpy = interp1(sSamples, ty, s);
normals = [-tpy, tpx];

% Preallocate outputs
numSeg = numel(s) - 1;
idxAll = cell(numSeg,1);
metricResults = zeros(numSeg, numel(opts.metrics));

% Expand height per sample if scalar
if isscalar(opts.height)
    opts.height = repmat(opts.height, size(normals,1),1);
end

% Determine edge offsets based on approach
switch opts.approach
    case 'middle'
        edgePos = positions + opts.height .* normals;
        edgeNeg = positions - opts.height .* normals;
    case 'below'
        edgePos = positions + opts.height .* normals;
        edgeNeg = positions;  % bottom edge on curve
    case 'above'
        edgePos = positions;  % top edge on curve
        edgeNeg = positions - opts.height .* normals;
end

edgeCoords = [edgePos, edgeNeg];

% Loop over each segment trapezoid
for k = 1:numSeg
    % Compute trapezoid vertices
    vx = [edgePos(k,1),   edgePos(k+1,1),   edgeNeg(k+1,1),   edgeNeg(k,1)];
    vy = [edgePos(k,2),   edgePos(k+1,2),   edgeNeg(k+1,2),   edgeNeg(k,2)];
    mask = poly2mask(vx, vy, size(I,1), size(I,2));
    idx = find(mask);
    idxAll{k} = idx;
    vals = I(idx);
    % Compute requested metrics
    for m = 1:numel(opts.metrics)
        metricResults(k,m) = feval(opts.metrics{m}, vals);
    end
end

% Optional visualization
if opts.visualize
    imshow(I,[]);
    cm = lines(numSeg);
    hold on
    for k = 1:numSeg
        vx = [edgePos(k,1),   edgePos(k+1,1),   edgeNeg(k+1,1),   edgeNeg(k,1)];
        vy = [edgePos(k,2),   edgePos(k+1,2),   edgeNeg(k+1,2),   edgeNeg(k,2)];
        patch(vx, vy, cm(k,:), 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    end
    hold off
end
