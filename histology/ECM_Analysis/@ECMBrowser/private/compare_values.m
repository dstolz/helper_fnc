function d = compare_values(op, a, b)
%COMPARE_VALUES Measure one profile against another, depth by depth.
% B is the reference. Every operation is undefined somewhere -- a ratio
% where the reference is zero, a logarithm where the ratio is not positive,
% a normalized difference where the two sides cancel -- and every one of
% those depths comes back NaN, which is already what a depth a section never
% reached comes back as and is already left out of the plot and the export.

switch op

    case "difference"
        d = a - b;

    case "ratio"
        d = a ./ b;

    case "log2 ratio"
        ratio = a ./ b;
        ratio(~(ratio > 0)) = NaN;
        d = log2(ratio);

    case "% change"
        d = 100 * (a - b) ./ b;

    otherwise
        total = a + b;
        d = (a - b) ./ total;

end

d(~isfinite(d)) = NaN;

end
