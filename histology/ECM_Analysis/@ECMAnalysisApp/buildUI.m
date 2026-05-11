        function buildUI(obj)
            obj.Fig = uifigure("Name", "ECM Analysis", "Position", [120 80 1300 760]);
            obj.Tabs = uitabgroup(obj.Fig, "Position", [10 10 1280 740]);

            obj.TabLoad = uitab(obj.Tabs, "Title", "Load");
            obj.TabConfigure = uitab(obj.Tabs, "Title", "Configure");
            obj.TabPlot = uitab(obj.Tabs, "Title", "Plot");
            obj.TabExport = uitab(obj.Tabs, "Title", "Export");

            obj.buildLoadTab();
            obj.buildConfigureTab();
            obj.buildPlotTab();
            obj.buildExportTab();
        end
