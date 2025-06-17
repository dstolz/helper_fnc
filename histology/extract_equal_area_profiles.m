% extract_equal_area_profiles
% Divide the curve into trapezoidal segments equally spaced by center-to-center distance,
% compute metrics, and return edge coordinates using argument validation syntax.
% Usage:
%   [metricResults, dists, edgeCoords, idxAll, positions, normals] = ...
%       extract_equal_area_profiles(I, x, y, opts)
function [metricResults, dists, edgeCoords, idxAll, positions, normals] = extract_equal_area_profiles(I, x, y, opts)
arguments
    I                  {mustBeNumeric, mustBeNonempty}
    x   (:,1) double   {mustBeNonempty}
    y   (:,1) double   {mustBeNonempty}

    opts.height         (:,1) double {mustBePositive} = 10
    opts.segmentSpacing (1,1) double {mustBePositive} = 10
    opts.metrics        cell = {'sum'}
    opts.visualize      (1,1) logical = false
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

% Distances: midpoints between sample centers
dists = (s(1:end-1) + s(2:end)) / 2;

% Compute normals at sampled positions
dx = gradient(x); dy = gradient(y);
mag = hypot(dx, dy); mag(mag==0) = 1;
tx = dx ./ mag; ty = dy ./ mag;
tpx = interp1(sSamples, tx, s);
tpy = interp1(sSamples, ty, s);
normals = [-tpy, tpx];


% Preallocate outputs
numSeg = numel(s) - 1;
idxAll = cell(numSeg,1);
metricResults = zeros(numSeg, numel(opts.metrics));

if isscalar(opts.height)
    opts.height = repmat(opts.height,size(normals,1),1);
end

edgePos = positions + opts.height .* normals;
edgeNeg = positions - opts.height .* normals;
edgeCoords = [edgePos, edgeNeg];

% Loop over each segment trapezoid
for k = 1:numSeg
    % Compute band edge coordinates
    vx = [edgePos(k,1), edgePos(k+1,1), edgeNeg(k+1,1), edgeNeg(k,1)];
    vy = [edgePos(k,2), edgePos(k+1,2), edgeNeg(k+1,2), edgeNeg(k,2)];
    mask = poly2mask(vx, vy, size(I,1), size(I,2));
    idx = find(mask);
    idxAll{k} = idx;
    vals = I(idx);
    % Compute requested metrics
    for m = 1:numel(opts.metrics)
        metricResults(k,m) = feval(opts.metrics{m},vals);
    end
end

% Optional visualization
if opts.visualize
    cm = lines(numSeg);
    hold on
    for k = 1:numSeg
        vx = [edgePos(k,1), edgePos(k+1,1), edgeNeg(k+1,1), edgeNeg(k,1)];
        vy = [edgePos(k,2), edgePos(k+1,2), edgeNeg(k+1,2), edgeNeg(k,2)];
        patch(vx, vy, cm(k,:), 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    end
    hold off
end

