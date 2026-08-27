function result = runProbeTool(obj, varargin)
%runProbeTool  Invoke probe_tool.py (probeinterface front-door) via system().
%   RESULT = obj.runProbeTool(SUBCMD, ARG1, ARG2, ...) runs the checked-in
%   probe_tool.py in the Python/conda env configured on the Kilosort tab,
%   passing SUBCMD and the remaining tokens as command-line arguments. It
%   captures stdout, raises on a PROBE_TOOL_ERROR marker or non-zero exit, and
%   returns the JSON the script prints on its last output line, jsondecoded:
%
%     list-library            -> struct mapping manufacturer -> {probe names}
%     get-library / generate  -> struct with fields out, n_contacts
%     describe                -> struct positions/shank_ids/device_channel_indices/...
%
%   probeinterface lives only in that env; the app itself stores and consumes
%   plain Kilosort4 probe .json, which is exactly what probe_tool.py writes.
%
%   Uses the same env-python-or-`conda run` dispatch as
%   IntanDataset.runSpikeInterface (env python directly when no conda env is
%   set; conda is not required to be on PATH in that case).
%
%   See also IntanKilosortApp.onDesignProbe, ProbeDesignerApp,
%   IntanDataset.runSpikeInterface.

if isempty(varargin)
    error('IntanKilosortApp:runProbeTool:NoSubcommand', ...
        'runProbeTool requires a subcommand (e.g. "list-library").');
end

pythonExe = strtrim(string(obj.PythonExeField.Value));
condaEnv  = strtrim(string(obj.CondaEnvField.Value));
if pythonExe == ""
    error('IntanKilosortApp:runProbeTool:NoPython', ...
        ['No Python executable configured. Set the Python exe on the ' ...
         'Kilosort tab (the same env used for sorting).']);
end

script = fullfile(fileparts(mfilename('fullpath')), 'probe_tool.py');
if ~isfile(script)
    error('IntanKilosortApp:runProbeTool:ScriptMissing', ...
        'probe_tool.py not found next to IntanKilosortApp: %s', script);
end

% Double-quote every token; keep native paths (cmd/python handle them as-is),
% mirroring runSpikeInterface's command assembly.
tokens = string(varargin);
quoted = strjoin(arrayfun(@(t) """" + t + """", tokens), " ");
if condaEnv ~= ""
    command = sprintf('conda run -n %s "%s" "%s" %s', condaEnv, pythonExe, script, quoted);
else
    command = sprintf('"%s" "%s" %s', pythonExe, script, quoted);
end

[status, out] = system(command);
raw = string(out);

if status ~= 0 || contains(raw, "PROBE_TOOL_ERROR")
    error('IntanKilosortApp:runProbeTool:Failed', ...
        'probe_tool.py %s failed (status %d):\n%s', tokens(1), status, strtrim(raw));
end

result = decodeLastJson(raw);
end


function value = decodeLastJson(raw)
%decodeLastJson  Return the last stdout line that parses as JSON (else the raw
%   text). Scanning from the end skips any leading warnings the env may print
%   (e.g. a first-time probeinterface library download) before the payload.
lines = splitlines(strtrim(raw));
for k = numel(lines):-1:1
    ln = strtrim(lines(k));
    if ln == ""; continue; end
    try
        value = jsondecode(ln);
        return
    catch
        % not this line; keep scanning upward
    end
end
value = raw;   % nothing decoded; hand back what we got
end
