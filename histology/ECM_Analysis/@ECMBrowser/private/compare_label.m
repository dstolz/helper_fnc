function label = compare_label(op, a, b)
%COMPARE_LABEL What one comparison is called wherever it is named.
% The arithmetic written out with the two values in it, so the legend of a
% figure says what was measured against what and in which direction without
% the caption having to.

switch op

    case "difference"
        label = a + " - " + b;

    case "ratio"
        label = a + " / " + b;

    case "log2 ratio"
        label = "log2(" + a + " / " + b + ")";

    case "% change"
        label = "% change " + a + " vs " + b;

    otherwise
        label = "(" + a + " - " + b + ") / (" + a + " + " + b + ")";

end

end
