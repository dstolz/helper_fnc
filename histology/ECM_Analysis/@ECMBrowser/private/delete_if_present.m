function delete_if_present(file)
%DELETE_IF_PRESENT Remove a scratch file, and say nothing if it never appeared.

if isfile(file)
    delete(file)
end

end
