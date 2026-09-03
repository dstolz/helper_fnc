function copyPlot(obj, options)
    %COPYPLOT Put the plot on the clipboard, without the panel beside it.
    %   B.copyPlot()
    %   B.copyPlot(ContentType = "vector")
    %
    % What the first two items of the Export menu do. An image pastes
    % into anything; vector graphics keep every curve a curve for
    % whatever will take one, which is most of what a figure ends up
    % in, and cannot be asked of the browser window itself.

    arguments
        obj
        options.ContentType (1,1) string ...
            {mustBeMember(options.ContentType, ["image", "vector"])} = "image"
    end

    if ~obj.canExport()
        return
    end

    f = obj.exportFigure();
    closeWhenDone = onCleanup(@() delete(f));

    note = "";

    try
        if options.ContentType == "vector"
            copygraphics(f, ContentType = "vector", ...
                BackgroundColor = obj.backgroundArg())
        else
            note = obj.copyImage(f);
        end
    catch ME
        uialert(obj.Fig, ME.message, "Could not copy the plot");
        return
    end

    obj.setStatus("Plot copied to the clipboard as " + ...
        options.ContentType + note + ".");

end
