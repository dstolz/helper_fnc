        function labels = makeConciseLegendLabels(~, names)
            names = string(names(:));
            n = numel(names);
            if n == 0
                labels = strings(0, 1);
                return
            end

                % Keep filename stem only (drop path + extension).
                stems = strings(n, 1);
                for i = 1:n
                    [~, stem, ~] = fileparts(char(names(i)));
                    if stem == ""
                        stem = string(names(i));
                    end
                    stems(i) = stem;
                end

            if n == 1
                labels = stems;
                return
            end

            % Find shortest unique suffix by tokenizing on _ or -.
            tokenCells = cell(n, 1);
            maxParts = 0;
            for i = 1:n
                parts = string(regexp(stems(i), '[-_]+', 'split'));
                parts = parts(parts ~= "");
                if isempty(parts)
                    parts = stems(i);
                end
                tokenCells{i} = parts;
                maxParts = max(maxParts, numel(parts));
            end

                % First try: keep only token positions that vary across names.
                tokenMat = strings(n, maxParts);
                for i = 1:n
                    parts = tokenCells{i};
                    tokenMat(i, 1:numel(parts)) = parts;
                end

                varyingCols = false(1, maxParts);
                for c = 1:maxParts
                    col = tokenMat(:, c);
                    col = col(col ~= "");
                    varyingCols(c) = numel(unique(col)) > 1;
                end

                if any(varyingCols)
                    cand = strings(n, 1);
                    for i = 1:n
                        parts = tokenMat(i, varyingCols);
                        parts = parts(parts ~= "");
                        cand(i) = strjoin(parts, "_");
                    end
                    if all(cand ~= "") && numel(unique(cand)) == n
                        labels = cand;
                        return
                    end
                end

                % Second try: shortest unique suffix.
            for k = 1:maxParts
                cand = strings(n, 1);
                for i = 1:n
                    parts = tokenCells{i};
                    take = min(k, numel(parts));
                    cand(i) = strjoin(parts(end-take+1:end), "_");
                end
                if numel(unique(cand)) == n
                    labels = cand;
                    return
                end
            end

            % Fallback: strip longest common prefix characters.
            minLen = min(strlength(stems));
            nCommon = 0;
            for ci = 1:minLen
                prefixes = extractBefore(stems, ci + 1);
                if numel(unique(prefixes)) == 1
                    nCommon = ci;
                else
                    break
                end
            end
            labels = extractAfter(stems, nCommon);
            labels(strlength(labels) == 0) = stems(strlength(labels) == 0);
            labels = strtrim(regexprep(labels, '^[-_]+', ''));
        end
