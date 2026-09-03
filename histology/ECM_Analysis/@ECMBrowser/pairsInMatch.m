function pairs = pairsInMatch(obj, rows, level, inMatch, levels, reference)
    %PAIRSINMATCH What is measured against what inside one match.
    % Three ways of settling it, because a field can have a value
    % everything else is measured against and can equally well have
    % none. Named a value, every other value present is measured
    % against it and a match without it yields nothing. Asked for each
    % against the rest, every value present is measured against all the
    % sections in the match that hold another value -- which is the
    % question to ask of subject, or of any field whose values are
    % peers. Asked for every pair, each two values present are measured
    % against each other, once, in the order the values are drawn in.
    %
    % A side is a set of sections rather than one section: they are
    % averaged before the comparison is taken, so a match holding two
    % sections on one side and one on the other is one comparison and
    % not two that share a profile.

    pairs = struct("A", {}, "B", {}, "AName", {}, "BName", {});

    present = levels(ismember(levels, level(inMatch)));

    switch reference

        case obj.RestOfMatch
            if numel(present) < 2
                return
            end

            for iLevel = 1:numel(present)
                pairs(end+1) = struct( ...
                    "A", rows(inMatch & level == present(iLevel)), ...
                    "B", rows(inMatch & level ~= present(iLevel)), ...
                    "AName", present(iLevel), "BName", obj.Rest); %#ok<AGROW>
            end

        case obj.EachPair
            for iLevel = 1:numel(present)
                for jLevel = iLevel + 1:numel(present)
                    pairs(end+1) = struct( ...
                        "A", rows(inMatch & level == present(iLevel)), ...
                        "B", rows(inMatch & level == present(jLevel)), ...
                        "AName", present(iLevel), ...
                        "BName", present(jLevel)); %#ok<AGROW>
                end
            end

        otherwise
            refRows = rows(inMatch & level == reference);

            if isempty(refRows)
                return
            end

            for iLevel = 1:numel(present)
                if present(iLevel) == reference
                    continue
                end

                pairs(end+1) = struct( ...
                    "A", rows(inMatch & level == present(iLevel)), ...
                    "B", refRows, ...
                    "AName", present(iLevel), "BName", reference); %#ok<AGROW>
            end

    end

end
