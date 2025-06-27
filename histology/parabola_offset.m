function [x_off, y_off, L_arc] = parabola_offset(p, x, d, n)
%PARABOLA_OFFSET Generate uniformly spaced offset curves and compute arc lengths
%   [x_off, y_off, L_arc] = parabola_offset(p, x, d) computes offset curves
%   for the fit defined by cfit object p over the domain x, shifted by distances in d.
%   Each curve is sampled uniformly in its own arc length (fixed point count,
%   variable total length), and total arc lengths are returned.
%
%   [x_off, y_off, L_arc] = parabola_offset(p, x, d, n) also specifies the
%   number of sample points per curve (default = 200).
%
%   Inputs:
%     p     - cfit object representing a polynomial fit
%     x     - 1×2 vector [xmin, xmax] defining the base domain
%     d     - K×1 or 1×K vector of signed offsets (positive outward, negative inward)
%     n     - (optional) scalar number of points per curve (default: 200)
%
%   Outputs:
%     x_off - n×K matrix; each column contains x-coordinates of an offset curve
%     y_off - n×K matrix; each column contains y-coordinates of an offset curve
%     L_arc - 1×K row vector of total arc lengths for each offset curve

arguments
    p (1,1) cfit
    x (1,2) double
    d (:,1) double
    n (1,1) double = 200
end

% Domain endpoints
xmin = min(x);
xmax = max(x);

% High-resolution sampling for normal calculation
m = 1000;
t = linspace(xmin, xmax, m)';

% Evaluate fit and derivative
y = feval(p, t);
dy = differentiate(p, t);

% Compute unit normals
Lvec = sqrt(1 + dy.^2);
nx = -dy ./ Lvec;
ny =  1  ./ Lvec;

% Initialize outputs
K = numel(d);
x_off = zeros(n, K);
y_off = zeros(n, K);
L_arc = zeros(1, K);

% Generate each offset curve and compute its length
for i = 1:K
    di = d(i);
    xf = t - di .* nx;
    yf = y - di .* ny;

    % Cumulative arc-length of the offset curve
    ds = hypot(diff(xf), diff(yf));
    s = [0; cumsum(ds)];
    L_arc(i) = s(end);

    % Uniform sampling in arc length
    su = linspace(0, L_arc(i), n)';
    x_off(:,i) = interp1(s, xf, su);
    y_off(:,i) = interp1(s, yf, su);
end
end
