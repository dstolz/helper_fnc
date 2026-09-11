function onRunConvert(obj)
%onRunConvert  Batch INTAN2MATLAB over the selected datasets; save one .mat each.
%   For each dataset ticked on the Datasets tab (none ticked = all), calls
%   INTAN2MATLAB on the dataset folder with the Convert-tab options and saves
%   its outputs Y, events and info -- plus a small "conversion" provenance
%   struct -- to <Output folder>/<Name><Suffix>.mat. A blank Output folder
%   writes next to the raw data (the dataset folder). The *.rhd files are
%   only read, never modified.
%
%   Safeguards
%   ----------
%     * Existing .mat files are skipped unless "Overwrite" is ticked.
%     * Datasets not in the traditional *.rhd layout are skipped with the
%       reason logged (intan2matlab reads only *.rhd files with embedded data).
%     * Two datasets that would write the same file stop the run before it
%       starts.
%     * Each file is written to "~<name>.partial.mat" and renamed to its final
%       name only after save() finishes without warnings and every variable is
%       confirmed present, so a failed or cancelled run never leaves a
%       complete-looking file behind.
%
%   Progress (overall + per-step bars, status table, log) is driven by
%   intan2matlab's ProgressFcn; Cancel stops at the next step boundary
%   (between files / processing stages).
%
%   See also INTAN2MATLAB, buildConvertTab, gatherConvertConfig.

if obj.ConvRunning; return; end
if isempty(obj.Project) || obj.Project.NumDatasets == 0
    uialert(obj.Fig, "Scan a parent directory first (Datasets tab).", "Convert");
    return
end

cfg = obj.gatherConvertConfig();
obj.savePreferences();

% --- validate options before touching anything ---
try
    args = intan2matlabArgs(cfg);
    validateSuffix(cfg.Suffix);
catch ME
    uialert(obj.Fig, ME.message, "Convert: invalid options");
    return
end

T = obj.convertTargets(cfg);
n = height(T);
if n == 0
    uialert(obj.Fig, "No datasets selected.", "Convert");
    return
end

% Two datasets must never write the same file (case-insensitive: Windows).
key = lower(T.OutputFile);
[~, first] = unique(key, 'stable');
dupKeys = key(setdiff(1:n, first));
if ~isempty(dupKeys)
    names = T.Dataset(ismember(key, dupKeys));
    uialert(obj.Fig, "These datasets would write the same output file: " + ...
        strjoin(names, ", ") + ". Leave the output folder blank (save next " + ...
        "to each dataset) or convert them separately.", "Convert");
    return
end

% A user-specified output folder is created if it does not exist yet.
if cfg.OutputDir ~= "" && ~isfolder(cfg.OutputDir)
    [ok, msg] = mkdir(cfg.OutputDir);
    if ~ok
        uialert(obj.Fig, "Could not create output folder: " + string(msg), "Convert");
        return
    end
    obj.convLog("Created output folder %s", cfg.OutputDir);
end

% --- run state ---
obj.ConvRunning = true;
obj.ConvCancelRequested = false;
obj.ConvRunButton.Enable = "off";
obj.ConvCancelButton.Enable = "on";
cleanup = onCleanup(@() finishRun(obj));

obj.ConvTargetsTable.Data = T(:, {'Dataset', 'Format', 'OutputFile', 'Status'});
touched = false(1, n);   % rows whose status this run has set

obj.convLog("=== intan2matlab batch: %d dataset(s) ===", n);
obj.convLog("Options: %s", formatArgs(args));
obj.convLog("Saving with %s; overwrite existing = %s", cfg.MatVersion, string(cfg.Overwrite));
obj.setStatus(sprintf("Convert: running intan2matlab on %d dataset(s)...", n), "");

