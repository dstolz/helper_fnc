function buildKilosortTab(obj)
%buildKilosortTab  Kilosort4 / .bin configuration, save/load, and batch run.
%   The full Kilosort4 parameter set is built from kilosortParamSpec(), laid out
%   two parameters per row in a wide, scrollable configuration panel, and stored
%   in obj.ParamControls keyed by KS4 settings name. No MATLAB-side filtering is
%   offered: the .bin is written broadband and KS4 filters internally (see the
%   highpass_cutoff parameter).

spec = obj.kilosortParamSpec();
groups = unique({spec.group}, 'stable');

% Row budget: connection (Python/Conda/Output/Phy) + ".bin writing" header +
% Scale/Dtype row + blank-artifacts checkbox + per group [header + ceil(nParams/2) rows] + JSON + buttons.
nRows = 7;
for gi = 1:numel(groups)
    np = sum(strcmp({spec.group}, groups{gi}));
    nRows = nRows + 1 + ceil(np / 2);
end
nRows = nRows + 2;

g = uigridlayout(obj.TabKilosort, [1 2]);
g.ColumnWidth = {720, '1x'};
g.Padding     = [10 10 10 10];

% =================== left column: configuration ===================
% Fixed pixel row heights + a scrollable grid: with 'fit' rows the grid sizes
% itself to the panel and clips; fixed heights let the content overflow so the
% scrollbar appears. Columns: labelA | controlA | labelB | controlB | browse.
cfg = uipanel(g, "Title", "Configuration");
cfg.Layout.Column = 1;
cg = uigridlayout(cfg, [nRows 5]);
cg.Scrollable  = "on";
cg.RowHeight   = repmat({26}, 1, nRows);
cg.ColumnWidth = {150, '1x', 150, '1x', 30};

r = 1;
lab(cg, "Python exe:", r);
obj.PythonExeField = uieditfield(cg, "text", "Placeholder", "python.exe (or conda base python)");
obj.PythonExeField.Layout.Row = r; obj.PythonExeField.Layout.Column = [2 4];
obj.BrowsePythonButton = uibutton(cg, "Text", "...", ...
    "ButtonPushedFcn", @(~,~) obj.onBrowsePython());
obj.BrowsePythonButton.Layout.Row = r; obj.BrowsePythonButton.Layout.Column = 5;

r = r + 1;
lab(cg, "Conda env:", r);
obj.CondaEnvField = uieditfield(cg, "text", "Placeholder", "optional (uses 'conda run -n')");
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

% --- .bin writing (no filtering: KS4 filters internally) ---
r = r + 1;
sep(cg, ".bin writing (broadband, no MATLAB filtering)", r);

r = r + 1;
lab(cg, "Scale:", r);
obj.ScaleField = uieditfield(cg, "numeric", "Value", 1/0.195);
obj.ScaleField.Layout.Row = r; obj.ScaleField.Layout.Column = 2;
l = lab(cg, "Dtype:", r); l.Layout.Column = 3;
obj.DtypeDropDown = uidropdown(cg, "Items", {'int16','uint16','int32','single'}, "Value", "int16");
obj.DtypeDropDown.Layout.Row = r; obj.DtypeDropDown.Layout.Column = 4;

r = r + 1;
obj.ArtEnableCheckBox = uicheckbox(cg, "Text", "Blank artifacts in .bin", ...
    "Value", false, "Tooltip", ...
    ["When on, detected artifacts are zeroed on every channel as the Kilosort " ...
     ".bin is written for this and every scanned dataset."], ...
    "ValueChangedFcn", @(~,~) obj.onArtifactControlsChanged());
obj.ArtEnableCheckBox.Layout.Row = r; obj.ArtEnableCheckBox.Layout.Column = [1 5];

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

% =================== right column: batch run + log ===================
runPanel = uipanel(g, "Title", "Batch processing");
runPanel.Layout.Column = 2;
rg = uigridlayout(runPanel, [6 3]);
rg.RowHeight   = {'fit', 'fit', 'fit', 'fit', 'fit', '1x'};
rg.ColumnWidth = {'fit', 'fit', '1x'};

lab(rg, "Execution:", 1);
obj.ExecModeDropDown = uidropdown(rg, ...
    "Items", {'Non-blocking (background)', 'Blocking (wait)'}, ...
    "ItemsData", {false, true}, "Value", false);
obj.ExecModeDropDown.Layout.Row = 1; obj.ExecModeDropDown.Layout.Column = [2 3];

obj.DryRunCheckBox = uicheckbox(rg, "Text", "Dry run (write KS4 script + settings, do not spawn)");
obj.DryRunCheckBox.Layout.Row = 2; obj.DryRunCheckBox.Layout.Column = [1 3];

obj.WriteBinButton = uibutton(rg, "Text", "Write .bin (selected)", ...
    "ButtonPushedFcn", @(~,~) obj.onRunBatch("bin"));
obj.WriteBinButton.Layout.Row = 3; obj.WriteBinButton.Layout.Column = 1;

obj.RunKilosortButton = uibutton(rg, "Text", "Run Kilosort4 (selected)", ...
    "ButtonPushedFcn", @(~,~) obj.onRunBatch("kilosort"));
obj.RunKilosortButton.Layout.Row = 3; obj.RunKilosortButton.Layout.Column = 2;

obj.LaunchPhyButton = uibutton(rg, "Text", "Open in phy (selected)", ...
    "ButtonPushedFcn", @(~,~) obj.onLaunchPhy());
obj.LaunchPhyButton.Layout.Row = 4; obj.LaunchPhyButton.Layout.Column = [1 2];
obj.LaunchPhyButton.Tooltip = "Launch phy template-gui on the selected dataset's kilosort4 results.";

obj.KSProgressLabel = uilabel(rg, "Text", "Idle. Tick datasets in the Datasets tab (or none = all).", ...
    "FontColor", [0.4 0.4 0.4]);
obj.KSProgressLabel.Layout.Row = 5; obj.KSProgressLabel.Layout.Column = [1 3];

obj.KSLogArea = uitextarea(rg, "Editable", "off");
obj.KSLogArea.Layout.Row = 6; obj.KSLogArea.Layout.Column = [1 3];
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
