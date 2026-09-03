function [idx, D] = compareWithin(obj, depth, Y, rows)
    %COMPAREWITHIN Measure one value of a field against another, in matches.
    % Sections are put into matches on the Pair within fields, and
    % what is measured against what inside a match is PAIRSINMATCH's
    % question. What is settled here is the same for all three of its
    % answers: each side is averaged before the two are compared,
    % which is what makes one section against one and three against
    % two the same operation, and what keeps a match with a spare
    % section on one side from producing several comparisons that
    % share a profile and would then be averaged as though they were
    % independent.
    %
    % A comparison that came out undefined at every depth -- two sides
    % that never overlapped, a reference of zero under a ratio -- is
    % dropped rather than drawn flat, and the sections that landed in
    % no comparison at all are counted, so the status line can say
    % what became of everything that is not on screen.

    op = string(obj.CompareDropDown.Value);
    field = string(obj.CompareFieldDropDown.Value);
    within = obj.pairFields();

    levels = obj.levelsOf(field);
    reference = string(obj.CompareRefDropDown.Value);

    if ~ismember(reference, [obj.RestOfMatch; obj.EachPair; levels])
        reference = levels(1);
    end

    level = obj.Text.(field)(rows);
    match = obj.matchKeys(rows, within);
    keys = unique(match);

    fields = string(fieldnames(obj.Text));

    columns = cell(1, 0);       % one profile per comparison
    sources = cell(1, 0);       % the rows of A.grid.files behind it
    labels = strings(1, 0);     % what the compared field now holds
    slugs = strings(1, 0);      % the same, as a column of an export
    sides = zeros(0, 2);        % how many sections went into each side
    nUndefined = 0;

    for iKey = 1:numel(keys)
        pairs = obj.pairsInMatch(rows, level, match == keys(iKey), ...
            levels, reference);

        for iPair = 1:numel(pairs)
            a = mean(Y(:, pairs(iPair).A), 2, "omitnan");
            b = mean(Y(:, pairs(iPair).B), 2, "omitnan");

            d = compare_values(op, a, b);

            if ~any(isfinite(d))
                nUndefined = nUndefined + 1;
                continue
            end

            columns{end+1} = d; %#ok<AGROW>
            sources{end+1} = unique([pairs(iPair).A(:); pairs(iPair).B(:)]); %#ok<AGROW>
            labels(end+1) = compare_label(op, pairs(iPair).AName, pairs(iPair).BName); %#ok<AGROW>
            slugs(end+1) = compare_slug(op, pairs(iPair).AName, pairs(iPair).BName); %#ok<AGROW>
            sides(end+1, :) = [numel(pairs(iPair).A), numel(pairs(iPair).B)]; %#ok<AGROW>
        end
    end

    nPairs = numel(columns);
    idx = (1:nPairs)';

    if nPairs == 0
        D = zeros(numel(depth), 0);
    else
        D = [columns{:}];
    end

    % Every field a section can be split on, answered for the group of
    % sections behind each comparison: the one value they agree on, or
    % "(mixed)" where they do not. The compared field is the exception
    % -- the sections behind a comparison disagree on it by
    % construction, and what the column holds is the comparison itself.
    txt = struct();

    for iField = 1:numel(fields)
        values = repmat(obj.Mixed, nPairs, 1);

        for iPair = 1:nPairs
            seen = unique(obj.Text.(fields(iField))(sources{iPair}));

            if isscalar(seen)
                values(iPair) = seen;
            end
        end

        txt.(fields(iField)) = values;
    end

    txt.(field) = reshape(labels, [], 1);

    [peakX, peakY] = obj.comparisonPeaks(depth, D, op);

    % A section can be behind several comparisons at once -- it is,
    % under either of the references that are not a value of the
    % field -- so what is counted is the sections that reached one,
    % not the entries of the list they were collected in.
    reached = unique(vertcat(zeros(0, 1), sources{:}));

    obj.View = struct( ...
        "Text", txt, ...
        "Sections", obj.comparisonTable(txt, labels, sides, peakX, peakY, op), ...
        "Names", obj.comparisonNames(txt, within, slugs), ...
        "PeakX", peakX, ...
        "PeakY", peakY, ...
        "Comparison", op + " by " + field, ...
        "Sources", numel(rows), ...
        "Unpaired", numel(rows) - numel(reached), ...
        "Undefined", nUndefined);

end