nOK = 0; nSkip = 0; nFail = 0; cancelled = false;
for j = 1:n
    if obj.ConvCancelRequested
        cancelled = true;
        break
    end
    d = obj.Project.Datasets(T.DatasetIdx(j));
    outFile = T.OutputFile(j);
    showProgress(obj, j, n, 0, 1, d.Name + ": starting");
    obj.convLog("[%d/%d] %s  (%s)", j, n, d.Name, d.Folder);
    touched(j) = true;

    if d.RecordingFormat ~= "traditional"
        nSkip = nSkip + 1;
        showProgress(obj, j, n, 1, 1, d.Name + ": skipped");
        setRowStatus(obj, j, "skipped: " + d.RecordingFormat + " layout");
        obj.convLog("    SKIPPED: folder is in the %s layout; intan2matlab reads only *.rhd files with embedded data.", ...
            d.RecordingFormat);
        continue
    end
    if isfile(outFile) && ~cfg.Overwrite
        nSkip = nSkip + 1;
        showProgress(obj, j, n, 1, 1, d.Name + ": skipped");
        setRowStatus(obj, j, "skipped: output exists");
        obj.convLog("    SKIPPED: %s already exists (tick Overwrite to replace it).", outFile);
        continue
    end

    setRowStatus(obj, j, "running");
    t0 = tic;
    try
        cb = @(done, total, msg) onProgress(obj, j, n, d.Name, done, total, msg);
        [Y, events, info] = intan2matlab(d.Folder, args{:}, 'ProgressFcn', cb);

        obj.ConvStepLabel.Text = char(d.Name + ": saving " + outFile);
        drawnow;

        S = struct();
        S.Y = Y;
        S.events = events;
        S.info = info;
        S.conversion = struct( ...
            'tool',          "IntanKilosortApp Convert tab -> intan2matlab", ...
            'created',       string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
            'dataset',       d.Name, ...
            'sourceFolder',  d.Folder, ...
            'matFileVersion', cfg.MatVersion, ...
            'matlabVersion', string(version));
        saveAtomically(outFile, S, cfg.MatVersion);
        clear S

        logSummary(obj, Y, events, info, cfg);
        fi = dir(outFile);
        obj.convLog("    saved %s (%.1f MB) in %.1f s", outFile, fi.bytes / 2^20, toc(t0));
        setRowStatus(obj, j, "done");
        nOK = nOK + 1;
    catch ME
        if strcmp(ME.identifier, 'IntanKilosortApp:ConvertCancelled')
            cancelled = true;
            setRowStatus(obj, j, "cancelled (nothing written)");
            obj.convLog("    CANCELLED during %s; no output written for it.", d.Name);
            break
        end
        nFail = nFail + 1;
        setRowStatus(obj, j, "FAILED");
        obj.convLog("    ERROR: %s", ME.message);
    end
    clear Y events info
end

if ~isvalid(obj.Fig); return; end

if cancelled
    for r = find(~touched)
        setRowStatus(obj, r, "not run (cancelled)");
    end
else
    obj.setConvertBar(obj.ConvOverallBar, 1);
    obj.ConvOverallText.Text = sprintf('%d/%d datasets', n, n);
end

summary = sprintf("%d converted, %d skipped, %d failed", nOK, nSkip, nFail);
if cancelled; summary = summary + ", cancelled by user"; end
obj.convLog("=== finished: %s ===", summary);
obj.ConvStepLabel.Text = char("Finished: " + summary + ".");
obj.setStatus("Convert: " + summary + ".", "");
end


%% ---- progress ---------------------------------------------------------

function onProgress(obj, j, n, name, done, total, msg)
%onProgress  intan2matlab ProgressFcn: update the tab, honor Cancel.
%   Per-file read steps update the bars only (they can number in the
%   thousands); the first read and every processing stage are also logged.
if ~isvalid(obj) || isempty(obj.Fig) || ~isvalid(obj.Fig)
    error('IntanKilosortApp:ConvertCancelled', 'The app was closed.');
end
msg = string(msg);
showProgress(obj, j, n, done, total, name + ": " + msg);
if done == 0 || ~startsWith(msg, "Reading file")
    obj.convLog("    %s", msg);
end
drawnow;   % render, and let a pending Cancel click run
if obj.ConvCancelRequested
    error('IntanKilosortApp:ConvertCancelled', 'Cancelled by user.');
end
end


function showProgress(obj, j, n, done, total, msg)
%showProgress  Set both bars + texts. Overall = finished datasets plus the
%   completed fraction of steps of the current one.
if ~isvalid(obj.Fig); return; end
frac = done / max(total, 1);
obj.setConvertBar(obj.ConvOverallBar, (j - 1 + frac) / n);
obj.ConvOverallText.Text = sprintf('dataset %d/%d', j, n);
obj.setConvertBar(obj.ConvStepBar, frac);
obj.ConvStepText.Text = sprintf('step %d/%d', done, total);
obj.ConvStepLabel.Text = char(msg);
end


function setRowStatus(obj, row, status)
%setRowStatus  Update the Status cell of one targets-table row.
if isempty(obj.ConvTargetsTable) || ~isvalid(obj.ConvTargetsTable); return; end
D = obj.ConvTargetsTable.Data;
if istable(D) && row <= height(D)
    D.Status(row) = string(status);
    obj.ConvTargetsTable.Data = D;
