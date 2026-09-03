function value = compare_neutral(op)
%COMPARE_NEUTRAL What one comparison reads when the two sides agree.
% Zero for every operation that subtracts, one for the one that divides.
% It is what the peak of a comparison is measured away from, so that a
% ratio's peak is its furthest departure from equality rather than from
% nothing at all.

if op == "ratio"
    value = 1;
else
    value = 0;
end

end
