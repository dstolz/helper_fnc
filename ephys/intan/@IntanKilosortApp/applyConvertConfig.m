function applyConvertConfig(obj, cfg)
%applyConvertConfig  Push a Convert config struct into the Convert-tab controls.
%   Tolerates partial/stale structs (e.g. saved preferences from an older
%   version): missing fields fall back to defaultConvertConfig and any value
%   a control rejects is left at the control's current value.
%
%   See also gatherConvertConfig, defaultConvertConfig.

if isempty(obj.ConvLFPCheckBox) || ~isvalid(obj.ConvLFPCheckBox); return; end

def = obj.defaultConvertConfig();
if isstruct(cfg) && isscalar(cfg)
    fn = fieldnames(def);
    for k = 1:numel(fn)
        if isfield(cfg, fn{k})
            def.(fn{k}) = cfg.(fn{k});
        end
    end
end
cfg = def;

trySet(obj.ConvOutputDirField,     'Value', char(string(cfg.OutputDir)));
trySet(obj.ConvSuffixField,        'Value', char(string(cfg.Suffix)));
setDrop(obj.ConvMatVersionDropDown, cfg.MatVersion);
trySet(obj.ConvOverwriteCheckBox,  'Value', logical(cfg.Overwrite));

trySet(obj.ConvLFPCheckBox,   'Value', logical(cfg.LFP));
trySet(obj.ConvMUACheckBox,   'Value', logical(cfg.MUA));
trySet(obj.ConvSPIKECheckBox, 'Value', logical(cfg.SPIKE));

trySet(obj.ConvLFPFsField,          'Value', cfg.LFP_Fs);
trySet(obj.ConvLFPHighpassCheckBox, 'Value', logical(cfg.LFP_HighpassOn));
trySet(obj.ConvLFPHighpassField,    'Value', cfg.LFP_HighpassHz);
trySet(obj.ConvLFPLowpassCheckBox,  'Value', logical(cfg.LFP_LowpassOn));
trySet(obj.ConvLFPLowpassField,     'Value', cfg.LFP_LowpassHz);
trySet(obj.ConvLFPNotchCheckBox,    'Value', logical(cfg.LFP_NotchOn));
trySet(obj.ConvLFPNotchField,       'Value', char(string(cfg.LFP_NotchHz)));
trySet(obj.ConvLFPNotchBWField,     'Value', cfg.LFP_NotchBW);
trySet(obj.ConvMUAFsField,          'Value', cfg.MUA_Fs);
trySet(obj.ConvMUAIntegrationField, 'Value', cfg.MUA_IntegrationHz);
if isnumeric(cfg.MUA_bpLoHi) && numel(cfg.MUA_bpLoHi) == 2
    trySet(obj.ConvMUALoField, 'Value', cfg.MUA_bpLoHi(1));
    trySet(obj.ConvMUAHiField, 'Value', cfg.MUA_bpLoHi(2));
end

trySet(obj.ConvSpikeOrigCheckBox, 'Value', logical(cfg.SPIKE_KeepOriginal));
trySet(obj.ConvSpikeFsField,      'Value', cfg.SPIKE_Fs);
if isnumeric(cfg.SPIKE_bpLoHi) && numel(cfg.SPIKE_bpLoHi) == 2
    trySet(obj.ConvSpikeLoField, 'Value', cfg.SPIKE_bpLoHi(1));
    trySet(obj.ConvSpikeHiField, 'Value', cfg.SPIKE_bpLoHi(2));
end

setDrop(obj.ConvLabelFieldDropDown, cfg.LabelField);
trySet(obj.ConvKeepChannelsField, 'Value', char(string(cfg.KeepChannels)));
setDrop(obj.ConvBadModeDropDown, cfg.BadMode);
trySet(obj.ConvBadThresholdField, 'Value', cfg.BadThreshold);
trySet(obj.ConvBadListField,      'Value', char(string(cfg.BadList)));
trySet(obj.ConvRemapField,        'Value', char(string(cfg.ChannelRemap)));

obj.syncConvertEnableStates();
end


function trySet(ctrl, prop, value)
%trySet  Set a control property, ignoring values the control rejects.
try
    ctrl.(prop) = value;
catch
end
end


function setDrop(dd, value)
%setDrop  Set a dropdown to VALUE if it is one of its ItemsData (or Items).
v = char(string(value));
if ~isempty(dd.ItemsData)
    ok = any(strcmp(v, dd.ItemsData));
else
    ok = any(strcmp(v, dd.Items));
end
if ok
    dd.Value = v;
end
end
