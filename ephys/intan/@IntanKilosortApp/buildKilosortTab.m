function buildKilosortTab(obj)
%buildKilosortTab  SpikeInterface preprocessing + Kilosort4 config + batch run.
%   The recording is converted for Kilosort4 through SpikeInterface
%   (read_intan -> attach probe -> preprocessing -> run_sorter); there is no
%   MATLAB-side .bin. The left panel exposes the connection paths, the
%   SpikeInterface preprocessing chain (bad-channel detection, artifact
%   silencing, optional common reference / bandpass filter), and the full
%   Kilosort4 parameter set from kilosortParamSpec(). Kilosort4 still high-pass
%   filters and whitens internally, so the SI bandpass is off by default.

spec = obj.kilosortParamSpec();
groups = unique({spec.group}, 'stable');

% Row budget (over-estimated; extra rows are harmless scroll space, under-sizing
% errors): connection (4) + preprocessing header + 6 rows + per group
% [header + ceil(nParams/2)] + JSON + buttons + slack.
nRows = 12;
for gi = 1:numel(groups)
    np = sum(strcmp({spec.group}, groups{gi}));
    nRows = nRows + 1 + ceil(np / 2);
end
nRows = nRows + 5;

g = uigridlayout(obj.TabKilosort, [1 2]);
g.ColumnWidth = {720, '1x'};
g.Padding     = [10 10 10 10];

% =================== left column: configuration ===================
cfg = uipanel(g, "Title", "Configuration");
cfg.Layout.Column = 1;
cg = uigridlayout(cfg, [nRows 5]);
cg.Scrollable  = "on";
cg.RowHeight   = repmat({26}, 1, nRows);
cg.ColumnWidth = {150, '1x', 150, '1x', 30};

r = 1;
lab(cg, "Python exe:", r);
obj.PythonExeField = uieditfield(cg, "text", "Placeholder", "kilosort env python.exe");
obj.PythonExeField.Layout.Row = r; obj.PythonExeField.Layout.Column = [2 4];
obj.BrowsePythonButton = uibutton(cg, "Text", "...", ...
    "ButtonPushedFcn", @(~,~) obj.onBrowsePython());
obj.BrowsePythonButton.Layout.Row = r; obj.BrowsePythonButton.Layout.Column = 5;

r = r + 1;
l = lab(cg, "Conda env:", r);
l.Tooltip = "Optional. When set, the pipeline runs via 'conda run -n <env>'. Leave blank if the Python exe above is already the kilosort env python.";
obj.CondaEnvField = uieditfield(cg, "text", "Placeholder", "optional (e.g. kilosort)");
obj.CondaEnvField.Layout.Row = r; obj.CondaEnvField.Layout.Column = [2 5];

r = r + 1;
lab(cg, "Output root:", r);
obj.OutputRootField = uieditfield(cg, "text", "Placeholder", "optional (defaults to each dataset folder)");
obj.OutputRootField.Layout.Row = r; obj.OutputRootField.Layout.Column = [2 4];
obj.BrowseOutputButton = uibutton(cg, "Text", "...", ...
    "ButtonPushedFcn", @(~,~) obj.onBrowseOutput());
obj.BrowseOutputButton.Layout.Row = r; obj.BrowseOutputButton.Layout.Column = 5;

r = r + 1;
l = lab(cg, "Phy command:", r);
l.Tooltip = "Command used to launch phy (e.g. 'phy', 'conda run -n phy2 phy', or a full phy path).";
obj.PhyCmdField = uieditfield(cg, "text", "Placeholder", "phy (or 'conda run -n phy2 phy')");
obj.PhyCmdField.Layout.Row = r; obj.PhyCmdField.Layout.Column = [2 5];

% --- Preprocessing (SpikeInterface) ---
r = r + 1;
sep(cg, "Preprocessing (SpikeInterface) - KS4 still filters + whitens internally", r);

r = r + 1;
obj.SIDetectBadCheckBox = uicheckbox(cg, "Text", "Detect bad channels (auto)", ...
    "Value", true, "Tooltip", ...
    ["Run spikeinterface.detect_bad_channels and drop dead/noisy channels " ...
     "before sorting. Detected channels are unioned with the manual Exclude list."], ...
    "ValueChangedFcn", @(~,~) obj.onSIControlsChanged());
obj.SIDetectBadCheckBox.Layout.Row = r; obj.SIDetectBadCheckBox.Layout.Column = [1 2];
l = lab(cg, "Action:", r); l.Layout.Column = 3;





obj.SIBadActionDropDown = uidropdown(cg);
obj.SIBadActionDropDown.Items = ["remove", "interpolate"];
obj.SIBadActionDropDown.Value = "remove";
set(obj.SIBadActionDropDown, "Tooltip", ...
    "Remove bad channels from the probe, or interpolate them from neighbours.", ...
    "ValueChangedFcn", @(~,~) obj.onSIControlsChanged());
