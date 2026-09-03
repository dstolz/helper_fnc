function [color, note] = backgroundArg(obj, ext)
    %BACKGROUNDARG What goes behind the plot in a file of this kind.
    % Transparency is something only the vector formats carry: PNG,
    % TIFF, and JPEG are written on white whatever is asked of them,
    % and MATLAB says so on the console rather than where the choice
    % was made, so it is said here instead and the caller puts it in
    % the status line. A .fig has no paper behind it to argue about,
    % being the figure itself rather than a picture of one, and
    % "clipboard" is the vector copy: the image one is a PNG and asks
    % under that name, so that it is answered as the bitmap it is.

    arguments
        obj
        ext (1,1) string = "clipboard"
    end

    color = "white";
    note = "";

    if obj.ExportBackground ~= "transparent"
        return
    end

    if ismember(ext, [".pdf", ".eps", ".svg", "clipboard"])
        color = "none";
    elseif ext ~= ".fig"
        note = ", on white -- no bitmap format holds transparency";
    end

end
