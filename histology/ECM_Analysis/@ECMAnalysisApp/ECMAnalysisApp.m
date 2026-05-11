classdef ECMAnalysisApp < handle
    %ECMANALYSISAPP GUI for structured ECM data loading, analysis, plotting, and export.

    properties
        Fig matlab.ui.Figure
        Tabs matlab.ui.container.TabGroup

        TabLoad matlab.ui.container.Tab
        TabConfigure matlab.ui.container.Tab
        TabPlot matlab.ui.container.Tab
        TabExport matlab.ui.container.Tab

        RootPathField matlab.ui.control.EditField
        MetadataPathField matlab.ui.control.EditField
        LoadButton matlab.ui.control.Button
        LoadStatusLabel matlab.ui.control.Label
        ValidationStatusLabel matlab.ui.control.Label
        DiagnosticsStatusLabel matlab.ui.control.Label
        ExportDiagnosticsButton matlab.ui.control.Button
        DiagnosticsTable matlab.ui.control.Table

        GroupVarsList matlab.ui.control.ListBox
        PeakMinField matlab.ui.control.NumericEditField
        PeakMaxField matlab.ui.control.NumericEditField
        SmoothMethodDropDown matlab.ui.control.DropDown
        SmoothWindowField matlab.ui.control.NumericEditField
        ErrorMetricDropDown matlab.ui.control.DropDown
        NormalizeDropDown matlab.ui.control.DropDown
        RecomputeButton matlab.ui.control.Button

        PlotTypeDropDown matlab.ui.control.DropDown
        PlotColorDropDown matlab.ui.control.DropDown
        PlotLineWidthField matlab.ui.control.NumericEditField
        PlotAxes matlab.ui.control.UIAxes

        FacetVarsList matlab.ui.control.ListBox
        FacetLayoutDropDown matlab.ui.control.DropDown
        FacetMaxRowsField matlab.ui.control.NumericEditField
        FacetMaxColsField matlab.ui.control.NumericEditField
        PlotInFigureButton matlab.ui.control.Button
        PlotInPanelButton matlab.ui.control.Button

        ExportProcessedButton matlab.ui.control.Button
        ExportSummaryButton matlab.ui.control.Button
        ExportPngButton matlab.ui.control.Button
        ExportFigButton matlab.ui.control.Button
        ExportScriptButton matlab.ui.control.Button
        SaveSessionButton matlab.ui.control.Button
        LoadSessionButton matlab.ui.control.Button
    end

    properties
        Data struct = struct()
        Analysis struct = struct()
        GroupChoices string = strings(0,1)
        FacetFigure matlab.ui.Figure = matlab.ui.Figure.empty
        FacetPanel = []
    end

    methods
        function obj = ECMAnalysisApp()
            % Construct and initialize the app.
            obj.buildUI();
            obj.initializeState();

            if nargout == 0
                clear obj
            end
        end

        buildUI(obj) % Build the top-level figure and tabs.

        function initializeState(obj)
            % Initialize default widget state and load saved preferences.
            obj.LoadStatusLabel.Text = "Idle";
            obj.GroupVarsList.Items = {};
            obj.GroupVarsList.Value = {};
            obj.loadPreferences();
        end

        buildLoadTab(obj) % Build the data loading controls and diagnostics table.

        buildConfigureTab(obj) % Build analysis parameter controls.

        buildPlotTab(obj) % Build plotting controls and axes.

        buildExportTab(obj) % Build data/session export controls.

        function onBrowseRoot(obj)
            % Prompt for and set the root data folder.
            d = uigetdir(obj.RootPathField.Value, "Select root folder containing *_values.csv files");
            if isequal(d, 0)
                return
            end
            obj.RootPathField.Value = d;
            obj.savePreferences();
        end

        function onBrowseMetadata(obj)
            % Prompt for and set the metadata CSV file.
            [f, p] = uigetfile("*.csv", "Select metadata CSV");
            if isequal(f, 0)
                return
            end
            obj.MetadataPathField.Value = fullfile(p, f);
            obj.savePreferences();
        end

        onLoadData(obj) % Load input tables and refresh diagnostics.

        function updateProgress(~, dlg, iFile, nFiles, filePath)
            % Update progress UI during batch loading.
            if ~isvalid(dlg)
                return
            end
            dlg.Value = min(1, iFile / nFiles);
            [~, fn, ext] = fileparts(char(filePath));
            dlg.Message = sprintf("%d/%d: %s", iFile, nFiles, fn + string(ext));
        end

        function finishLoadUI(obj, dlg)
            % Restore UI state after load completion.
            if isvalid(obj.LoadButton)
                obj.LoadButton.Enable = "on";
            end
            if isvalid(dlg)
                close(dlg);
            end
        end

        function txt = makeLoadSummaryText(~, S)
            % Build summary status text after loading.
            txt = sprintf("Loaded %d rows from %d/%d files (%d failed, %d cancelled).", ...
                S.summary.nCombinedRows, S.summary.nSucceeded, S.summary.nDiscoveredFiles, ...
                S.summary.nFailed, S.summary.nCancelled);
        end

        refreshGroupChoices(obj) % Refresh group variable options from loaded table columns.

        onRecompute(obj) % Recompute derived analysis tables from selected options.

        onRenderPlot(obj) % Render selected plot mode.

        onRenderTiledFacets(obj, useInline) % Render tiled facets in new figure or inline panel.

        showPlotAxes(obj) % Show PlotAxes, hide FacetPanel.

        showFacetPanel(obj) % Show FacetPanel, hide PlotAxes.

        [co, cmap] = resolvePlotColors(obj, nColors) % Resolve selected color order and colormap.

        labels = makeConciseLegendLabels(obj, names) % Build minimal unique legend labels.

        plotOverlay(obj, ax) % Plot raw and smoothed overlay traces.

        plotGroupedMean(obj, ax) % Plot grouped mean with error bands.

        plotPeakSummary(obj, ax) % Plot peak summary scatter.

        plotHeatmap(obj, ax) % Plot per-file intensity heatmap.

        plotFacetsFigure(obj) % Plot per-subject tiled facets in a separate figure.

        plotTiledFacets(obj, useInline) % Plot with tiled layout using user-selected facet variables.

        onExportDiagnostics(obj) % Export diagnostics table to CSV.

        onExportProcessed(obj) % Export processed aligned table to CSV.

        onExportSummary(obj) % Export grouped summary table to CSV.

        function onExportPng(obj)
            % Export current plot axes to PNG.
            [f, p] = uiputfile("*.png", "Save current plot as PNG");
            if isequal(f, 0)
                return
            end
            exportgraphics(obj.PlotAxes, fullfile(p, f));
        end

        onExportFig(obj) % Export current plot to FIG.

        onExportScript(obj) % Export reproducible MATLAB script.

        onSaveSession(obj) % Save app state to MAT session file.

        onLoadSession(obj) % Load app state from MAT session file.

        D = buildDiagnosticsTable(~, S) % Build merged diagnostics table including schema warnings.

        updateDiagnosticsStatus(obj) % Update diagnostics status summary label.

        updateValidationStatus(obj) % Update analysis validation status label.

        s = getUIState(obj) % Capture current control state for session persistence.

        applyUIState(obj, s) % Apply persisted control state to UI.

        loadPreferences(obj) % Load saved preferences for directories and analysis settings.

        savePreferences(obj) % Save current settings as preferences.
    end
end
