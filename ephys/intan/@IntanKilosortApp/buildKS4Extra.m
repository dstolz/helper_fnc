function [extra, errMsg] = buildKS4Extra(obj)
%buildKS4Extra  Build the Kilosort4 settings struct from the tab controls.
%   [EXTRA, ERRMSG] = obj.buildKS4Extra() reads every control in
%   obj.ParamControls (per kilosortParamSpec), converts each to its JSON type,
%   and returns a scalar struct EXTRA suitable for IntanDataset.runKilosort's
%   ExtraSettings. The free-form "Extra settings (JSON)" block is merged last
%   and overrides the named fields. ERRMSG is "" on success or a message
%   describing the first parse failure.
%
%   Blank or Infinity/null entries are OMITTED so Kilosort4 falls back to its
%   own default for that parameter.

extra  = struct();
errMsg = "";
spec   = obj.kilosortParamSpec();

for i = 1:numel(spec)
    s    = spec(i);
    ctrl = obj.ParamControls.(s.name);
    v    = ctrl.Value;
    switch s.kind
        case 'bool'
            extra.(s.name) = logical(v);
        case 'int'
            extra.(s.name) = round(double(v));
        case 'float'
            extra.(s.name) = double(v);
        case 'floatinf'
            t = lower(strtrim(string(v)));
            if t == "" || t == "inf" || t == "+inf" || t == "infinity"
                continue   % omit -> KS4 default (typically +inf)
            end
            d = str2double(t);
            if isnan(d)
                errMsg = s.label + ": '" + string(v) + "' is not a number.";
                return
            end
            extra.(s.name) = d;
        case 'nullable'
            t = strtrim(string(v));
            if t == "" || lower(t) == "null" || lower(t) == "none"
                continue   % omit -> KS4 default
            end
            d = str2double(t);
            if isnan(d)
                errMsg = s.label + ": '" + string(v) + "' is not a number.";
                return
            end
            extra.(s.name) = d;
        case 'vector'
            t = strtrim(string(v));
            if t == ""
                continue
            end
            nums = sscanf(char(replace(t, ",", " ")), '%g');
            if isempty(nums) || any(isnan(nums))
                errMsg = s.label + ": '" + string(v) + "' is not a numeric list.";
                return
            end
            extra.(s.name) = nums(:).';
    end
end

% Merge the free-form JSON block last so it can override the named fields.
raw = strtrim(strjoin(string(obj.ExtraSettingsArea.Value(:)), newline));
if raw ~= "" && raw ~= "{}" && ~all(strtrim(splitlines(raw)) == "")
    try
        s = jsondecode(char(raw));
    catch ME
        errMsg = "Extra settings JSON: " + string(ME.message);
        return
    end
    if isstruct(s)
        fn = fieldnames(s);
        for k = 1:numel(fn)
            extra.(fn{k}) = s.(fn{k});
        end
    end
end
end
