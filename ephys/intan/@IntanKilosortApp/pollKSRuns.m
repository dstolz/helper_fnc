function pollKSRuns(obj)
%pollKSRuns  Timer callback: stream each background Kilosort4 run's log and
%   check for completion.
%   Each background run redirects Kilosort4 stdout/stderr to a ks4_run.log and
%   writes a ks4_status.json (state "done" or "error") in its results dir when
%   it finishes. Every tick this tails each run's log into the status box so
%   progress is visible live, then polls the status files, logs each
%   completion, updates the progress label, and stops the monitor once every
%   tracked run has finished.

if isempty(obj.KSRuns)
    obj.stopKSMonitor();
    return
end

pending = 0;
for i = 1:numel(obj.KSRuns)
    if obj.KSRuns(i).done
        continue
    end

    % Stream any new log output for this run into the status box.
    obj.KSRuns(i).logPos = tailLog(obj, obj.KSRuns(i));

    sf = char(obj.KSRuns(i).statusFile);
    if ~isfile(sf)
        pending = pending + 1;
        continue
    end

    % The file may be observed mid-write; if it does not parse yet, retry next tick.
    try
        s = jsondecode(fileread(sf));
    catch
        pending = pending + 1;
        continue
    end

    % Run finished: flush the tail of its log before reporting status.
    obj.KSRuns(i).logPos = tailLog(obj, obj.KSRuns(i));

    state = "done";
    if isfield(s, 'state'); state = string(s.state); end
    obj.KSRuns(i).done = true;
    if state == "done"
        obj.log("[done] %s - Kilosort4 complete (%s)", obj.KSRuns(i).Name, ...
            obj.KSRuns(i).resultsDir);
    else
        msg = "";
        if isfield(s, 'message'); msg = string(s.message); end
        obj.log("[error] %s - Kilosort4 failed: %s", obj.KSRuns(i).Name, msg);
    end
end

nTot  = numel(obj.KSRuns);
nDone = sum([obj.KSRuns.done]);
obj.KSProgressLabel.Text = sprintf("Background Kilosort4: %d/%d complete (%d running).", ...
    nDone, nTot, pending);

% Refresh the datasets table so the Bin/results columns reflect new outputs.
obj.refreshDatasetsTable();

if pending == 0
    obj.log("=== all %d background run(s) complete ===", nTot);
    obj.stopKSMonitor();
    obj.KSRuns(:) = [];   % clear the completed batch
end
end


%% ---- local helpers ----------------------------------------------------

function pos = tailLog(obj, run)
%tailLog  Append RUN's newly-written ks4_run.log lines to the status box.
%   Returns the byte offset consumed so the next tick resumes there. Only whole
%   (newline-terminated) lines are emitted; a partial trailing line is left for
%   the next tick. Carriage-return progress updates (e.g. tqdm) are collapsed to
%   their final state so they don't flood the box.
pos = run.logPos;
lf  = char(run.logFile);
if isempty(lf) || ~isfile(lf)
    return
end

fid = fopen(lf, 'r');   % MATLAB 'r' is binary: ftell == byte offset
if fid < 0
    return
end
try
    fseek(fid, pos, 'bof');
    chunk = fread(fid, inf, '*char').';
catch
    fclose(fid);
    return
end
fclose(fid);
if isempty(chunk)
    return
end

% Consume only up to the last newline; keep any partial line for next time.
nl = find(chunk == newline, 1, 'last');
if isempty(nl)
    return
end
pos   = pos + nl;
ready = chunk(1:nl);

parts = split(string(ready), newline);
parts(end) = [];   % drop the empty segment after the final newline
ts  = char(datetime('now', 'Format', 'HH:mm:ss'));
out = strings(0, 1);
for k = 1:numel(parts)
    ln = collapseCR(parts(k));
    if strlength(strip(ln)) == 0
        continue
    end
    out(end+1, 1) = sprintf("%s  %s | %s", ts, run.Name, ln); %#ok<AGROW>
end
obj.appendLogLines(out);
end


function s = collapseCR(s)
%collapseCR  Reduce a carriage-return-overwritten line to its final state.
parts = split(string(s), sprintf('\r'));
s = parts(end);
end
