function result = runSpikeInterface(obj, opts)
%runSpikeInterface  Convert + sort with SpikeInterface -> Kilosort4 via system().
%   RESULT = ds.runSpikeInterface() writes an si_config.json and a run_si_ks4.py
%   into the dataset's kilosort4 run folder, then launches a configurable
%   python/conda executable through SYSTEM (not MATLAB's pyenv). The Python side
%   reads the recording directly with SpikeInterface (read_intan), attaches the
%   probe built from ds.ProbeFile, applies the SIConfig preprocessing chain
%   (optional bandpass / common reference, automatic bad-channel detection, and
%   artifact silencing from ds.artifactIntervals), and runs Kilosort4 through
%   spikeinterface.run_sorter. No MATLAB-side .bin is written: SpikeInterface
%   owns the conversion end to end.
%
%   Unlike runKilosort (which spawns kilosort.run_kilosort on a pre-written
%   .bin), this needs no ds.toBin first. ds.ProbeFile must point to an existing
%   Kilosort4 probe .json (this class never generates probe maps).
%
%   Output layout: run_sorter writes Kilosort4's native phy files under
%   <kilosort4>/si/sorter_output (resolved by ds.kilosortResultsDir); our
%   bookkeeping (si_config.json, run_si_ks4.py, ks4_run.log, ks4_status.json)
%   lives in <kilosort4>/ so run_sorter's folder wipe never touches it.
%
%   Options (name-value)
%     PythonExe        python executable path (default ds.PythonExe)
%     CondaEnv         conda env name; when set, uses `conda run -n <env> ...`
%     ProbeFile        KS4 probe .json (default ds.ProbeFile)
%     ExcludeChannels  (1,:) double  1-based channels to drop (default ds.ExcludeChannels)
%     ResultsDir       KS4 run folder (default ds.kilosortDir())
%     Fs / NChan       overrides (default ds.Fs / ds.NumChannels)
%     SIConfig         scalar struct override (default ds.SIConfig)
%     ExtraSettings    scalar struct of Kilosort4 settings merged into ks4 block
%     ArtifactIntervals (:,2) double  seconds periods to silence (default: computed
%                      from ds.artifactIntervals(): manual + auto when enabled)
%     DryRun           (1,1) logical  write files + build command, do NOT spawn
%     Wait             (1,1) logical  block until finished (default true). When
%                      false, launched detached (background) with stdout/stderr
%                      redirected to the log; result.status is the launcher's.
%
%   Whether blocking or not, run_si_ks4.py writes ks4_status.json (state "done"
%   or "error") in the run folder on completion, so a caller (pollKSRuns) can
%   poll a background run exactly as for runKilosort.
%
%   RESULT struct: status, command, stdoutLog, scriptPath, settingsPath,
%   resultsDir, runDir, probeFile, excludeChannels, dryRun, wait, statusFile,
%   background.
%
%   See also IntanDataset.runKilosort, IntanDataset.artifactIntervals,
%   IntanDataset.kilosortResultsDir.

arguments
    obj (1,1) IntanDataset
    opts.PythonExe (1,1) string = ""
    opts.CondaEnv (1,1) string = ""
    opts.ProbeFile (1,1) string = ""
    opts.ExcludeChannels (1,:) double = []
    opts.ResultsDir (1,1) string = ""
    opts.Fs (1,1) double = NaN
    opts.NChan (1,1) double = NaN
    opts.SIConfig struct = struct()
    opts.ExtraSettings (1,1) struct = struct()
    opts.ArtifactIntervals (:,2) double = NaN(0, 2)
    opts.Files (1,:) string = string.empty(1,0)
    opts.DryRun (1,1) logical = false
    opts.Wait (1,1) logical = true
end

% Resolve config (per-call -> dataset)
pythonExe = firstNonEmpty(opts.PythonExe, obj.PythonExe);
condaEnv  = firstNonEmpty(opts.CondaEnv,  obj.CondaEnv);
probeFile = firstNonEmpty(opts.ProbeFile, obj.ProbeFile);

if pythonExe == ""
    error('IntanDataset:runSpikeInterface:NoPython', ...
        'No python executable configured (set ds.PythonExe or pass PythonExe).');
end
if probeFile == ""
    error('IntanDataset:runSpikeInterface:NoProbe', ...
        'No probe file configured (set ds.ProbeFile or pass ProbeFile).');
end
if ~isfile(probeFile)
    error('IntanDataset:runSpikeInterface:ProbeMissing', 'Probe file not found: %s', probeFile);
end

% Metadata (Fs / NumChannels / files) drives the config.
if obj.NumFiles == 0
    obj.discoverFiles();
end
if isnan(obj.Fs) || isempty(obj.PerFile)
    obj.refreshMetadata();
end

fsVal = opts.Fs;   if isnan(fsVal); fsVal = obj.Fs;          end
nChan = opts.NChan; if isnan(nChan); nChan = obj.NumChannels; end

fileList = opts.Files;
if isempty(fileList); fileList = obj.Files; end
if isempty(fileList)
    error('IntanDataset:runSpikeInterface:NoFiles', 'No Intan files in %s', obj.Folder);
end

% Run folder (bookkeeping) and the run_sorter output folder inside it.
if opts.ResultsDir ~= ""
    runDir = char(opts.ResultsDir);
else
    runDir = char(obj.kilosortDir());
end
runDir = absPath(runDir);
if ~isfolder(runDir)
    mkdir(runDir);
end
sorterDir = fullfile(runDir, 'si');   % run_sorter owns/wipes this subfolder

probeAbs = absPath(probeFile);

% Per-recording channel exclusions -> 0-based recording indices for Python.
excludeCh = opts.ExcludeChannels;
if isempty(excludeCh); excludeCh = obj.ExcludeChannels; end
excludeCh = IntanDataset.parseChannelList(excludeCh);
exclude0  = excludeCh - 1;   % 1-based .bin row -> 0-based recording index

% Preprocessing config (per-call override -> dataset).
sicfg = IntanDataset.normalizeSIConfig(obj.SIConfig);
if ~isempty(fieldnames(opts.SIConfig))
    sicfg = IntanDataset.normalizeSIConfig(opts.SIConfig);
end

% Artifact periods to silence (manual + auto when enabled), in seconds.
if isequaln(opts.ArtifactIntervals, NaN(0, 2))
    intervals = obj.artifactIntervals();
else
    intervals = opts.ArtifactIntervals;
end

% ---- Assemble the config the Python script consumes --------------------
statusFile = fullfile(runDir, 'ks4_status.json');
stdoutLog  = fullfile(runDir, 'ks4_run.log');
scriptPath = fullfile(runDir, 'run_si_ks4.py');
configPath = fullfile(runDir, 'si_config.json');

cfg = struct();
cfg.schema           = "intan-si-ks4/1";
cfg.folder           = fwdslash(obj.Folder);
cfg.recording_format = obj.RecordingFormat;
cfg.files            = cellstr(fileList(:).');
cfg.fs               = fsVal;
cfg.n_chan           = nChan;
cfg.probe            = fwdslash(probeAbs);
cfg.exclude_channels = num2cell(double(exclude0(:).'));    % JSON array (even if scalar/empty)
cfg.results_dir      = fwdslash(sorterDir);
cfg.status_path      = fwdslash(statusFile);
cfg.log_path         = fwdslash(stdoutLog);

% silence_periods.periods_s must be a cell of 1x2 rows so jsonencode emits a
% JSON array-of-pairs ([[a,b],...]); assign it (never pass a cell straight to
% struct(), which would build a struct array instead of storing the cell).
sp = struct('enabled', ~isempty(intervals));
sp.periods_s = num2cell(intervals, 2);

cfg.preprocessing = struct( ...
    'filter', struct('enabled', logical(sicfg.Filter), ...
        'freq_min', sicfg.FilterFreqMin, 'freq_max', sicfg.FilterFreqMax), ...
    'common_reference', struct('enabled', logical(sicfg.CommonReference), ...
        'operator', char(sicfg.ReferenceOperator)), ...
    'detect_bad_channels', struct('enabled', logical(sicfg.DetectBadChannels), ...
        'method', char(sicfg.BadChannelMethod), 'action', char(sicfg.BadChannelAction)), ...
    'silence_periods', sp);

cfg.ks4 = opts.ExtraSettings;

% If SpikeInterface applies the common reference, disable Kilosort4's internal
% CAR (do_CAR) to avoid referencing twice - unless the user set do_CAR
% explicitly in the Extra settings.
if logical(sicfg.CommonReference) && ~isfield(cfg.ks4, 'do_CAR')
    cfg.ks4.do_CAR = false;
end

writeJson(cfg, configPath);
writeRunScript(scriptPath);

% ---- Build command (absolute, double-quoted paths everywhere) ----------
if condaEnv ~= ""
    command = sprintf('conda run -n %s "%s" "%s" "%s"', condaEnv, pythonExe, scriptPath, configPath);
else
    command = sprintf('"%s" "%s" "%s"', pythonExe, scriptPath, configPath);
end

result = struct();
result.status       = NaN;
result.command      = command;
result.stdoutLog    = char(stdoutLog);
result.scriptPath   = char(scriptPath);
result.settingsPath = char(configPath);   % "settings" == the SI config
result.resultsDir   = char(runDir);       % run folder (bookkeeping + status)
result.runDir       = char(runDir);
result.sorterDir    = char(sorterDir);
result.probeFile    = char(probeAbs);
result.excludeChannels = excludeCh;
result.dryRun       = opts.DryRun;
result.wait         = opts.Wait;
result.statusFile   = char(statusFile);
result.background   = false;

if opts.DryRun
    fprintf('[DryRun] Wrote %s and %s\n', configPath, scriptPath);
    fprintf('[DryRun] Command: %s\n', command);
    return
end

% Clear any stale status file so it reflects this run only.
if isfile(statusFile)
    delete(statusFile);
end

if opts.Wait
    fprintf('Launching SpikeInterface + Kilosort4 (blocking):\n  %s\n', command);
    [status, out] = system(command);
    result.status = status;
    fid = fopen(stdoutLog, 'w');
    if fid >= 0
        fwrite(fid, out, 'char');
        fclose(fid);
    end
    if status ~= 0
        warning('IntanDataset:runSpikeInterface:NonZeroExit', ...
            'Pipeline exited with status %d. See log: %s', status, stdoutLog);
    end
else
    bgCommand = backgroundCommand(command, stdoutLog);
    fprintf('Launching SpikeInterface + Kilosort4 (background):\n  %s\n', bgCommand);
    status = system(bgCommand);   % returns immediately
    result.status = status;       % launcher status, not the pipeline exit code
    result.background = true;
    if status ~= 0
        warning('IntanDataset:runSpikeInterface:LaunchFailed', ...
            'Background launch returned status %d. See log: %s', status, stdoutLog);
    end
end

if ~isempty(obj.Manifest) && isa(obj.Manifest, 'Manifest')
    obj.Manifest.add("runSpikeInterface", "Spawned SpikeInterface + Kilosort4", ...
        struct('command', command, 'status', status, 'wait', opts.Wait, ...
        'resultsDir', runDir, 'probeFile', probeAbs));
end
end


%% ---- local helpers ----------------------------------------------------

function bg = backgroundCommand(command, logFile)
%backgroundCommand  Wrap COMMAND to run detached with output redirected to LOG.
%   PYTHONUNBUFFERED=1 forces unbuffered stdout/stderr; without it, Python
%   fully block-buffers when writing to a redirected file (not a TTY), so
%   ks4_run.log stays empty until the process exits and the live tail in
%   pollKSRuns has nothing to show.
log = char(logFile);
if ispc
    bg = sprintf('start "SpikeInterface-KS4" /min cmd /s /c "set PYTHONUNBUFFERED=1&& %s 1> "%s" 2>&1"', command, log);
else
    bg = sprintf('PYTHONUNBUFFERED=1 %s > "%s" 2>&1 &', command, log);
end
end


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


function s = fwdslash(p)
%fwdslash  Absolute-safe forward-slash path (JSON- and SI-friendly on Windows).
s = string(strrep(char(p), '\', '/'));
end


function p = absPath(p)
p = char(p);
d = fileparts(p);
if isempty(d) || ~isAbsolute(d)
    p = fullfile(pwd, p);
end
try
    p = char(java.io.File(p).getCanonicalPath());
catch
    p = char(p);
end
end


function tf = isAbsolute(d)
d = char(d);
tf = ~isempty(regexp(d, '^([A-Za-z]:[\\/]|[\\/]{2}|[\\/])', 'once'));
end


function writeJson(s, file)
try
    txt = jsonencode(s, 'PrettyPrint', true);
catch
    txt = jsonencode(s);
end
fid = fopen(file, 'w');
if fid < 0
    error('IntanDataset:runSpikeInterface:ConfigWriteFailed', ...
        'Could not write %s', file);
end
fwrite(fid, txt, 'char');
fclose(fid);
end


function writeRunScript(scriptPath)
%writeRunScript  Copy the checked-in run_si_ks4.py driver to scriptPath.
%   The script itself lives alongside this .m file (fully self-contained: it
%   reads the si_config.json path from argv[1]); we just stage a copy next to
%   each run's config so run_sorter's folder wipe never touches the source.
template = fullfile(fileparts(mfilename('fullpath')), 'run_si_ks4.py');
if ~isfile(template)
    error('IntanDataset:runSpikeInterface:ScriptMissing', ...
        'Could not find %s', template);
end
copyfile(template, scriptPath, 'f');
end
