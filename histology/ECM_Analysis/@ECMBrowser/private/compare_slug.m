function slug = compare_slug(op, a, b)
%COMPARE_SLUG What one comparison is called where the arithmetic cannot go.
% MAKEVALIDNAME takes "Right - Left" and "Right / Left" down to the same
% name, so a column of an export says which operation it is in a word that
% survives being made into a variable name.

switch op

    case "difference"
        slug = a + " minus " + b;

    case "ratio"
        slug = a + " over " + b;

    case "log2 ratio"
        slug = "log2 " + a + " over " + b;

    case "% change"
        slug = "pct change " + a + " vs " + b;

    otherwise
        slug = "norm diff " + a + " vs " + b;

end

end
