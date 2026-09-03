function note = copyImage(obj, f)
    %COPYIMAGE Put the plot on the clipboard as a PNG.
    % COPYGRAPHICS offers a Windows bitmap and nothing besides, which
    % the desktop applications read and the ones that live in a
    % browser -- Google Slides among them -- quietly ignore, so a
    % paste there does nothing at all and says nothing about why. The
    % plot is written to a scratch PNG at the export resolution
    % instead and put on the clipboard twice over: under PNG, which
    % the browser applications look for, and under bitmap, which the
    % desktop ones look for and which Windows makes the older DIB
    % formats out of. Whatever it is pasted into takes the one it
    % knows. A PNG is a bitmap format like the others, so
    % transparency is no more on offer here than in a saved one, and
    % the note saying so goes back to the caller for the status line.

    [background, note] = obj.backgroundArg(".png");

    scratch = string(tempname) + ".png";
    cleanUp = onCleanup(@() delete_if_present(scratch));

    exportgraphics(f, scratch, Resolution = obj.ExportResolution, ...
        BackgroundColor = background)

    if ispc
        copy_png_to_clipboard(scratch)
    else
        % The clipboard is reached through .NET, which is on Windows
        % alone; elsewhere the bitmap is all there is to give.
        copygraphics(f, ContentType = "image", ...
            Resolution = obj.ExportResolution, ...
            BackgroundColor = background)
    end

end
