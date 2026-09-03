function levels = levelsOf(obj, field, txt)
    %LEVELSOF List one field's values in the order they should be drawn.
    % Numbers sort as numbers, so plate 5 comes before plate 27 rather
    % than after it, and cannula distance -3 before -1. A field that is
    % numeric apart from a placeholder -- "n/a" for a value the sheet
    % never held -- still orders its numbers numerically; whatever does
    % not read as a number goes after them, in the text order UNIQUE
    % already put it in.
    %
    % TXT says whose values to list, and defaults to every section's:
    % what a field can be filtered to is a question about the sections,
    % and what a plot is split into is a question about the columns it
    % draws, which are the same thing until a comparison replaces them.

    if nargin < 3
        txt = obj.Text.(field);
    end

    levels = reshape(unique(txt(:)), [], 1);

    asNumber = str2double(levels);
    isNumeric = ~isnan(asNumber);

    if any(isNumeric)
        [~, order] = sort(asNumber(isNumeric));
        numeric = levels(isNumeric);
        levels = [numeric(order); levels(~isNumeric)];
    end

end
