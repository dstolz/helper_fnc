function result = runKilosort(obj, opts)
%runKilosort  Write run_ks4.py + settings.json and spawn Kilosort4 via system().
%   RESULT = ds.runKilosort() writes a settings.json and a run_ks4.py next to
%   the dataset's .bin, then launches Kilosort4 by calling a configurable
%   python/conda executable through SYSTEM (not MATLAB's pyenv). The .bin must
%   already exist (call ds.toBin first) and ds.ProbeFile must point to an
%   existing Kilosort4 probe .json (this class never generates probe maps).
%
%   RESULT = ds.runKilosort(opts) with name-value options:
%     PythonExe      python executable path (default ds.PythonExe)
%     CondaEnv       conda env name; when set, uses `conda run -n <env> ...`
%     ProbeFile      KS4 probe .json (default ds.ProbeFile)
%     ExcludeChannels (1,:) double  1-based channels to drop from sorting
%                    (default ds.ExcludeChannels). Excluded channels stay in the
%                    .bin (n_chan_bin is unchanged) but are removed from the
%                    probe's chanMap/xc/yc/kcoords via a derived probe written to
%                    the results dir; the original probe .json is never modified.
%     BinFile        input .bin (default ds.BinFile)
%     ResultsDir     KS4 output dir (default OutputDir/kilosort4)
%     NChanBin       n_chan_bin override (default from .bin JSON sidecar or NumChannels)
%     Fs             sample rate override (default ds.Fs)
%     ExtraSettings  scalar struct merged into settings.json
%     DryRun         (1,1) logical  write files + build command, do NOT spawn (default false)
%     Wait           (1,1) logical  block until Kilosort4 finishes (default true).
%                    When false, the process is launched detached (background)
%                    with stdout/stderr redirected to the log, and the call
%                    returns immediately; result.status is then the launcher's
%                    status, not the Kilosort4 exit code.
%
%   Whether blocking or not, the generated run_ks4.py writes a small
%   ks4_status.json (state "done" or "error") in the results dir on completion,
%   so a caller can poll for completion of a background run.
%
%   Python/conda exe and conda env resolve most-specific-first:
%   per-call opts -> dataset property -> (manager default, when pushed down).
%
%   RESULT struct: status, command, stdoutLog, scriptPath, settingsPath,
%   resultsDir, binFile, probeFile, dryRun, wait, statusFile, background.
%
%   See also IntanDataset.toBin, INTANKILOSORTPROJECT.

arguments
    obj (1,1) IntanDataset
    opts.PythonExe (1,1) string = ""
    opts.CondaEnv (1,1) string = ""
    opts.ProbeFile (1,1) string = ""
    opts.ExcludeChannels (1,:) double = []
    opts.BinFile (1,1) string = ""
    opts.ResultsDir (1,1) string = ""
    opts.NChanBin (1,1) double = NaN
    opts.Fs (1,1) double = NaN
    opts.ExtraSettings (1,1) struct = struct()
    opts.DryRun (1,1) logical = false
    opts.Wait (1,1) logical = true
end

% Resolve config (per-call -> dataset)
pythonExe = firstNonEmpty(opts.PythonExe, obj.PythonExe);
condaEnv  = firstNonEmpty(opts.CondaEnv,  obj.CondaEnv);
probeFile = firstNonEmpty(opts.ProbeFile, obj.ProbeFile);
binFile   = firstNonEmpty(opts.BinFile,   obj.BinFile);

if pythonExe == ""
    error('IntanDataset:runKilosort:NoPython', ...
        'No python executable configured (set ds.PythonExe or pass PythonExe).');
end
if probeFile == ""
    error('IntanDataset:runKilosort:NoProbe', ...
        'No probe file configured (set ds.ProbeFile or pass ProbeFile).');
end
if ~isfile(probeFile)
    error('IntanDataset:runKilosort:ProbeMissing', 'Probe file not found: %s', probeFile);
end
if ~opts.DryRun && ~isfile(binFile)
    error('IntanDataset:runKilosort:BinMissing', ...
        '.bin not found: %s (run ds.toBin first).', binFile);
end

% Absolute paths (KS4 + system() want absolute, double-quoted paths)
binFile   = absPath(binFile);
probeFile = absPath(probeFile);

% n_chan_bin and fs: opts -> .bin JSON sidecar -> dataset metadata
[nChanBin, fsVal] = resolveBinMeta(binFile, opts, obj);

% Results dir
if opts.ResultsDir ~= ""
    resultsDir = char(opts.ResultsDir);
else
    resultsDir = fullfile(char(obj.outputFolder()), 'kilosort4');
end
resultsDir = absPath(resultsDir);
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

% Validate probe channel count against n_chan_bin (warn only)
checkProbeChannels(probeFile, nChanBin);

% Per-recording channel exclusions: drop the listed channels from the probe
% (keeping n_chan == n_chan_bin) so Kilosort4 ignores them. Write the reduced
% map to a derived probe in the results dir; never touch the original .json.
excludeCh = opts.ExcludeChannels;
if isempty(excludeCh); excludeCh = obj.ExcludeChannels; end
excludeCh = IntanDataset.parseChannelList(excludeCh);
nExcluded = 0;
if ~isempty(excludeCh)
    [probeFile, nExcluded] = writeExcludedProbe(probeFile, excludeCh, resultsDir, nChanBin);
    if nExcluded > 0
        fprintf('Excluding %d channel(s) from sorting: %s\n', ...
            nExcluded, char(IntanDataset.formatChannelList(excludeCh)));
    end
end

% Build settings.json
settings = struct();
settings.n_chan_bin = nChanBin;
settings.fs         = fsVal;
settings.data_dtype = char(obj.Dtype);
settings.filename   = strrep(binFile, '\', '/');     % forward slashes are JSON-safe
settings.probe      = strrep(probeFile, '\', '/');
settings.results_dir = strrep(resultsDir, '\', '/');
% Merge ExtraSettings
extraNames = fieldnames(opts.ExtraSettings);
for k = 1:numel(extraNames)
    settings.(extraNames{k}) = opts.ExtraSettings.(extraNames{k});
end

settingsPath = fullfile(resultsDir, 'settings.json');
scriptPath   = fullfile(resultsDir, 'run_ks4.py');
stdoutLog    = fullfile(resultsDir, 'ks4_run.log');
statusFile   = fullfile(resultsDir, 'ks4_status.json');

writeSettings(settings, settingsPath);
writeRunScript(scriptPath);

% Build command (absolute, double-quoted paths everywhere)
if condaEnv ~= ""
    command = sprintf('conda run -n %s "%s" "%s" "%s"', condaEnv, pythonExe, scriptPath, settingsPath);
else
    command = sprintf('"%s" "%s" "%s"', pythonExe, scriptPath, settingsPath);
end

result = struct();
result.status       = NaN;
result.command      = command;
result.stdoutLog    = char(stdoutLog);
result.scriptPath   = char(scriptPath);
result.settingsPath = char(settingsPath);
result.resultsDir   = resultsDir;
result.binFile      = binFile;
result.probeFile    = probeFile;
result.excludeChannels = excludeCh;
result.nExcludedChannels = nExcluded;
result.dryRun       = opts.DryRun;
result.wait         = opts.Wait;
result.statusFile   = char(statusFile);
result.background   = false;

if opts.DryRun
    fprintf('[DryRun] Wrote %s and %s\n', settingsPath, scriptPath);
    fprintf('[DryRun] Command: %s\n', command);
    return
end

% Clear any stale status file so it reflects this run only.
if isfile(statusFile)
    delete(statusFile);
end

if opts.Wait
    fprintf('Launching Kilosort4 (blocking):\n  %s\n', command);
    [status, out] = system(command);
    result.status = status;

    % Tee output to log
    fid = fopen(stdoutLog, 'w');
    if fid >= 0
        fwrite(fid, out, 'char');
        fclose(fid);
    end

    if status ~= 0
        warning('IntanDataset:runKilosort:NonZeroExit', ...
            'Kilosort4 exited with status %d. See log: %s', status, stdoutLog);
    end
else
    bgCommand = backgroundCommand(command, stdoutLog);
    fprintf('Launching Kilosort4 (background):\n  %s\n', bgCommand);
    status = system(bgCommand);   % returns immediately
    result.status = status;       % launcher status, not Kilosort4 exit code
    result.background = true;
    if status ~= 0
        warning('IntanDataset:runKilosort:LaunchFailed', ...
            'Background launch returned status %d. See log: %s', status, stdoutLog);
    end
end

if ~isempty(obj.Manifest) && isa(obj.Manifest, 'Manifest')
    obj.Manifest.add("runKilosort", "Spawned Kilosort4", ...
        struct('command', command, 'status', status, 'wait', opts.Wait, ...
        'resultsDir', resultsDir, 'binFile', binFile));
end
end


function bg = backgroundCommand(command, logFile)
%backgroundCommand  Wrap COMMAND to run detached with output redirected to LOG.
%   PYTHONUNBUFFERED=1 forces unbuffered stdout/stderr; without it, Python
%   fully block-buffers when writing to a redirected file (not a TTY), so
%   ks4_run.log stays empty until the process exits and the live tail in
%   pollKSRuns has nothing to show.
log = char(logFile);
if ispc
    % start returns immediately; cmd /s /c keeps the inner quotes verbatim.
    bg = sprintf('start "Kilosort4" /min cmd /s /c "set PYTHONUNBUFFERED=1&& %s 1> "%s" 2>&1"', command, log);
else
    bg = sprintf('PYTHONUNBUFFERED=1 %s > "%s" 2>&1 &', command, log);
end
end


%% ---- local helpers ----------------------------------------------------

function v = firstNonEmpty(varargin)
v = "";
for k = 1:nargin
    s = string(varargin{k});
    if s ~= ""
        v = s;
        return
    end
end
end


function p = absPath(p)
p = char(p);
[d, n, e] = fileparts(p);
if isempty(d) || ~isAbsolute(d)
    p = fullfile(pwd, p);
end
% Normalize via Java file to resolve any . / .. components
try
    p = char(java.io.File(p).getCanonicalPath());
catch
    p = char(p);
end
[~] = n; [~] = e;  %#ok<NASGU>
end


function tf = isAbsolute(d)
d = char(d);
tf = ~isempty(regexp(d, '^([A-Za-z]:[\\/]|[\\/]{2}|[\\/])', 'once'));
end


function [nChanBin, fsVal] = resolveBinMeta(binFile, opts, obj)
nChanBin = opts.NChanBin;
fsVal    = opts.Fs;
% Try the .bin JSON sidecar
[d, n] = fileparts(binFile);
sidecar = fullfile(d, [n '.json']);
if (isnan(nChanBin) || isnan(fsVal)) && isfile(sidecar)
    try
        meta = jsondecode(fileread(sidecar));
        if isnan(nChanBin) && isfield(meta, 'n_chan_bin'); nChanBin = meta.n_chan_bin; end
        if isnan(fsVal)    && isfield(meta, 'fs');         fsVal    = meta.fs;         end
    catch
    end
end
if isnan(nChanBin); nChanBin = obj.NumChannels; end
if isnan(fsVal);    fsVal    = obj.Fs;          end
if isnan(nChanBin) || isnan(fsVal)
    error('IntanDataset:runKilosort:UnknownBinMeta', ...
        'Could not determine n_chan_bin/fs; pass NChanBin/Fs or write the .bin sidecar.');
end
end


function checkProbeChannels(probeFile, nChanBin)
try
    probe = jsondecode(fileread(probeFile));
catch ME
    error('IntanDataset:runKilosort:BadProbeJson', ...
        'Probe file is not valid JSON: %s (%s)', probeFile, ME.message);
end
nProbe = NaN;
% n_chan, but never fewer than the mapped sites: an n_chan written from a
% 0-based map's max index is one short of numel(chanMap); prefer the map.
nMap = NaN;
if isfield(probe, 'chanMap'); nMap = numel(probe.chanMap); end
if isfield(probe, 'n_chan');  nProbe = double(probe.n_chan); end
if ~isnan(nMap); nProbe = max([nProbe, nMap], [], 'omitnan'); end
if ~isnan(nProbe) && nProbe ~= nChanBin
    warning('IntanDataset:runKilosort:ProbeChannelMismatch', ...
        'Probe channel count (%d) differs from n_chan_bin (%d).', nProbe, nChanBin);
end
end


function [derivedFile, nExcluded] = writeExcludedProbe(probeFile, excludeCh, resultsDir, nChanBin)
%writeExcludedProbe  Write a probe .json with excludeCh removed from the map.
%   excludeCh are 1-based .bin channels; a probe site is kept unless its
%   chanMap value + 1 is in excludeCh. n_chan is preserved so it still matches
%   n_chan_bin. Returns the original file unchanged when nothing is dropped.
derivedFile = string(probeFile);
nExcluded   = 0;
try
    probe = jsondecode(fileread(probeFile));
catch ME
    error('IntanDataset:runKilosort:BadProbeJson', ...
        'Probe file is not valid JSON: %s (%s)', probeFile, ME.message);
end

if isfield(probe, 'chanMap') && ~isempty(probe.chanMap)
    cm = double(probe.chanMap(:));
elseif isfield(probe, 'xc')
    cm = (0:numel(probe.xc)-1).';   % KS4 defaults chanMap to 0..n-1
else
    warning('IntanDataset:runKilosort:NoChanMap', ...
        'Probe has no chanMap/xc; cannot exclude channels. Using full probe.');
    return
end

keep = ~ismember(cm + 1, excludeCh(:));
nExcluded = nnz(~keep);
if nExcluded == 0
    return   % nothing in excludeCh is on this probe; keep the original
end

% Filter the per-site arrays in lockstep; leave n_chan and all other fields.
% chanMap is written explicitly as the kept original indices so the mapping to
% .bin rows stays correct even if the source probe omitted chanMap.
for f = ["xc", "yc", "kcoords"]
    if isfield(probe, f) && numel(probe.(f)) == numel(keep)
        v = probe.(f);
        probe.(f) = v(keep);
    end
end
probe.chanMap = cm(keep);

[~, pn] = fileparts(char(probeFile));
derivedFile = string(fullfile(char(resultsDir), pn + "_excluded.json"));
writeSettings(probe, derivedFile);

nKept = numel(cm) - nExcluded;
if nKept ~= nChanBin
    % Informational: KS4 sorts nKept of nChanBin channels.
    fprintf('Derived probe: %d of %d channel(s) retained for sorting.\n', ...
        nKept, nChanBin);
end
end


function writeSettings(settings, settingsPath)
try
    txt = jsonencode(settings, 'PrettyPrint', true);
catch
    txt = jsonencode(settings);
end
fid = fopen(settingsPath, 'w');
if fid < 0
    error('IntanDataset:runKilosort:SettingsWriteFailed', ...
        'Could not write %s', settingsPath);
end
fwrite(fid, txt, 'char');
fclose(fid);
end


function writeRunScript(scriptPath)
%writeRunScript  Copy the checked-in run_ks4.py driver to scriptPath.
%   The script itself lives alongside this .m file (fully self-contained: it
%   reads the settings.json path from argv[1]); we just stage a copy next to
%   each run's settings for provenance.
template = fullfile(fileparts(mfilename('fullpath')), 'run_ks4.py');
if ~isfile(template)
    error('IntanDataset:runKilosort:ScriptMissing', ...
        'Could not find %s', template);
end
copyfile(template, scriptPath, 'f');
end
