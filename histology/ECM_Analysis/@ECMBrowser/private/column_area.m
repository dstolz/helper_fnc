function a = column_area(x, Y)
%COLUMN_AREA Integrate each column over the depths it actually measured.
% TRAPZ has no omitnan, and a section that stops short of the reference window
% leaves NaN behind, so each column is integrated over its own finite samples
% rather than being given up on for the depths it never reached.

a = nan(1, size(Y, 2));

for iCol = 1:size(Y, 2)
    finiteSample = isfinite(Y(:, iCol));

    if nnz(finiteSample) > 1
        a(iCol) = trapz(x(finiteSample), Y(finiteSample, iCol));
    end
end

end
