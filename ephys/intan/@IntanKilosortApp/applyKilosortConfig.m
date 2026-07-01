function applyKilosortConfig(obj, cfg)
%applyKilosortConfig  Push a config struct (from gatherKilosortConfig) into the UI.
%   Missing fields are left at their current value, so partial configs are safe.

setIf(@() set2(obj.PythonExeField, 'Value', cfg, 'PythonExe', @char));
setIf(@() set2(obj.CondaEnvField, 'Value', cfg, 'CondaEnv', @char));
setIf(@() set2(obj.OutputRootField, 'Value', cfg, 'OutputRoot', @char));

% SpikeInterface preprocessing config.
if isfield(cfg, 'SIConfig')
    setIf(@() obj.applySIConfig(cfg.SIConfig));
end

% KS4 parameter controls.
spec = obj.kilosortParamSpec();
if isfield(cfg, 'Params') && isstruct(cfg.Params)
    for i = 1:numel(spec)
        s = spec(i);
        if isfield(cfg.Params, s.name)
            setIf(@() applyParam(obj.ParamControls.(s.name), s, cfg.Params.(s.name)));
        end
    end
end

% Backward compat: older configs stored a few KS4 fields at the top level.
legacy = {'nblocks', 'Th_universal', 'Th_learned', 'batch_size'};
for k = 1:numel(legacy)
    name = legacy{k};
    if isfield(cfg, name) && isfield(obj.ParamControls, name)
        si = find(strcmp({spec.name}, name), 1);
        if ~isempty(si)
            setIf(@() applyParam(obj.ParamControls.(name), spec(si), cfg.(name)));
        end
    end
end

if isfield(cfg, 'ExtraSettings')
    obj.ExtraSettingsArea.Value = cellstr(splitlines(string(cfg.ExtraSettings)));
end
end


function applyParam(ctrl, s, value)
%applyParam  Set one control's value, coercing to the type its kind expects.
switch s.kind
    case 'bool'
        ctrl.Value = logical(value);
    case {'int', 'float'}
        ctrl.Value = double(value);
    otherwise   % text kinds
        ctrl.Value = char(string(value));
end
end


function setIf(fn)
try
    fn();
catch
end
end

function set2(h, prop, cfg, field, conv)
if isfield(cfg, field)
    h.(prop) = conv(cfg.(field));
end
end
