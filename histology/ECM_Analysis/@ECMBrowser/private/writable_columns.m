function T = writable_columns(T)
%WRITABLE_COLUMNS Drop the columns WRITETABLE has nothing to write.
% A section table can carry a container per row rather than a value -- the
% profile itself, a list of the value files it was read from -- and one of
% those turns a CSV that would otherwise have been fine into an error.

names = string(T.Properties.VariableNames);
drop = false(1, numel(names));

for k = 1:numel(names)
    col = T.(names(k));
    drop(k) = (iscell(col) && ~all(cellfun(@ischar, col))) || ...
        istable(col) || isstruct(col) || ~ismatrix(col);
end

T(:, drop) = [];

end