end
end


function finishRun(obj)
%finishRun  Clear the running state and restore the buttons (onCleanup).
if ~isvalid(obj); return; end
obj.ConvRunning = false;
obj.ConvCancelRequested = false;
if ~isempty(obj.ConvRunButton) && isvalid(obj.ConvRunButton)
    obj.ConvRunButton.Enable = "on";
end
if ~isempty(obj.ConvCancelButton) && isvalid(obj.ConvCancelButton)
    obj.ConvCancelButton.Enable = "off";
end
end


%% ---- options ----------------------------------------------------------

function args = intan2matlabArgs(cfg)
%intan2matlabArgs  Convert a Convert config into intan2matlab name-value args.
%   Only the options relevant to the ticked signals are passed; everything
%   else stays at intan2matlab's defaults. Errors with a readable message on
%   invalid input.
types = ["LFP" "MUA" "SPIKE"];
sel = [cfg.LFP cfg.MUA cfg.SPIKE];
if ~any(sel)
    error('IntanKilosortApp:ConvertNoSignals', ...
        'Tick at least one signal to compute (LFP, MUA or SPIKE).');
end
args = {'dataTypeOut', types(sel), 'labelField', string(cfg.LabelField)};

keep = parseOrderedList(cfg.KeepChannels, "Keep amp channels");
if ~isempty(keep)
    args = [args, {'keepAmpChannels', keep}];
end

switch string(cfg.BadMode)
    case "manual"
        bad = parseOrderedList(cfg.BadList, "Bad channel list");
        if isempty(bad)
            error('IntanKilosortApp:ConvertBadList', ...
                'Bad channels is set to "Manual list" but the list is empty.');
        end
        args = [args, {'badChannels', bad}];
    case "auto"
        if ~cfg.LFP
            error('IntanKilosortApp:ConvertAutoBadNeedsLFP', ...
                'Automatic bad-channel detection is computed from the LFP; tick LFP.');
        end
        if ~(cfg.BadThreshold > 0)
            error('IntanKilosortApp:ConvertBadThreshold', ...
                'The |z(RMS)| threshold must be greater than 0.');
        end
        args = [args, {'badChannels', -abs(cfg.BadThreshold)}];   % negative = auto
end

remap = parseOrderedList(cfg.ChannelRemap, "Channel remap");
if ~isempty(remap)
    args = [args, {'channelRemap', remap}];
end

if cfg.LFP
    args = [args, {'LFP_Fs', cfg.LFP_Fs}];
end
if cfg.MUA
    checkBand(cfg.MUA_bpLoHi, "MUA bandpass");
    args = [args, {'MUA_Fs', cfg.MUA_Fs, 'MUA_IntegrationHz', cfg.MUA_IntegrationHz, ...
        'MUA_bpLoHi', cfg.MUA_bpLoHi}];
end
if cfg.SPIKE
    checkBand(cfg.SPIKE_bpLoHi, "SPIKE bandpass");
    if cfg.SPIKE_KeepOriginal
        spikeFs = Inf;
    else
        spikeFs = cfg.SPIKE_Fs;
    end
    args = [args, {'SPIKE_Fs', spikeFs, 'SPIKE_bpLoHi', cfg.SPIKE_bpLoHi}];
end
end


function checkBand(lohi, what)
if ~(lohi(1) < lohi(2))
    error('IntanKilosortApp:ConvertBand', ...
        '%s: low edge (%g Hz) must be below the high edge (%g Hz).', what, lohi(1), lohi(2));
end
end


function v = parseOrderedList(txt, what)
%parseOrderedList  "1-4, 8, 12-10" -> [1 2 3 4 8 12 11 10].
%   Order and repeats are preserved (unlike IntanDataset.parseChannelList,
%   which sorts) because keepAmpChannels and channelRemap are order-sensitive.
%   A descending range (12-10) counts down. Anything unparseable is an error,
%   never silently dropped.
v = double.empty(1, 0);
t = strtrim(char(string(txt)));
if isempty(t); return; end
t = regexprep(t, '\s*([-:])\s*', '$1');   % "5 - 8" -> "5-8"
toks = regexp(t, '[,;\s]+', 'split');
toks = toks(~cellfun(@isempty, toks));
for k = 1:numel(toks)
    % Two explicit patterns: MATLAB's regexp does not return tokens captured
    % inside a non-capturing (?:...) group, so an optional range suffix
    % cannot be written as one pattern without silently losing its end.
    mOne   = regexp(toks{k}, '^(\d+)$', 'tokens', 'once');
    mRange = regexp(toks{k}, '^(\d+)[-:](\d+)$', 'tokens', 'once');
    if ~isempty(mOne)
        a = str2double(mOne{1});
        b = a;
    elseif ~isempty(mRange)
        a = str2double(mRange{1});
        b = str2double(mRange{2});
    else
        error('IntanKilosortApp:ConvertIndexList', ...
            '%s: cannot parse "%s". Use 1-based integers and ranges, e.g. 1-16, 20, 32-17.', ...
            what, toks{k});
    end
    if a < 1 || b < 1
        error('IntanKilosortApp:ConvertIndexList', ...
            '%s: channel indices are 1-based ("%s").', what, toks{k});
    end
    if b >= a
        v = [v, a:b]; %#ok<AGROW>
    else
        v = [v, a:-1:b]; %#ok<AGROW>
    end
