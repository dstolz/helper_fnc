function file = savePlot(obj, filename)
    %SAVEPLOT Write the plot to a file, without the panel beside it.
    %   B.savePlot()                   asks where, and in what format
    %   B.savePlot("profiles.pdf")
    %
    % The format is the extension: PNG, TIFF, and JPEG are written at
    % the resolution the Export menu is set to, PDF, EPS, and SVG as
    % vector graphics that stay sharp however large they are printed,
    % and .fig as the figure itself, to be opened and edited later.
    % What was written is handed back, and "" if the dialog was
    % canceled or the write failed.

    arguments
        obj
        filename (1,1) string = ""
    end

    file = "";

    if ~obj.canExport()
        return
    end

    if filename == ""
        filename = obj.askForFile(obj.PlotFormats, "Save plot", obj.defaultFileName());

        if filename == ""
            return
        end
    end

    [~, ~, ext] = fileparts(filename);
    ext = lower(string(ext));

    if ext == ""
        ext = ".png";
        filename = filename + ext;
    end

    [background, note] = obj.backgroundArg(ext);

    f = obj.exportFigure();
    closeWhenDone = onCleanup(@() delete(f));

    try
        switch ext

            case ".fig"
                % SAVEFIG records the figure as it stands, its
                % visibility included, and the export figure is drawn
                % out of sight: a .fig saved from it as it is would
                % open into a window nobody can see.
                f.Visible = "on";
                savefig(f, char(filename))

            case ".svg"
                % PRINT writes the SVG, and it has no background of
                % its own to be told about: the paper is the figure's
                % color, and only if the figure is also told not to
                % have it turned white on the way out.
                if background == "none"
                    set(f, Color = "none", InvertHardcopy = "off")
                end

                print(f, '-dsvg', char(filename))

            case {".pdf", ".eps"}
                exportgraphics(f, filename, ContentType = "vector", ...
                    BackgroundColor = background)

            otherwise
                exportgraphics(f, filename, ...
                    Resolution = obj.ExportResolution, ...
                    BackgroundColor = background)
        end
    catch ME
        uialert(obj.Fig, ME.message, "Could not save the plot");
        return
    end

    file = filename;
    obj.setStatus("Saved " + filename + note);

end
