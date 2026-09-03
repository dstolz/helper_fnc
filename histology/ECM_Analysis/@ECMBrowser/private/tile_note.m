function note = tile_note(nDrawn, nWanted)
%TILE_NOTE Say how many tiles are on screen, and how many were left off.

if nDrawn < nWanted
    note = sprintf("%d of %d tile(s), the rest left undrawn", nDrawn, nWanted);
else
    note = sprintf("%d tile(s)", nDrawn);
end

end