end
end


function validateSuffix(sfx)
if ~isempty(regexp(char(sfx), '[\\/:*?"<>|]', 'once'))
    error('IntanKilosortApp:ConvertBadSuffix', ...
        'File suffix contains characters not allowed in file names: \\ / : * ? " < > |');
end
end


function s = formatArgs(args)
%formatArgs  Render name-value args as "name=value, ..." for the log.
parts = strings(1, numel(args) / 2);
for k = 1:2:numel(args)
    v = args{k + 1};
    if isstring(v) || ischar(v)
        v = string(v);
        if isscalar(v)
            vs = """" + v + """";
        else
            vs = "[""" + strjoin(v, """ """) + """]";
        end
    else
        vs = string(mat2str(v));
    end
    parts((k + 1) / 2) = string(args{k}) + "=" + vs;
end
s = strjoin(parts, ", ");
end


%% ---- output -----------------------------------------------------------

function saveAtomically(outFile, S, matVersion)
%saveAtomically  save() the fields of S to a temp file, verify, then rename.
%   Any warning from save() (e.g. a variable over 2 GB with -v7, which save
%   reports as a warning and silently omits) is treated as a failure.
[outDir, base] = fileparts(outFile);
tmp = fullfile(outDir, "~" + base + ".partial.mat");
if isfile(tmp); delete(tmp); end
lastwarn('');
try
    save(tmp, '-struct', 'S', char(matVersion));
    [wmsg, wid] = lastwarn;
    if ~isempty(wmsg)
        error('IntanKilosortApp:ConvertSaveWarning', ...
            'save() raised a warning, so the output was discarded (%s): %s', wid, wmsg);
    end
    w = whos('-file', tmp);
    missing = setdiff(fieldnames(S), {w.name});
    if ~isempty(missing)
        error('IntanKilosortApp:ConvertSaveIncomplete', ...
            'Saved file is missing variable(s): %s', strjoin(missing, ', '));
    end
    [ok, msg] = movefile(tmp, outFile, 'f');
    if ~ok
        error('IntanKilosortApp:ConvertMoveFailed', ...
            'Could not rename %s to %s: %s', tmp, outFile, msg);
    end
catch ME
    if isfile(tmp); delete(tmp); end
    rethrow(ME);
end
end


function logSummary(obj, Y, events, info, cfg)
%logSummary  Log what was actually produced (sizes, rates, events, bad chans).
for f = ["LFP" "MUA" "SPIKE"]
    if isfield(info, f)   % info.<type> exists only for requested types
        X = Y.(f);
        obj.convLog("    %s: %d samples x %d channels (%s) @ %g Hz", ...
            f, size(X, 1), size(X, 2), class(X), info.(f).Fs);
    end
end

evn = fieldnames(events);
if isempty(evn)
    obj.convLog("    digital events: no dig-in lines recorded");
else
    counts = cellfun(@(k) size(events.(k), 1), evn);
    obj.convLog("    digital events: %s", ...
        strjoin(compose("%s (%d)", string(evn), counts), ", "));
end

switch string(cfg.BadMode)
    case "auto"
        bc = info.importOptions.badChannels;
        if isempty(bc)
            obj.convLog("    auto bad-channel detection flagged no channels (|z| > %g)", cfg.BadThreshold);
        else
            obj.convLog("    auto-flagged and interpolated channels (kept-channel indices, pre-remap): %s", ...
                mat2str(bc));
        end
    case "manual"
        obj.convLog("    interpolated channels (kept-channel indices, pre-remap): %s", ...
            mat2str(info.importOptions.badChannels));
end
end