obj.SIBadActionDropDown.Layout.Row = r; obj.SIBadActionDropDown.Layout.Column = 4;

r = r + 1;
lab(cg, "Detector method:", r);
obj.SIBadMethodDropDown = uidropdown(cg);
obj.SIBadMethodDropDown.Items = ["coherence+psd", "std", "mad", "neighborhood_r2"];
obj.SIBadMethodDropDown.Value = "coherence+psd";
obj.SIBadMethodDropDown.Tooltip = "spikeinterface.detect_bad_channels method.";
obj.SIBadMethodDropDown.ValueChangedFcn = @(~,~) obj.onSIControlsChanged();
obj.SIBadMethodDropDown.Layout.Row = r; obj.SIBadMethodDropDown.Layout.Column = [2 4];

r = r + 1;
% Reuse ArtifactConfig.Enabled: this master toggle gates AUTO artifact
% detection; manual (Visualize-tab) periods are always silenced. Tune the
% detector on the Artifacts tab.
obj.ArtEnableCheckBox = uicheckbox(cg, "Text", ...
    "Silence artifacts (manual always; auto-detect when ticked)", ...
    "Value", true, "Tooltip", ...
    ["Zero flagged spans in the SpikeInterface recording (silence_periods). " ...
     "Manual periods marked on the Visualize tab are always silenced; ticking " ...
     "this also runs the Artifacts-tab detector over the recording."], ...
    "ValueChangedFcn", @(~,~) obj.onArtifactControlsChanged());
obj.ArtEnableCheckBox.Layout.Row = r; obj.ArtEnableCheckBox.Layout.Column = [1 5];

r = r + 1;
obj.SICommonRefCheckBox = uicheckbox(cg, "Text", "Common reference (CMR/CAR)", ...
    "Value", false, "Tooltip", ...
    "Apply spikeinterface.common_reference across channels before sorting.", ...
    "ValueChangedFcn", @(~,~) obj.onSIControlsChanged());
obj.SICommonRefCheckBox.Layout.Row = r; obj.SICommonRefCheckBox.Layout.Column = [1 2];
l = lab(cg, "Operator:", r); l.Layout.Column = 3;
obj.SIRefOperatorDropDown = uidropdown(cg);
obj.SIRefOperatorDropDown.Items = ["median", "average"];
obj.SIRefOperatorDropDown.Value = "median";
obj.SIRefOperatorDropDown.ValueChangedFcn = @(~,~) obj.onSIControlsChanged();
obj.SIRefOperatorDropDown.Layout.Row = r; obj.SIRefOperatorDropDown.Layout.Column = 4;

r = r + 1;
obj.SIFilterCheckBox = uicheckbox(cg, "Text", ...
    "Bandpass filter in SpikeInterface (off = let KS4 filter)", ...
    "Value", false, "Tooltip", ...
    ["Filter in SpikeInterface instead of relying on KS4's internal high-pass. " ...
     "Off by default to avoid double-filtering."], ...
    "ValueChangedFcn", @(~,~) obj.onSIControlsChanged());
obj.SIFilterCheckBox.Layout.Row = r; obj.SIFilterCheckBox.Layout.Column = [1 5];

r = r + 1;
lab(cg, "Filter min (Hz):", r);
obj.SIFilterMinField = uieditfield(cg, "numeric", "Value", 300, "Limits", [0 Inf]);
obj.SIFilterMinField.Layout.Row = r; obj.SIFilterMinField.Layout.Column = 2;
l = lab(cg, "Filter max (Hz):", r); l.Layout.Column = 3;
obj.SIFilterMaxField = uieditfield(cg, "numeric", "Value", 6000, "Limits", [0 Inf]);
obj.SIFilterMaxField.Layout.Row = r; obj.SIFilterMaxField.Layout.Column = 4;

% --- Kilosort4 parameters (from kilosortParamSpec), two per row ---
obj.ParamControls = struct();
for gi = 1:numel(groups)
    gp = spec(strcmp({spec.group}, groups{gi}));
    r = r + 1;
    sep(cg, groups{gi}, r);
    for k = 1:numel(gp)
        s = gp(k);
        if mod(k, 2) == 1
            r = r + 1;
            lcol = 1;
        else
            lcol = 3;
        end
        l = lab(cg, [s.label ':'], r);
        l.Layout.Column = lcol;
        l.Tooltip = s.tip;
        ctrl = makeControl(cg, s);
        ctrl.Layout.Row = r;
        ctrl.Layout.Column = lcol + 1;
        obj.ParamControls.(s.name) = ctrl;
    end
end

% --- free-form extra settings ---
r = r + 1;
l = uilabel(cg, "Text", "Extra settings (JSON):", "VerticalAlignment", "top");
l.Layout.Row = r; l.Layout.Column = 1;
l.Tooltip = "Any additional KS4 settings as JSON; these override the fields above.";
obj.ExtraSettingsArea = uitextarea(cg, "Value", {'{'; '}'}, ...
    "Placeholder", '{ "x_centers": 2 }');
