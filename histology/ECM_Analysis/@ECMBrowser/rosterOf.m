function [idx, Y] = rosterOf(obj, depth, Y, rows)
    %ROSTEROF The columns to draw, and what each of them holds.
    % Without a comparison the roster is the section table itself and
    % ROWS indexes it, which is what a column index has always been;
    % everything below reads the columns it draws out of the roster
    % rather than out of A.grid.files, so a comparison can put pairs
    % there instead and be tiled, colored, and exported as sections are.

    if ~obj.comparing()
        everyRow = (1:height(obj.Files))';

        obj.View = struct( ...
            "Text", obj.Text, ...
            "Sections", obj.Files, ...
            "Names", obj.sectionNames(everyRow), ...
            "PeakX", obj.Files.PeakX, ...
            "PeakY", obj.peakHeights(everyRow), ...
            "Comparison", "", ...
            "Sources", numel(rows), ...
            "Unpaired", 0, ...
            "Undefined", 0);

        idx = rows(:);
        Y = Y(:, idx);
        return
    end

    [idx, Y] = obj.compareWithin(depth, Y, rows);

end
