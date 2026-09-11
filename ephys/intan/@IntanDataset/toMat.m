function out = toMat(obj, opts)
%toMat  Derive LFP / MUA / SPIKE signals and save them to a .mat file.
%   OUT = ds.toMat(Name=Value) runs IntanDataset.deriveSignals and saves its
%   outputs -- variables Y, events and info, plus a small "conversion"
%   provenance struct -- to one MAT-file. The recording files are only read.
%
%   The file is written to "~<name>.partial.mat" next to the target and
%   renamed only after save() finishes without warnings and every variable is
%   confirmed present, so a failed or cancelled run never leaves a
%   complete-looking file behind. (save() reports a variable it could not
%   store, e.g. over 2 GB with -v7, as a warning and omits it; that is treated
%   as a failure here.)
%
%   Options
%   -------
%     File           target .mat path (default:
%                    <outputFolder()>/<Name>_extract.mat)
%     SignalOptions  struct of deriveSignals options (dataTypeOut, LFP_Fs,
%                    keepAmpChannels, ...); omitted fields use its defaults
%     MatVersion     "-v7.3" (default, any size) | "-v7"
%     Overwrite      false (default): error if File already exists
%     ProgressFcn    as in deriveSignals, called as ProgressFcn(nDone, nTotal,
%                    message); the save is counted as one extra step. It may
%                    throw to abort; once the file is complete, an error from
%                    the final "Done" notification is ignored.
%
%   OUT fields: file, bytes, seconds, matVersion, recordingFormat, origFs,
%   signals (struct array: name, nSamples, nChannels, class, Fs), events
%   (struct array: name, count), badChannels (the channels actually
%   interpolated, from info.importOptions).
%
%   See also IntanDataset.deriveSignals, INTAN2MATLAB.

arguments
    obj (1,1) IntanDataset
    opts.File (1,1) string = ""
    opts.SignalOptions (1,1) struct = struct()
    opts.MatVersion (1,1) string {mustBeMember(opts.MatVersion, ["-v7.3", "-v7"])} = "-v7.3"
    opts.Overwrite (1,1) logical = false
    opts.ProgressFcn = []
end

file = opts.File;
if file == ""
    file = string(fullfile(obj.outputFolder(), obj.Name + "_extract.mat"));
end
if isfile(file) && ~opts.Overwrite
    error('IntanDataset:toMat:Exists', ...
        '%s already exists (pass Overwrite=true to replace it).', file);
end
outDir = fileparts(file);
if strlength(outDir) > 0 && ~isfolder(outDir)
    [ok, msg] = mkdir(outDir);
    if ~ok
        error('IntanDataset:toMat:MkdirFailed', 'Could not create %s: %s', outDir, msg);
    end
end
if isfield(opts.SignalOptions, 'ProgressFcn')
    error('IntanDataset:toMat:ProgressFcn', ...
        'Pass ProgressFcn to toMat itself, not inside SignalOptions.');
end

% Forward progress with one extra step for the save: deriveSignals' final
% (n, n, "Done") becomes (n, n+1, "Saving ...").
steps = containers.Map({'total'}, {NaN});
cb = [];
if ~isempty(opts.ProgressFcn)
    cb = @(d, n, m) forwardProgress(opts.ProgressFcn, steps, d, n, m, file);
end

t0 = tic;
args = namedargs2cell(opts.SignalOptions);
[Y, ev, info] = obj.deriveSignals(args{:}, 'ProgressFcn', cb);

S = struct();
S.Y = Y;
S.events = ev;
S.info = info;
S.conversion = struct( ...
    'tool',            "IntanDataset.toMat (deriveSignals / intan2matlab)", ...
    'created',         string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
    'dataset',         obj.Name, ...
    'sourceFolder',    obj.Folder, ...
    'recordingFormat', obj.RecordingFormat, ...
    'matFileVersion',  opts.MatVersion, ...
    'matlabVersion',   string(version));
saveAtomically(file, S, opts.MatVersion);
clear S

d = dir(file);
out = struct();
out.file            = file;
out.bytes           = d.bytes;
out.seconds         = toc(t0);
out.matVersion      = opts.MatVersion;
out.recordingFormat = obj.RecordingFormat;
out.origFs          = info.origFs;
out.signals         = signalSummary(Y, info);
out.events          = eventSummary(ev);
out.badChannels     = info.importOptions.badChannels;

if ~isempty(obj.Manifest) && isa(obj.Manifest, 'Manifest')
    obj.Manifest.add("toMat", "Wrote derived signals .mat", ...
        struct('file', file, 'dataTypeOut', info.importOptions.dataTypeOut, ...
        'bytes', out.bytes));
end

if ~isempty(opts.ProgressFcn)
    try
        n1 = steps('total');
        opts.ProgressFcn(n1, n1, "Done");
    catch
        % The file is already complete; a cancel raised here must not turn a
        % finished conversion into a reported failure.
    end
end
end


function forwardProgress(fcn, steps, d, n, m, file)
%forwardProgress  Relay deriveSignals progress with one extra (save) step.
steps('total') = n + 1;   % containers.Map is a handle: visible to toMat
if d >= n
    fcn(n, n + 1, "Saving " + file);
else
    fcn(d, n + 1, m);
end
end


function saveAtomically(outFile, S, matVersion)
%saveAtomically  save() the fields of S to a temp file, verify, then rename.
[outDir, base] = fileparts(outFile);
tmp = fullfile(outDir, "~" + base + ".partial.mat");
if isfile(tmp); delete(tmp); end
lastwarn('');
try
    save(tmp, '-struct', 'S', char(matVersion));
    [wmsg, wid] = lastwarn;
    if ~isempty(wmsg)
        error('IntanDataset:toMat:SaveWarning', ...
            'save() raised a warning, so the output was discarded (%s): %s', wid, wmsg);
    end
    w = whos('-file', tmp);
    missing = setdiff(fieldnames(S), {w.name});
    if ~isempty(missing)
        error('IntanDataset:toMat:SaveIncomplete', ...
            'Saved file is missing variable(s): %s', strjoin(missing, ', '));
    end
    [ok, msg] = movefile(tmp, outFile, 'f');
    if ~ok
        error('IntanDataset:toMat:MoveFailed', ...
            'Could not rename %s to %s: %s', tmp, outFile, msg);
    end
catch ME
    if isfile(tmp); delete(tmp); end
    rethrow(ME);
end
end


function s = signalSummary(Y, info)
%signalSummary  Size / class / rate of each derived signal that was requested.
s = struct('name', {}, 'nSamples', {}, 'nChannels', {}, 'class', {}, 'Fs', {});
for f = ["LFP" "MUA" "SPIKE"]
    if isfield(info, f)   % info.<type> exists only for requested types
        X = Y.(f);
        s(end+1) = struct('name', f, 'nSamples', size(X, 1), ...
            'nChannels', size(X, 2), 'class', string(class(X)), ...
            'Fs', info.(f).Fs); %#ok<AGROW>
    end
end
end


function s = eventSummary(events)
%eventSummary  Number of [on off] intervals per digital-input line.
fn = fieldnames(events);
s = struct('name', {}, 'count', {});
for k = 1:numel(fn)
    s(end+1) = struct('name', string(fn{k}), 'count', size(events.(fn{k}), 1)); %#ok<AGROW>
end
end
