function loadPreferences(obj)
%loadPreferences  Restore paths, Kilosort config, and figure geometry.
%   Uses getpref under the 'IntanKilosortApp' group so choices persist between
%   sessions. Anything missing is left at its built-in default.

g = obj.PrefGroup;

% --- figure position & size ---
if ispref(g, 'FigurePosition')
    pos = getpref(g, 'FigurePosition');
    if isnumeric(pos) && numel(pos) == 4 && all(pos(3:4) > 100)
        pos = clampToScreen(pos);
        obj.Fig.Position = pos;
    end
end

% --- paths ---
if ispref(g, 'RootPath')
    p = getpref(g, 'RootPath');
    if isfolder(p); obj.RootPathField.Value = p; end
end
if ispref(g, 'ProbeFolder')
    p = getpref(g, 'ProbeFolder');
    if isfolder(p); obj.ProbeFolderField.Value = p; end
end
if obj.ProbeFolderField.Value == ""
    obj.ProbeFolderField.Value = char(obj.defaultProbeFolder());
end
if ispref(g, 'PhyCmd')
    obj.PhyCmdField.Value = char(getpref(g, 'PhyCmd'));
end
if ispref(g, 'ReviewFolder')
    p = getpref(g, 'ReviewFolder');
    if isfolder(p); obj.ReviewFolderField.Value = p; end
end

% --- visualize options ---
applyPref(g, 'VizChannels',  @(v) set(obj.VizChannelsField, 'Value', v));
applyPref(g, 'VizDuration',  @(v) set(obj.VizDurField, 'Value', v));
applyPref(g, 'VizHighpass',  @(v) set(obj.VizHighpassField, 'Value', v));
applyPref(g, 'VizLowpass',   @(v) set(obj.VizLowpassField, 'Value', v));
applyPref(g, 'VizOrder',     @(v) set(obj.VizOrderField, 'Value', v));
applyPref(g, 'VizReference', @(v) set(obj.VizRefDropDown, 'Value', char(v)));
% Backward-compat: old VizCAR boolean mapped to median subtraction.
if ~ispref(g, 'VizReference') && ispref(g, 'VizCAR')
    if logical(getpref(g, 'VizCAR')); obj.VizRefDropDown.Value = 'cmr'; end
end
applyPref(g, 'VizDetrend',   @(v) set(obj.VizDetrendCheckBox, 'Value', logical(v)));
applyPref(g, 'VizSpacing',   @(v) set(obj.VizSpacingField, 'Value', v));

% --- artifact detection options ---
applyPref(g, 'ArtMethod',       @(v) set(obj.ArtMethodDropDown, 'Value', char(v)));
applyPref(g, 'ArtThreshold',    @(v) set(obj.ArtThresholdField, 'Value', v));
applyPref(g, 'ArtRmsWindowMs',  @(v) set(obj.ArtRmsWindowField, 'Value', v));
applyPref(g, 'ArtMergeGapMs',   @(v) set(obj.ArtMergeGapField, 'Value', v));
applyPref(g, 'ArtPadMs',        @(v) set(obj.ArtPadField, 'Value', v));
applyPref(g, 'ArtMinChannels',  @(v) set(obj.ArtMinChannelsField, 'Value', v));
applyPref(g, 'ArtFilter',      @(v) set(obj.ArtFilterCheckBox, 'Value', logical(v)));
applyPref(g, 'ArtHighpass',    @(v) set(obj.ArtHighpassField, 'Value', v));
applyPref(g, 'ArtEnable',      @(v) set(obj.ArtEnableCheckBox, 'Value', logical(v)));
% Reflect restored values in the RMS/high-pass field enable state.
obj.ArtRmsWindowField.Enable = matlab.lang.OnOffSwitchState( ...
    string(obj.ArtMethodDropDown.Value) == "rms");
obj.ArtHighpassField.Enable  = matlab.lang.OnOffSwitchState( ...
    logical(obj.ArtFilterCheckBox.Value));

% --- execution mode ---
applyPref(g, 'ExecBlocking', @(v) set(obj.ExecModeDropDown, 'Value', logical(v)));

% --- kilosort config ---
if ispref(g, 'KilosortConfig')
    cfg = getpref(g, 'KilosortConfig');
    if isstruct(cfg)
        obj.applyKilosortConfig(cfg);
    end
end

% Seed the Python exe on first launch with the kilosort env python (the
% SpikeInterface + Kilosort4 environment) when nothing was restored.
if strlength(strtrim(string(obj.PythonExeField.Value))) == 0
    dp = obj.defaultPythonExe();
    if strlength(dp) > 0
        obj.PythonExeField.Value = char(dp);
    end
end
end


function applyPref(g, key, setter)
if ispref(g, key)
    try
        setter(getpref(g, key));
    catch
    end
end
end

function pos = clampToScreen(pos)
%clampToScreen  Keep the figure on-screen if the display layout changed.
try
    r = groot().ScreenSize;   % [x y w h]
    pos(1) = min(max(pos(1), 1), max(1, r(3) - 100));
    pos(2) = min(max(pos(2), 1), max(1, r(4) - 100));
    pos(3) = min(pos(3), r(3));
    pos(4) = min(pos(4), r(4));
catch
end
end