obj.ExtraSettingsArea.Layout.Row = r; obj.ExtraSettingsArea.Layout.Column = [2 5];
cg.RowHeight{r} = 70;

% --- config save/load ---
r = r + 1;
obj.SaveConfigButton = uibutton(cg, "Text", "Save config...", ...
    "ButtonPushedFcn", @(~,~) obj.onSaveConfig());
obj.SaveConfigButton.Layout.Row = r; obj.SaveConfigButton.Layout.Column = 2;
obj.LoadConfigButton = uibutton(cg, "Text", "Load config...", ...
    "ButtonPushedFcn", @(~,~) obj.onLoadConfig());
obj.LoadConfigButton.Layout.Row = r; obj.LoadConfigButton.Layout.Column = 4;

r = r + 1;
obj.KSDocsLink = uihyperlink(cg, "Text", "Kilosort4 parameter docs", ...
    "URL", "https://kilosort.readthedocs.io/en/latest/parameters.html");
obj.KSDocsLink.Layout.Row = r; obj.KSDocsLink.Layout.Column = [2 3];

obj.SIDocsLink = uihyperlink(cg, "Text", "SpikeInterface docs", ...
    "URL", "https://spikeinterface.readthedocs.io/en/stable/");
obj.SIDocsLink.Layout.Row = r; obj.SIDocsLink.Layout.Column = [4 5];

% =================== right column: batch run + log ===================
runPanel = uipanel(g, "Title", "Batch processing");
runPanel.Layout.Column = 2;
rg = uigridlayout(runPanel, [6 3]);
rg.RowHeight   = {'fit', 'fit', 'fit', 'fit', 'fit', '1x'};
rg.ColumnWidth = {'fit', 'fit', '1x'};

lab(rg, "Execution:", 1);
obj.ExecModeDropDown = uidropdown(rg);
obj.ExecModeDropDown.Items = {'Non-blocking (background)', 'Blocking (wait)'};
obj.ExecModeDropDown.ItemsData = {false, true};
obj.ExecModeDropDown.Value = false;
obj.ExecModeDropDown.Layout.Row = 1; obj.ExecModeDropDown.Layout.Column = [2 3];

obj.DryRunCheckBox = uicheckbox(rg, "Text", ...
    "Dry run (write si_config.json + run_si_ks4.py, do not spawn)");
obj.DryRunCheckBox.Layout.Row = 2; obj.DryRunCheckBox.Layout.Column = [1 3];

obj.RunKilosortButton = uibutton(rg, "Text", "Run Kilosort4 (selected)", ...
    "ButtonPushedFcn", @(~,~) obj.onRunBatch("kilosort"), ...
    "Tooltip", "Convert with SpikeInterface and run Kilosort4 on the selected datasets.");
obj.RunKilosortButton.Layout.Row = 3; obj.RunKilosortButton.Layout.Column = [1 2];

% "Open in phy" lives on the Datasets tab (it acts on the selected row).

obj.KSProgressLabel = uilabel(rg, "Text", "Idle. Tick datasets in the Datasets tab (or none = all).", ...
    "FontColor", [0.4 0.4 0.4]);
obj.KSProgressLabel.Layout.Row = 5; obj.KSProgressLabel.Layout.Column = [1 3];

obj.KSLogArea = uitextarea(rg, "Editable", "off");
obj.KSLogArea.Layout.Row = 6; obj.KSLogArea.Layout.Column = [1 3];

obj.syncSIEnableStates();
end


function ctrl = makeControl(parent, s)
%makeControl  Create the control for one parameter spec entry (no layout set).
switch s.kind
    case 'bool'
        ctrl = uicheckbox(parent, "Text", "", "Value", logical(s.default));
    case 'int'
        ctrl = uieditfield(parent, "numeric", "Value", s.default, ...
            "RoundFractionalValues", "on");
    case 'float'
        ctrl = uieditfield(parent, "numeric", "Value", s.default);
    otherwise   % 'floatinf', 'nullable', 'vector' -> free text
        ctrl = uieditfield(parent, "text", "Value", char(string(s.default)));
        if strcmp(s.kind, 'nullable')
            ctrl.Placeholder = "blank = auto/none";
        elseif strcmp(s.kind, 'floatinf')
            ctrl.Placeholder = "Infinity = off";
        end
end
ctrl.Tooltip = s.tip;
end


function l = lab(parent, txt, row)
%lab  Create a column-1 label at the given grid row.
l = uilabel(parent, "Text", txt);
l.Layout.Row = row;
l.Layout.Column = 1;
end


function sep(parent, txt, row)
%sep  Create a bold full-width section header at the given grid row.
l = uilabel(parent, "Text", txt, "FontWeight", "bold");
l.Layout.Row = row;
l.Layout.Column = [1 5];
end
