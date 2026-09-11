function onRunConvert(obj)
%onRunConvert  Batch IntanDataset.toMat over the selected datasets; one .mat each.
%   For each dataset ticked on the Datasets tab (none ticked = all), calls
%   IntanDataset.toMat with the Convert-tab options: the dataset reads its
%   recording (any supported layout), derives the signals with
%   IntanDataset.deriveSignals (the intan2matlab processing) and saves Y,
%   events, info and a "conversion" provenance struct to
%   <Output folder>/<Name><Suffix>.mat. A blank Output folder writes next to
%   the raw data (the dataset folder). The recording files are only read.
%
%   Safeguards
%   ----------
%     * Existing .mat files are skipped unless "Overwrite" is ticked (toMat
%       also refuses to overwrite unless told to).
%     * Folders with no recognized Intan files are skipped, reason logged.
%     * Two datasets that would write the same file stop the run before it
%       starts.
%     * toMat writes "~<name>.partial.mat" and renames it only after save()
%       finishes without warnings and every variable is confirmed present, so
%       a failed or cancelled run never leaves a complete-looking file behind.
%
%   Progress (overall + per-step bars, status table, log) is driven by the
%   toMat/deriveSignals ProgressFcn; Cancel stops at the next step boundary
%   (between files / processing stages / before the save).
%
%   See also IntanDataset.toMat, IntanDataset.deriveSignals, buildConvertTab,
%   gatherConvertConfig.

if obj.ConvRunning; return; end
if isempty(obj.Project) || obj.Project.NumDatasets == 0
    uialert(obj.Fig, "Scan a parent directory first (Datasets tab).", "Convert");
    return
end

cfg = obj.gatherConvertConfig();
obj.savePreferences();

% --- validate options before touching anything ---
try
    sigOpts = signalOptions(cfg);
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

obj.convLog("=== Convert batch (IntanDataset.toMat): %d dataset(s) ===", n);
obj.convLog("Signal options: %s", formatOptions(sigOpts));
obj.convLog("Saving with %s; overwrite existing = %s", cfg.MatVersion, string(cfg.Overwrite));
obj.setStatus(sprintf("Convert: deriving signals for %d dataset(s)...", n), "");

nOK = 0; nSkip = 0; nFail = 0; cancelled = false;
for j = 1:n
    if obj.ConvCancelRequested
        cancelled = true;
        break
    end
    d = obj.Project.Datasets(T.DatasetIdx(j));
    outFile = T.OutputFile(j);
    showProgress(obj, j, n, 0, 1, d.Name + ": starting");
    obj.convLog("[%d/%d] %s  (%s, %s)", j, n, d.Name, d.RecordingFormat, d.Folder);
    touched(j) = true;

    if d.RecordingFormat == "unknown"
        nSkip = nSkip + 1;
        showProgress(obj, j, n, 1, 1, d.Name + ": skipped");
        setRowStatus(obj, j, "skipped: no Intan files");
        obj.convLog("    SKIPPED: no recognized Intan recording files in the folder.");
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
    try
        cb = @(done, total, msg) onProgress(obj, j, n, d.Name, done, total, msg);
        out = d.toMat(File=outFile, SignalOptions=sigOpts, ...
            MatVersion=cfg.MatVersion, Overwrite=cfg.Overwrite, ProgressFcn=cb);

        logSummary(obj, out, cfg);
        obj.convLog("    saved %s (%.1f MB) in %.1f s", out.file, out.bytes / 2^20, out.seconds);
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
%onProgress  toMat/deriveSignals ProgressFcn: update the tab, honor Cancel.
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

function s = signalOptions(cfg)
%signalOptions  Convert a Convert config into IntanDataset.deriveSignals options.
%   Returns the struct passed to toMat as SignalOptions. Only the options
%   relevant to the ticked signals are set; everything else stays at
%   deriveSignals' defaults. Errors with a readable message on invalid input.
types = ["LFP" "MUA" "SPIKE"];
sel = [cfg.LFP cfg.MUA cfg.SPIKE];
if ~any(sel)
    error('IntanKilosortApp:ConvertNoSignals', ...
        'Tick at least one signal to compute (LFP, MUA or SPIKE).');
end
s = struct();
s.dataTypeOut = types(sel);
s.labelField  = string(cfg.LabelField);

keep = parseOrderedList(cfg.KeepChannels, "Keep amp channels");
if ~isempty(keep)
    s.keepAmpChannels = keep;
end

switch string(cfg.BadMode)
    case "manual"
        bad = parseOrderedList(cfg.BadList, "Bad channel list");
        if isempty(bad)
            error('IntanKilosortApp:ConvertBadList', ...
                'Bad channels is set to "Manual list" but the list is empty.');
        end
        s.badChannels = bad;
    case "auto"
        if ~cfg.LFP
            error('IntanKilosortApp:ConvertAutoBadNeedsLFP', ...
                'Automatic bad-channel detection is computed from the LFP; tick LFP.');
        end
        if ~(cfg.BadThreshold > 0)
            error('IntanKilosortApp:ConvertBadThreshold', ...
                'The |z(RMS)| threshold must be greater than 0.');
        end
        s.badChannels = -abs(cfg.BadThreshold);   % negative = auto
