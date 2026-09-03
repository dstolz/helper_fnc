function file = saveData(obj, filename, options)
    %SAVEDATA Write the numbers behind the plot to a delimited file.
    %   B.saveData()                                asks where
    %   B.saveData("profiles.csv")
    %   B.saveData("samples.csv", Layout = "long")
    %   B.saveData("sections.csv", Layout = "sections")
    %
    % Three layouts, because three different things get asked of one
    % view. "wide" is a depth column and one intensity column per
    % section, which is what a plotting program wants pasted into it.
    % "long" is one row per sample, carrying every field the sections
    % can be grouped or filtered by, which is what a statistics
    % package wants; the depths a section never reached are left out
    % rather than written as blanks. "sections" is one row per section
    % -- the table beside the profiles, with the peak added to it on
    % the scale the plot is drawn on.
    %
    % Under a comparison all three are written per comparison rather
    % than per section, and "sections" carries the account of it:
    % which operation between which two values, how many sections
    % went into each side, and the peak of the result.

    arguments
        obj
        filename (1,1) string = ""
        options.Layout (1,1) string ...
            {mustBeMember(options.Layout, ["wide", "long", "sections"])} = "wide"
    end

    file = "";

    if ~obj.canExport()
        return
    end

    if filename == ""
        filename = obj.askForFile(obj.DataFormats, ...
            "Save " + options.Layout + " data", ...
            obj.defaultFileName() + " " + options.Layout);

        if filename == ""
            return
        end
    end

    try
        T = obj.viewTable(options.Layout);
        writetable(T, filename)
    catch ME
        uialert(obj.Fig, ME.message, "Could not save the data");
        return
    end

    file = filename;
    obj.setStatus(sprintf("Saved %d row(s) to %s", height(T), filename));

end
