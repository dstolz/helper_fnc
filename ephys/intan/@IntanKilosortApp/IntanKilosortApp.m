classdef IntanKilosortApp < handle
    %INTANKILOSORTAPP  GUI for discovering Intan recordings and running Kilosort4.
    %   IntanKilosortApp is a thin front end over IntanKilosortProject and
    %   IntanDataset. It does not duplicate any of their logic: scanning,
    %   metadata, reading, filtering, .bin streaming and the Kilosort4 spawn all
    %   happen through those classes. The app only orchestrates them and shows
    %   progress.
    %
    %   Features
    %   --------
    %     1. Datasets   Pick a parent directory, scan recursively for *.rhd
    %                   folders, and view per-dataset metadata in a table.
    %     2. Visualize  Quick time-domain plots of a short window with optional
    %                   filtering / CAR / detrend. Display-only: the underlying
    %                   recording is never modified.
    %     3. Artifacts  Configure the automatic amplitude-deviation detector
    %                   (running-RMS, threshold in robust SDs, with stitching),
    %                   preview per-channel counts and the percent of the
    %                   recording it would zero, and enable blanking on .bin write.
    %     4. Probe      Pick a Kilosort4 probe .json (stored under
    %                   ephys/intan/probes by default), with a simple channel-
    %                   count check, and assign it to one or all datasets.
    %     5. Kilosort   Expose Kilosort4 / .bin configuration, save & reload it,
    %                   and batch-process selected datasets (.bin then KS4) with
    %                   per-dataset progress.
    %
    %   User preferences (paths, config, and the figure position/size) persist
    %   across sessions via getpref/setpref under the 'IntanKilosortApp' group.
    %
    %   Usage
    %   -----
    %     IntanKilosortApp;            % launch
    %     app = IntanKilosortApp;      % launch and keep a handle
    %
    %   See also INTANKILOSORTPROJECT, INTANDATASET.

    properties
        Fig   matlab.ui.Figure
        Tabs  matlab.ui.container.TabGroup

        TabDatasets  matlab.ui.container.Tab
        TabVisualize matlab.ui.container.Tab
        TabArtifacts matlab.ui.container.Tab
        TabProbe     matlab.ui.container.Tab
        TabKilosort  matlab.ui.container.Tab
        TabReview    matlab.ui.container.Tab

        % --- Datasets tab ---
        RootPathField    matlab.ui.control.EditField
        BrowseRootButton matlab.ui.control.Button
        ScanButton       matlab.ui.control.Button
        RefreshMetaButton matlab.ui.control.Button
        DatasetsTable    matlab.ui.control.Table
        ScanStatusLabel  matlab.ui.control.Label

        % --- Visualize tab ---
        VizDatasetDropDown matlab.ui.control.DropDown
        VizFileDropDown    matlab.ui.control.DropDown
        VizChannelsField   matlab.ui.control.EditField
        VizStartField      matlab.ui.control.NumericEditField
        VizDurField        matlab.ui.control.NumericEditField
        VizHighpassField   matlab.ui.control.EditField
        VizLowpassField    matlab.ui.control.EditField
        VizOrderField      matlab.ui.control.NumericEditField
        VizRefDropDown     matlab.ui.control.DropDown
        VizDetrendCheckBox matlab.ui.control.CheckBox
        VizSpacingField    matlab.ui.control.NumericEditField
        VizModeDropDown    matlab.ui.control.DropDown
        VizColormapDropDown matlab.ui.control.DropDown
        VizPlotButton      matlab.ui.control.Button
        VizArtButton       matlab.ui.control.StateButton
        VizArtClearButton  matlab.ui.control.Button
        VizArtStatusLabel  matlab.ui.control.Label
        VizAxes            matlab.ui.control.UIAxes
        VizStatusLabel     matlab.ui.control.Label
        VizHelpLabel       matlab.ui.control.Label

        % --- Artifacts tab ---
        ArtDatasetDropDown  matlab.ui.control.DropDown
        ArtEnableCheckBox   matlab.ui.control.CheckBox
        ArtMethodDropDown   matlab.ui.control.DropDown
        ArtThresholdField   matlab.ui.control.NumericEditField
        ArtRmsWindowField   matlab.ui.control.NumericEditField
        ArtMergeGapField    matlab.ui.control.NumericEditField
        ArtMinChannelsField matlab.ui.control.NumericEditField
        ArtPadField         matlab.ui.control.NumericEditField
        ArtFilterCheckBox   matlab.ui.control.CheckBox
        ArtHighpassField    matlab.ui.control.NumericEditField
        ArtDetectButton     matlab.ui.control.Button
        ArtSummaryLabel     matlab.ui.control.Label
        ArtChannelTable     matlab.ui.control.Table
        ArtStatusLabel      matlab.ui.control.Label

        % --- Probe tab ---
        ProbeFolderField    matlab.ui.control.EditField
        BrowseProbeFolderButton matlab.ui.control.Button
        ImportProbeButton   matlab.ui.control.Button
        RefreshProbesButton matlab.ui.control.Button
        ProbeTable          matlab.ui.control.Table
        ProbeInfoLabel      matlab.ui.control.Label
        ProbeCheckLabel     matlab.ui.control.Label
        ProbePreviewAxes    matlab.ui.control.UIAxes
        AssignSelectedButton matlab.ui.control.Button
        AssignAllButton     matlab.ui.control.Button
        ExcludeChannelsField matlab.ui.control.EditField
        ApplyExcludeSelectedButton matlab.ui.control.Button
        ApplyExcludeAllButton matlab.ui.control.Button

        % --- Kilosort tab ---
        PythonExeField    matlab.ui.control.EditField
        BrowsePythonButton matlab.ui.control.Button
        CondaEnvField     matlab.ui.control.EditField
        OutputRootField   matlab.ui.control.EditField
        BrowseOutputButton matlab.ui.control.Button
        PhyCmdField       matlab.ui.control.EditField
        ScaleField        matlab.ui.control.NumericEditField
        DtypeDropDown     matlab.ui.control.DropDown
        % Kilosort4 parameter controls, keyed by KS4 settings name. Built from
        % kilosortParamSpec(); see buildKilosortTab / buildKS4Extra.
        ParamControls struct = struct()
        ExtraSettingsArea matlab.ui.control.TextArea
        ExecModeDropDown  matlab.ui.control.DropDown
        DryRunCheckBox    matlab.ui.control.CheckBox
        SaveConfigButton  matlab.ui.control.Button
        LoadConfigButton  matlab.ui.control.Button
        WriteBinButton    matlab.ui.control.Button
        RunKilosortButton matlab.ui.control.Button
        LaunchPhyButton   matlab.ui.control.Button
        KSProgressLabel   matlab.ui.control.Label
        KSLogArea         matlab.ui.control.TextArea

        % --- Review tab ---
        ReviewFolderField   matlab.ui.control.EditField
        BrowseReviewButton  matlab.ui.control.Button
        ReviewDatasetDropDown matlab.ui.control.DropDown
        LoadReviewButton    matlab.ui.control.Button
        OpenReviewFolderButton matlab.ui.control.Button
        ReviewSummaryLabel  matlab.ui.control.Label
        ReviewUnitsTable    matlab.ui.control.Table
        ReviewAllUnitsButton matlab.ui.control.Button
        ReviewShankAxes     matlab.ui.control.UIAxes
        ReviewWaveAxes      matlab.ui.control.UIAxes
        ReviewAmpAxes       matlab.ui.control.UIAxes
        ReviewRateAxes      matlab.ui.control.UIAxes
    end

    properties
        Project IntanKilosortProject = IntanKilosortProject.empty
        SelectedRow (1,1) double = 0   % last-clicked datasets-table row (0 = none)

        % Probe tab selection state. ProbeTable shows one row per probe .json;
        % ProbePaths holds the matching full paths (the table itself only shows
        % file names + parsed metadata), and SelectedProbeRow is the active row.
        ProbePaths (1,:) string = string.empty(1,0)
        SelectedProbeRow (1,1) double = 0   % selected ProbeTable row (0 = none)

        % Background Kilosort4 runs awaiting completion + the polling timer.
        % logFile/logPos let the monitor tail each run's ks4_run.log into the
        % status box: logPos is the byte offset already shown.
        KSRuns struct = struct('Name', {}, 'statusFile', {}, 'resultsDir', {}, ...
            'logFile', {}, 'logPos', {}, 'done', {})
        KSMonitorTimer = []

        % --- Visualize interaction state (display-only, in-memory) ---
        % VizData caches the whole, already-preprocessed window so navigation
        % never re-reads or re-filters: X [nSamp x nCh], Fs, chans, name, clim0.
        VizData = struct([])
        % VizView holds the current viewport: tLeft/tWin (s), ampGain, yOffset,
        % and mode ("traces"|"heatmap").
        VizView = struct([])
        VizLines = []          % per-channel line handles (traces mode)
        VizImage = []          % image handle (heatmap mode)
        VizColorbar = []       % colorbar handle (heatmap mode)
        VizDrawnMode (1,1) string = ""   % mode currently drawn (triggers rebuild)
        VizMods (1,:) string = string.empty(1,0)   % held modifier keys
        VizPan = struct('active', false)            % middle-drag pan bookkeeping
        VizPixelBudget (1,1) double = 2500          % max plotted points per channel
        % Byte budget for the cached single-precision Visualize matrix. The
        % loader streams files one at a time and, when the full-resolution span
        % would exceed this, peak-decimates on load so RAM stays bounded
        % regardless of recording length. 0 = auto (see autoMemoryBudget).
        VizMemoryBudget (1,1) double = 0

        % --- Manual artifact marking (Visualize tab) ---
        % When VizArtMode is on, a plain left-drag on the plot defines an
        % artifact period and a left-click inside a marked region removes it.
        % Periods live on the dataset (IntanDataset.ManualArtifacts) and are
        % blanked by toBin; the data on disk is never altered. They are drawn
        % with xregion (handles in VizArtPatches; VizArtPreview is the live
        % rubber-band during a drag).
        VizArtMode (1,1) logical = false
        VizArtDrag = struct('active', false)
        VizArtPatches = gobjects(0,1)
        VizArtPreview = gobjects(0,1)

        % --- Review (Kilosort4 output) state ---
        % ReviewData caches everything parsed from a kilosort4/ results folder so
        % unit selection re-plots without re-reading .npy files. See
        % loadReviewResults / renderReviewPlots.
        ReviewData = struct([])
        ReviewSelectedUnit (1,1) double = 0   % row index into ReviewData unit list (0 = all)
    end

    properties (Constant)
        PrefGroup = 'IntanKilosortApp'
    end

    methods
        function obj = IntanKilosortApp()
            % Construct, build the UI, restore preferences.
            obj.buildUI();
            obj.loadPreferences();
            obj.refreshProbeList();

            if nargout == 0
                clear obj
            end
        end

        % --- declared in separate files in this @-folder ---
        buildUI(obj)
        buildDatasetsTab(obj)
        buildVisualizeTab(obj)
        buildArtifactsTab(obj)
        buildProbeTab(obj)
        buildKilosortTab(obj)
        buildReviewTab(obj)

        onScan(obj)
        refreshDatasetsTable(obj)
        onDatasetCellSelection(obj, evt)
        onRefreshMetadata(obj)

        onDetectArtifacts(obj)

        onPlotVisualization(obj)
        renderViz(obj)
        onVizScroll(obj, evt)
        onVizButtonDown(obj)
        onVizButtonMotion(obj)
        onVizButtonUp(obj)
        onVizKey(obj, evt, isPress)
        drawVizArtifacts(obj)

        refreshProbeList(obj)
        onProbeSelected(obj)
        onImportProbe(obj)
        onAssignProbe(obj, scope)
        onApplyExclude(obj, scope)

        spec = kilosortParamSpec(obj)
        [extra, errMsg] = buildKS4Extra(obj)
        cfg = gatherKilosortConfig(obj)
        applyKilosortConfig(obj, cfg)
        onSaveConfig(obj)
        onLoadConfig(obj)

        onRunBatch(obj, mode)
        onLaunchPhy(obj)
        pollKSRuns(obj)

        loadReviewResults(obj)
        renderReviewPlots(obj)

        loadPreferences(obj)
        savePreferences(obj)

        function startKSMonitor(obj)
            % Start (or leave running) the timer that polls background KS4 runs.
            t = obj.KSMonitorTimer;
            if ~isempty(t) && isvalid(t) && strcmp(t.Running, 'on')
                return   % already polling; it will pick up newly-added runs
            end
            obj.stopKSMonitor();   % clear any stale, stopped timer
            obj.KSMonitorTimer = timer( ...
                "Name", "IntanKilosortAppMonitor", ...
                "ExecutionMode", "fixedSpacing", "Period", 3, "BusyMode", "drop", ...
                "TimerFcn", @(~,~) obj.pollKSRuns());
            start(obj.KSMonitorTimer);
        end

        function stopKSMonitor(obj)
            % Stop and delete the polling timer if present.
            t = obj.KSMonitorTimer;
            if ~isempty(t) && isvalid(t)
                try
                    stop(t);
                catch
                end
                try
                    delete(t);
                catch
                end
            end
            obj.KSMonitorTimer = [];
        end

        %% --- small inline handlers --------------------------------------
        function onBrowseRoot(obj)
            % Prompt for the parent directory to scan.
            start = obj.RootPathField.Value;
            if isempty(start) || ~isfolder(start); start = pwd; end
            d = uigetdir(start, "Select parent directory to scan for *.rhd recordings");
            figure(obj.Fig);  % restore focus after modal dialog
            if isequal(d, 0); return; end
            obj.RootPathField.Value = d;
            obj.savePreferences();
        end

        function onBrowseProbeFolder(obj)
            % Prompt for the folder that holds probe .json files.
            start = obj.ProbeFolderField.Value;
            if isempty(start) || ~isfolder(start); start = obj.defaultProbeFolder(); end
            d = uigetdir(start, "Select folder containing Kilosort4 probe .json files");
            figure(obj.Fig);
            if isequal(d, 0); return; end
            obj.ProbeFolderField.Value = d;
            obj.refreshProbeList();
            obj.savePreferences();
        end

        function onBrowsePython(obj)
            % Prompt for the python/conda executable.
            [f, p] = uigetfile({'*.exe;python*', 'Executable'}, "Select python executable");
            figure(obj.Fig);
            if isequal(f, 0); return; end
            obj.PythonExeField.Value = fullfile(p, f);
            obj.savePreferences();
        end

        function onBrowseOutput(obj)
            % Prompt for the output root for .bin / Kilosort4 results.
            start = obj.OutputRootField.Value;
            if isempty(start) || ~isfolder(start); start = pwd; end
            d = uigetdir(start, "Select output root (per-dataset results go under <root>/<Name>)");
            figure(obj.Fig);
            if isequal(d, 0); return; end
            obj.OutputRootField.Value = d;
            obj.savePreferences();
        end

        %% --- Review tab handlers -----------------------------------------
        function onBrowseReviewFolder(obj)
            % Prompt for a Kilosort4 results folder to review.
            start = obj.ReviewFolderField.Value;
            if isempty(start) || ~isfolder(start); start = pwd; end
            d = uigetdir(start, "Select a Kilosort4 results folder (contains params.py)");
            figure(obj.Fig);
            if isequal(d, 0); return; end
            obj.ReviewFolderField.Value = d;
            obj.savePreferences();
            obj.loadReviewResults();
        end

        function onOpenReviewFolder(obj)
            % Open the current results folder in the system file browser.
            f = strtrim(obj.ReviewFolderField.Value);
            if isempty(f) || ~isfolder(f)
                uialert(obj.Fig, "Select a valid results folder first.", "Review");
                return
            end
            if ispc; winopen(f); else; system(sprintf('open "%s" &', f)); end
        end

        function populateReviewDatasets(obj)
            % Fill the Review dataset dropdown from scanned datasets whose
            % kilosort4/ results folder exists on disk.
            obj.ReviewDatasetDropDown.Items = {'(pick folder, or scan first)'};
            obj.ReviewDatasetDropDown.ItemsData = {};
            if isempty(obj.Project) || obj.Project.NumDatasets == 0; return; end
            obj.applyConfigToProject();
            names = {};
            dirs  = {};
            for k = 1:obj.Project.NumDatasets
                d = obj.Project.Datasets(k);
                rd = fullfile(char(d.outputFolder()), 'kilosort4');
                if isfile(fullfile(rd, 'params.py'))
                    names{end+1} = char(d.Name);   %#ok<AGROW>
                    dirs{end+1}  = rd;             %#ok<AGROW>
                end
            end
            if isempty(names)
                obj.ReviewDatasetDropDown.Items = {'(no kilosort4 results found)'};
            else
                obj.ReviewDatasetDropDown.Items = names;
                obj.ReviewDatasetDropDown.ItemsData = dirs;
            end
        end

        function onReviewDatasetChanged(obj)
            % Point the folder field at the chosen dataset's results and load.
            rd = obj.ReviewDatasetDropDown.Value;
            if isempty(rd) || ~ischar(rd) || ~isfolder(rd); return; end
            obj.ReviewFolderField.Value = rd;
            obj.savePreferences();
            obj.loadReviewResults();
        end

        function onReviewUnitSelected(obj, evt)
            % Table row click -> focus the plots on that single unit.
            % Look up by cluster ID so column-sort doesn't break the mapping.
            if isempty(obj.ReviewData) || isempty(evt.Indices)
                return
            end
            row = evt.Indices(1);
            T = obj.ReviewUnitsTable.Data;
            if iscell(T) && size(T, 1) >= row
                cid = T{row, 1};
            else
                return
            end
            unitIdx = find(obj.ReviewData.clusterID == cid, 1);
            if isempty(unitIdx); return; end
            obj.ReviewSelectedUnit = unitIdx;
            obj.renderReviewPlots();
        end

        function onReviewAllUnits(obj)
            % Clear the unit selection and show all units again.
            if isempty(obj.ReviewData); return; end
            obj.ReviewSelectedUnit = 0;
            if ~isempty(obj.ReviewUnitsTable.Selection)
                obj.ReviewUnitsTable.Selection = [];
            end
            obj.renderReviewPlots();
        end

        function onClose(obj)
            % Persist preferences (incl. figure geometry) and close.
            obj.stopKSMonitor();
            try
                obj.savePreferences();
            catch ME
                warning('IntanKilosortApp:SavePrefsFailed', ...
                    'Could not save preferences: %s', ME.message);
            end
            delete(obj.Fig);
        end

        function log(obj, fmt, varargin)
            % Append a timestamped line to the Kilosort log area.
            line = sprintf("%s  %s", datetime('now', 'Format', 'HH:mm:ss'), ...
                string(sprintf(fmt, varargin{:})));
            obj.appendLogLines(line);
        end

        function appendLogLines(obj, lines)
            % Append a block of pre-formatted lines to the Kilosort log area in
            % a single update (cheaper than calling log() per line when tailing
            % a run's ks4_run.log). Empty input is a no-op.
            lines = cellstr(string(lines(:)));
            if isempty(lines); return; end
            cur = obj.KSLogArea.Value;
            if isscalar(cur) && strlength(string(cur{1})) == 0
                cur = cell(0, 1);   % drop the default blank line
            end
            obj.KSLogArea.Value = [cur; lines];
            scroll(obj.KSLogArea, 'bottom');
            drawnow limitrate;
        end

        %% --- Probe tab handlers ------------------------------------------
        function pf = selectedProbeFile(obj)
            % Full path of the probe in the currently selected ProbeTable row
            % ("" if none). The table shows names + metadata; paths live here.
            pf = "";
            r = obj.SelectedProbeRow;
            if r >= 1 && r <= numel(obj.ProbePaths)
                pf = obj.ProbePaths(r);
            end
        end

        function onProbeRowSelected(obj, evt)
            % ProbeTable row click -> update the active probe and its info/plot.
            if isempty(evt.Indices); return; end
            obj.SelectedProbeRow = evt.Indices(1);
            obj.onProbeSelected();
        end

        function syncExcludeField(obj)
            % Mirror the active dataset's ExcludeChannels into the edit field.
            % No-op for the field's enable; just reflects the per-recording list.
            if isempty(obj.ExcludeChannelsField) || ~isvalid(obj.ExcludeChannelsField)
                return
            end
            d = obj.currentDataset();
            if isempty(d)
                obj.ExcludeChannelsField.Value = '';
            else
                obj.ExcludeChannelsField.Value = ...
                    char(IntanDataset.formatChannelList(d.ExcludeChannels));
            end
        end

        function selectProbeRow(obj, row)
            % Programmatically focus a ProbeTable row (highlight + info panel).
            if row < 1 || row > numel(obj.ProbePaths); return; end
            obj.SelectedProbeRow = row;
            try
                obj.ProbeTable.Selection = row;   % R2023a+ row highlight
            catch
            end
            obj.onProbeSelected();
        end

        function onProbeNotesEdited(obj, evt)
            % Persist an edited Notes cell back into the probe .json file.
            if isempty(evt.Indices); return; end
            row = evt.Indices(1);
            if row < 1 || row > numel(obj.ProbePaths); return; end
            pf = obj.ProbePaths(row);
            try
                obj.saveProbeNotes(pf, string(evt.NewData));
            catch ME
                uialert(obj.Fig, "Could not save notes: " + string(ME.message), ...
                    "Probe notes");
                T = obj.ProbeTable.Data;   % revert the displayed value
                if istable(T) && row <= height(T)
                    T.Notes(row) = string(evt.PreviousData);
                    obj.ProbeTable.Data = T;
                end
            end
        end

        function saveProbeNotes(obj, pf, notes) %#ok<INUSL>
            % Write the optional "notes" field into a probe .json with a minimal
            % textual edit (replace in place if present, otherwise insert as the
            % first field) so the file's hand-formatting is preserved.
            txt = fileread(pf);
            enc = jsonencode(string(notes));   % quoted, JSON-escaped literal
            if ~isempty(regexp(txt, '"notes"\s*:', 'once'))
                escRep = regexprep(['"notes": ' enc], '([\\$])', '\\$1');
                txt = regexprep(txt, ...
                    '"notes"\s*:\s*("(?:[^"\\]|\\.)*"|null|true|false|-?[0-9.eE+]+)', ...
                    escRep, 'once');
            else
                b = strfind(txt, '{');
                if isempty(b); error('not a JSON object'); end
                ins = [newline '  "notes": ' enc ','];
                txt = [txt(1:b(1)) ins txt(b(1)+1:end)];
            end
            fid = fopen(pf, 'w');
            if fid < 0; error('cannot open %s for writing', pf); end
            closer = onCleanup(@() fclose(fid));
            fwrite(fid, txt);
        end

        function p = defaultProbeFolder(~)
            % Repository probe folder: ephys/intan/probes (next to this @-folder).
            here = fileparts(mfilename('fullpath'));        % .../@IntanKilosortApp
            p = fullfile(fileparts(here), 'probes');         % .../intan/probes
        end

        function p = defaultConfigFolder(~)
            % Repository config folder: ephys/intan/ks4_configs.
            here = fileparts(mfilename('fullpath'));
            p = fullfile(fileparts(here), 'ks4_configs');
        end

        function d = currentDataset(obj)
            % Return the IntanDataset for the last-selected table row ([] if none).
            d = IntanDataset.empty;
            if isempty(obj.Project) || obj.SelectedRow < 1; return; end
            if obj.SelectedRow <= obj.Project.NumDatasets
                d = obj.Project.Datasets(obj.SelectedRow);
            end
        end

        function applyConfigToProject(obj, P)
            % Push shared run config (python/conda/output/scale/dtype) into a
            % project so discover()/pushConfig propagate it to every dataset.
            if nargin < 2 || isempty(P); P = obj.Project; end
            if isempty(P); return; end
            P.PythonExe  = string(obj.PythonExeField.Value);
            P.CondaEnv   = string(obj.CondaEnvField.Value);
            P.OutputRoot = string(obj.OutputRootField.Value);
            P.Scale      = obj.ScaleField.Value;
            P.Dtype      = string(obj.DtypeDropDown.Value);
            % Set fields directly (NOT pushConfig) so per-dataset ProbeFile
            % assignments made on the Probe tab are preserved.
            for k = 1:P.NumDatasets
                d = P.Datasets(k);
                d.PythonExe = P.PythonExe;
                d.CondaEnv  = P.CondaEnv;
                d.Scale     = P.Scale;
                d.Dtype     = P.Dtype;
                if P.OutputRoot ~= ""
                    d.OutputDir = fullfile(P.OutputRoot, d.Name);
                end
            end
        end

        function populateVizDatasets(obj)
            % Fill the Visualize dataset dropdown from the scanned project.
            if isempty(obj.Project) || obj.Project.NumDatasets == 0
                obj.VizDatasetDropDown.Items = {'(scan first)'};
                obj.VizDatasetDropDown.ItemsData = {};
                obj.VizFileDropDown.Items = {'(all)'};
                return
            end
            names = cellstr([obj.Project.Datasets.Name]);
            obj.VizDatasetDropDown.Items = names;
            obj.VizDatasetDropDown.ItemsData = num2cell(1:numel(names));
            obj.populateVizFiles();
        end

        function onVizModeChanged(obj)
            % Switch traces <-> heatmap without re-reading/re-filtering.
            if isempty(obj.VizData) || ~isfield(obj.VizData, 'X'); return; end
            obj.VizView.mode = string(obj.VizModeDropDown.Value);
            obj.renderViz();
        end

        function onVizColormapChanged(obj)
            % Re-render so a new heatmap colormap takes effect immediately.
            if isempty(obj.VizData) || ~isfield(obj.VizData, 'X'); return; end
            obj.renderViz();
        end

        function tf = vizActive(obj)
            % True when there is cached data and the Visualize tab is showing.
            tf = ~isempty(obj.VizData) && isfield(obj.VizData, 'X') ...
                && isvalid(obj.Fig) && obj.Tabs.SelectedTab == obj.TabVisualize;
        end

        function tf = cursorOverAxes(obj)
            % True when the pointer is inside the Visualize axes (pixel coords).
            pp = getpixelposition(obj.VizAxes, true);
            cp = obj.Fig.CurrentPoint;
            tf = cp(1) >= pp(1) && cp(1) <= pp(1) + pp(3) ...
                && cp(2) >= pp(2) && cp(2) <= pp(2) + pp(4);
        end

        %% --- Manual artifact marking (Visualize tab) ---------------------
        function d = currentVizDataset(obj)
            % Dataset handle backing the currently cached Visualize data ([] none).
            d = IntanDataset.empty;
            if isempty(obj.VizData) || ~isfield(obj.VizData, 'dsIndex'); return; end
            i = obj.VizData.dsIndex;
            if ~isempty(obj.Project) && i >= 1 && i <= obj.Project.NumDatasets
                d = obj.Project.Datasets(i);
            end
        end

        function onVizArtToggle(obj, val)
            % Enter/leave artifact-marking mode (drives the left-drag gesture).
            obj.VizArtMode = logical(val);
            if obj.VizArtMode
                obj.VizArtButton.Text = "Mark Artifacts: ON (drag to mark)";
                obj.VizArtButton.FontWeight = "bold";
                if isvalid(obj.Fig); obj.Fig.Pointer = "crosshair"; end
            else
                obj.VizArtButton.Text = "Mark Artifacts: off";
                obj.VizArtButton.FontWeight = "normal";
                if isvalid(obj.Fig); obj.Fig.Pointer = "arrow"; end
            end
        end

        function onVizArtClear(obj)
            % Remove all manual artifact periods for the current dataset.
            d = obj.currentVizDataset();
            if isempty(d) || isempty(d.ManualArtifacts)
                obj.updateVizArtStatus();
                return
            end
            d.ManualArtifacts = zeros(0, 2);
            obj.renderViz();
            obj.updateVizArtStatus();
        end

        function onVizArtMotion(obj)
            % Stretch the rubber-band region while an artifact drag is active.
            D = obj.VizArtDrag;
            if ~isstruct(D) || ~isfield(D, 'active') || ~D.active; return; end
            x1 = obj.VizAxes.CurrentPoint(1, 1);
            lo = min(D.x0, x1); hi = max(D.x0, x1);
            if isempty(obj.VizArtPreview) || ~isvalid(obj.VizArtPreview)
                obj.VizArtPreview = xregion(obj.VizAxes, lo, hi, ...
                    'FaceColor', [0.85 0.2 0.2], 'FaceAlpha', 0.15);
            else
                obj.VizArtPreview.Value = [lo hi];
            end
        end

        function finishVizArtDrag(obj)
            % End an artifact gesture: a drag defines a period, a click deletes one.
            D = obj.VizArtDrag;
            obj.VizArtDrag = struct('active', false);
            if isvalid(obj.Fig); obj.Fig.WindowButtonMotionFcn = ''; end
            if ~isempty(obj.VizArtPreview) && isvalid(obj.VizArtPreview)
                delete(obj.VizArtPreview);
            end
            obj.VizArtPreview = gobjects(0, 1);

            d = obj.currentVizDataset();
            if isempty(d); return; end

            x0 = D.x0;
            x1 = obj.VizAxes.CurrentPoint(1, 1);
            tOff = 0;
            if isfield(obj.VizData, 'tOffset'); tOff = obj.VizData.tOffset; end

            % Treat a sub-few-pixel move as a click (delete) rather than a drag.
            secPerPix = obj.VizView.tWin / max(D.axPix(3), 1);
            if abs(x1 - x0) >= 4 * secPerPix
                d.addArtifact(min(x0, x1) + tOff, max(x0, x1) + tOff);
            else
                iv = d.ManualArtifacts;
                if ~isempty(iv)
                    hit = find((x0 + tOff) >= iv(:, 1) & (x0 + tOff) <= iv(:, 2), 1);
                    if ~isempty(hit)
                        iv(hit, :) = [];
                        d.ManualArtifacts = iv;
                    end
                end
            end
            obj.renderViz();
            obj.updateVizArtStatus();
        end

        function updateVizArtStatus(obj)
            % Refresh the artifact-count label under the Visualize controls.
            if isempty(obj.VizArtStatusLabel) || ~isvalid(obj.VizArtStatusLabel); return; end
            d = obj.currentVizDataset();
            if isempty(d) || isempty(d.ManualArtifacts)
                obj.VizArtStatusLabel.Text = "No artifacts defined.";
                return
            end
            iv = d.ManualArtifacts;
            obj.VizArtStatusLabel.Text = sprintf( ...
                "%d artifact period(s), %.3f s total (blanked on .bin write).", ...
                size(iv, 1), sum(iv(:, 2) - iv(:, 1)));
        end

        function populateVizFiles(obj)
            % Fill the Visualize file dropdown for the chosen dataset.
            idx = obj.VizDatasetDropDown.Value;
            if isempty(idx) || ~isnumeric(idx) || isempty(obj.Project) ...
                    || idx > obj.Project.NumDatasets
                obj.VizFileDropDown.Items = {'(all)'};
                return
            end
            d = obj.Project.Datasets(idx);
            if d.NumFiles == 0; d.discoverFiles(); end
            obj.VizFileDropDown.Items = ['(all)'; cellstr(d.Files(:))];
        end

        %% --- Artifacts tab -----------------------------------------------
        function populateArtifactDatasets(obj)
            % Fill the Artifacts dataset dropdown from the scanned project.
            if isempty(obj.Project) || obj.Project.NumDatasets == 0
                obj.ArtDatasetDropDown.Items = {'(scan first)'};
                obj.ArtDatasetDropDown.ItemsData = {};
                return
            end
            names = cellstr([obj.Project.Datasets.Name]);
            obj.ArtDatasetDropDown.Items = names;
            obj.ArtDatasetDropDown.ItemsData = num2cell(1:numel(names));
        end

        function d = currentArtifactDataset(obj)
            % Dataset selected on the Artifacts tab ([] if none).
            d = IntanDataset.empty;
            idx = obj.ArtDatasetDropDown.Value;
            if isempty(idx) || ~isnumeric(idx) || isempty(obj.Project) ...
                    || idx > obj.Project.NumDatasets
                return
            end
            d = obj.Project.Datasets(idx);
        end

        function cfg = artifactConfigFromControls(obj)
            % Build an ArtifactConfig struct from the tab controls. All timing
            % parameters are in milliseconds; detectArtifacts converts them to
            % samples with each dataset's Fs at run time.
            cfg = IntanDataset.defaultArtifactConfig();
            cfg.Enabled     = logical(obj.ArtEnableCheckBox.Value);
            cfg.Method      = string(obj.ArtMethodDropDown.Value);
            cfg.Threshold   = obj.ArtThresholdField.Value;
            cfg.MergeGapMs  = obj.ArtMergeGapField.Value;
            cfg.MinChannels = max(1, round(obj.ArtMinChannelsField.Value));
            cfg.PadMs       = obj.ArtPadField.Value;
            winMs = obj.ArtRmsWindowField.Value;
            if winMs > 0
                cfg.RmsWindowMs = winMs;
            else
                cfg.RmsWindowMs = NaN;   % auto (~1 ms) resolved at run time
            end
        end

        function applyArtifactConfigToProject(obj)
            % Push the tab's detection config onto every scanned dataset so the
            % .bin write (onRunBatch) blanks consistently across the batch.
            if isempty(obj.Project) || obj.Project.NumDatasets == 0; return; end
            cfg = obj.artifactConfigFromControls();
            for k = 1:obj.Project.NumDatasets
                obj.Project.Datasets(k).ArtifactConfig = cfg;
            end
        end

        function onArtifactControlsChanged(obj)
            % Sync RMS-only field enable state and persist the config to disk
            % whenever a detection control changes.
            isRms = string(obj.ArtMethodDropDown.Value) == "rms";
            obj.ArtRmsWindowField.Enable = matlab.lang.OnOffSwitchState(isRms);
            obj.ArtFilterCheckBox.Enable = "on";
            obj.ArtHighpassField.Enable  = matlab.lang.OnOffSwitchState( ...
                logical(obj.ArtFilterCheckBox.Value));
            obj.applyArtifactConfigToProject();
            obj.savePreferences();
        end

        function idx = selectedDatasetIndices(obj)
            % Indices of datasets ticked in the table's "Select" column.
            % Falls back to all datasets when none are ticked.
            idx = [];
            if isempty(obj.Project) || obj.Project.NumDatasets == 0; return; end
            T = obj.DatasetsTable.Data;
            if istable(T) && any(strcmp('Select', T.Properties.VariableNames))
                idx = find(T.Select(:).');
            end
            if isempty(idx)
                idx = 1:obj.Project.NumDatasets;
            end
        end
    end
end