end

remap = parseOrderedList(cfg.ChannelRemap, "Channel remap");
if ~isempty(remap)
    s.channelRemap = remap;
end

if cfg.LFP
    s.LFP_Fs = cfg.LFP_Fs;
    nyq = cfg.LFP_Fs / 2;
    % [0 Inf] = no band filter (deriveSignals' default); only set if ticked.
    lohi = [0 Inf];
    if cfg.LFP_HighpassOn; lohi(1) = cfg.LFP_HighpassHz; end
    if cfg.LFP_LowpassOn;  lohi(2) = cfg.LFP_LowpassHz;  end
    if cfg.LFP_HighpassOn || cfg.LFP_LowpassOn
        checkBand(lohi, "LFP high-pass / low-pass");
        if lohi(1) >= nyq || (isfinite(lohi(2)) && lohi(2) >= nyq)
            error('IntanKilosortApp:ConvertLFPNyquist', ...
                'LFP filter cut-offs must be below LFP_Fs / 2 (%g Hz).', nyq);
        end
        s.LFP_bpLoHi = lohi;
    end
    if cfg.LFP_NotchOn
        f0 = parseFreqList(cfg.LFP_NotchHz, "LFP notch");
        if isempty(f0)
            error('IntanKilosortApp:ConvertLFPNotch', ...
                'LFP notch is ticked but no frequency is given.');
        end
        bw = cfg.LFP_NotchBW;
        bad = f0(f0 - bw/2 <= 0 | f0 + bw/2 >= nyq);
        if ~isempty(bad)
            error('IntanKilosortApp:ConvertLFPNotch', ...
                ['LFP notch %s Hz with width %g Hz does not fit inside ' ...
                 '(0, LFP_Fs / 2 = %g Hz).'], mat2str(bad), bw, nyq);
        end
        s.LFP_NotchHz = f0;
        s.LFP_NotchBW = bw;
    end
end
if cfg.MUA
    checkBand(cfg.MUA_bpLoHi, "MUA bandpass");
    s.MUA_Fs            = cfg.MUA_Fs;
    s.MUA_IntegrationHz = cfg.MUA_IntegrationHz;
    s.MUA_bpLoHi        = cfg.MUA_bpLoHi;
end
if cfg.SPIKE
    checkBand(cfg.SPIKE_bpLoHi, "SPIKE bandpass");
    if cfg.SPIKE_KeepOriginal
        s.SPIKE_Fs = Inf;
    else
        s.SPIKE_Fs = cfg.SPIKE_Fs;
    end
    s.SPIKE_bpLoHi = cfg.SPIKE_bpLoHi;
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


function v = parseFreqList(txt, what)
%parseFreqList  "60, 120 180" -> [60 120 180]. Positive finite numbers only;
%   anything unparseable is an error, never silently dropped.
v = double.empty(1, 0);
t = strtrim(char(string(txt)));
if isempty(t); return; end
toks = regexp(t, '[,;\s]+', 'split');
toks = toks(~cellfun(@isempty, toks));
v = str2double(toks);
badTok = toks(~(isfinite(v) & v > 0));
if ~isempty(badTok)
    error('IntanKilosortApp:ConvertFreqList', ...
        '%s: cannot parse "%s". Use positive frequencies in Hz, e.g. 60, 120, 180.', ...
        what, strjoin(badTok, '", "'));
end
end


function validateSuffix(sfx)
if ~isempty(regexp(char(sfx), '[\\/:*?"<>|]', 'once'))
    error('IntanKilosortApp:ConvertBadSuffix', ...
        'File suffix contains characters not allowed in file names: \\ / : * ? " < > |');
end
end


function s = formatOptions(opts)
%formatOptions  Render a name-value struct as "name=value, ..." for the log.
fn = fieldnames(opts);
parts = strings(1, numel(fn));
for k = 1:numel(fn)
    v = opts.(fn{k});
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
    parts(k) = string(fn{k}) + "=" + vs;
end
s = strjoin(parts, ", ");
end


%% ---- output -----------------------------------------------------------

function logSummary(obj, out, cfg)
%logSummary  Log what toMat actually produced (sizes, rates, events, bad chans).
for s = out.signals
    obj.convLog("    %s: %d samples x %d channels (%s) @ %g Hz", ...
        s.name, s.nSamples, s.nChannels, s.class, s.Fs);
end

if isempty(out.events)
    obj.convLog("    digital events: no dig-in lines recorded");
else
    obj.convLog("    digital events: %s", ...
        strjoin(compose("%s (%d)", [out.events.name]', [out.events.count]'), ", "));
end

switch string(cfg.BadMode)
    case "auto"
        if isempty(out.badChannels)
            obj.convLog("    auto bad-channel detection flagged no channels (|z| > %g)", cfg.BadThreshold);
        else
            obj.convLog("    auto-flagged and interpolated channels (kept-channel indices, pre-remap): %s", ...
                mat2str(out.badChannels));
        end
    case "manual"
        obj.convLog("    interpolated channels (kept-channel indices, pre-remap): %s", ...
            mat2str(out.badChannels));
end
end
