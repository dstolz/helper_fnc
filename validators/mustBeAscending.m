function mustBeAscending(A)
if A(2) <= A(1)
    throwAsCaller(MException(message('mustBeAscending')));
end
end