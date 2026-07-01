function test_DatasetTracker()
%test_DatasetTracker  Verification suite for DatasetTracker discovery.
%   Builds a synthetic dataset tree on disk (empty *.rhd files, a .bin + JSON
%   sidecar, a probe .json, and two kilosort4 folders) and checks that the
%   tracker inventories each artifact type correctly. DatasetTracker inspects
%   only filenames and JSON content, so the *.rhd files need no valid header
%   and no Kilosort4 install is required.
%
%   Usage:  test_DatasetTracker
%
%   The fixtures live in a temp folder which is deleted on completion.

here = fileparts(mfilename('fullpath'));
addpath(here);   % @DatasetTracker / @IntanDataset

root = fullfile(tempdir, sprintf('DSTrack_test_%s', ...
    datestr(now, 'yyyymmdd_HHMMSSFFF'))); %#ok<TNOW1,DATST>
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));

nPass = 0; nFail = 0;
    function check(cond, msg)
        if cond
            nPass = nPass + 1;
            fprintf('  PASS: %s\n', msg);
        else
            nFail = nFail + 1;
            fprintf(2, '  FAIL: %s\n', msg);
        end
    end

% ---- Build a dataset tree -----------------------------------------------
% Two recording folders (one nested), each with *.rhd files.
recA = fullfile(root, 'rec_morning');
recB = fullfile(root, 'sub', 'rec_evening');
mkdir(recA); mkdir(recB);
touch(fullfile(recA, 'a_001.rhd'));
touch(fullfile(recA, 'a_002.rhd'));
touch(fullfile(recB, 'b_001.rhd'));

% A streamed .bin + JSON sidecar (mirrors IntanDataset.toBin output).
binFile = fullfile(recA, 'rec_morning.bin');
touch(binFile);
writeJson(struct('n_chan_bin', 64, 'fs', 30000, 'n_samples', 900000, ...
    'bin_file', binFile, 'source_folder', recA), ...
    fullfile(recA, 'rec_morning.json'));

% A real probe map and a decoy non-probe .json that must NOT be counted.
writeJson(struct('chanMap', 0:15, 'xc', zeros(1,16), 'yc', (0:15)*20, ...
    'kcoords', zeros(1,16), 'n_chan', 16, 'notes', 'linear16'), ...
    fullfile(root, 'linear16.json'));
writeJson(struct('unrelated', true, 'value', 7), fullfile(root, 'notes.json'));

% Kilosort4 run #1: completed (has results + status done + cluster table).
ks1 = fullfile(recA, 'kilosort4');
mkdir(ks1);
touch(fullfile(ks1, 'spike_clusters.npy'));
touch(fullfile(ks1, 'spike_times.npy'));
touch(fullfile(ks1, 'params.py'));
writeText(fullfile(ks1, 'cluster_KSLabel.tsv'), ...
    sprintf('cluster_id\tKSLabel\n0\tgood\n1\tmua\n2\tgood\n'));
writeJson(struct('n_chan_bin', 64, 'fs', 30000, 'filename', binFile, ...
    'probe', fullfile(root,'linear16.json'), 'results_dir', ks1), ...
    fullfile(ks1, 'settings.json'));
writeJson(struct('state', 'done'), fullfile(ks1, 'ks4_status.json'));
touch(fullfile(ks1, 'run_ks4.py'));
touch(fullfile(ks1, 'ks4_run.log'));

% Kilosort4 run #2: errored, no results (only the run files + error status).
ks2 = fullfile(recB, 'kilosort4');
mkdir(ks2);
touch(fullfile(ks2, 'run_ks4.py'));
writeJson(struct('n_chan_bin', 64, 'fs', 30000, 'filename', 'x.bin', ...
    'probe', 'p.json', 'results_dir', ks2), fullfile(ks2, 'settings.json'));
writeJson(struct('state', 'error', 'message', 'boom'), ...
    fullfile(ks2, 'ks4_status.json'));

% ---- 1. Recordings -------------------------------------------------------
fprintf('\n== 1. recording discovery ==\n');
dt = DatasetTracker(root);
check(dt.NumRecordings == 2, 'found 2 recording folders');
check(dt.NumRhdFiles == 3, 'counted 3 *.rhd files total');
check(dt.Name == string(getLeaf(root)), 'Name defaults to folder leaf');
recNames = sort([dt.Recordings.Name]);
check(isequal(recNames, sort(["rec_morning","rec_evening"])), 'recording names');
ra = dt.Recordings([dt.Recordings.Name] == "rec_morning");
check(ra.NumRhdFiles == 2, 'rec_morning has 2 files');
check(isequal(ra.RhdFiles, ["a_001.rhd","a_002.rhd"]), 'files listed in order');

% ---- 2. Probe files (decoy excluded) ------------------------------------
fprintf('\n== 2. probe discovery (classification) ==\n');
check(dt.NumProbeFiles == 1, 'found exactly 1 probe (decoy .json ignored)');
check(dt.ProbeFiles(1).NumChannels == 16, 'probe channel count');
check(dt.ProbeFiles(1).NumShanks == 1, 'probe shank count');
check(dt.ProbeFiles(1).Notes == "linear16", 'probe notes');
check(~dt.ProbeFiles(1).IsDerived, 'probe not flagged derived');

% ---- 3. Bin files + sidecar ---------------------------------------------
fprintf('\n== 3. bin discovery + sidecar parse ==\n');
check(dt.NumBinFiles == 1, 'found 1 bin file');
b = dt.BinFiles(1);
check(b.NChanBin == 64 && b.Fs == 30000 && b.NSamples == 900000, 'sidecar metadata');
check(b.SourceFolder == string(recA), 'sidecar source folder');
check(b.SidecarPath ~= "", 'sidecar path recorded');

% ---- 4. Kilosort4 runs ---------------------------------------------------
fprintf('\n== 4. kilosort run discovery + state ==\n');
check(dt.NumKilosortRuns == 2, 'found 2 kilosort4 folders');
check(dt.hasKilosort, 'hasKilosort true (one run has results)');
done = dt.KilosortRuns([dt.KilosortRuns.HasResults]);
check(isscalar(done), 'exactly one run has results');
check(done.State == "done", 'completed run state = done');
check(done.NumUnits == 3, 'cluster count from cluster_KSLabel.tsv');
check(done.BinFile == string(binFile), 'run bin file from settings.json');
err = dt.KilosortRuns(~[dt.KilosortRuns.HasResults]);
check(err.State == "error" && err.Message == "boom", 'errored run state + message');
latest = dt.latestKilosortRun();
check(latest.HasResults, 'latestKilosortRun prefers a run with results');

% ---- 5. Accessors / tables ----------------------------------------------
fprintf('\n== 5. accessors + tabular views ==\n');
ds = dt.recording("rec_morning");
check(isa(ds, 'IntanDataset') && ds.NumFiles == 2, 'recording() returns an IntanDataset');
T = dt.recordingTable();
check(height(T) == 2 && any(T.NumRhdFiles == 2), 'recordingTable shape');
K = dt.kilosortTable();
check(height(K) == 2 && any(K.NumUnits == 3), 'kilosortTable shape');
check(dt.binFile(1) == string(binFile), 'binFile accessor');
threw = false;
try
    dt.recording(99);
catch
    threw = true;
end
check(threw, 'out-of-range recording index errors');

% ---- 6. Non-recursive scope + empty object ------------------------------
fprintf('\n== 6. non-recursive scan + empty object ==\n');
dtTop = DatasetTracker(root, Recursive=false);
check(dtTop.NumRecordings == 0, 'non-recursive: nested recordings not descended into');
check(dtTop.NumProbeFiles == 1, 'non-recursive: top-level probe still found');
e = DatasetTracker();   % default empty object must construct without error
check(e.NumRecordings == 0 && e.Root == "", 'empty default object');

fprintf('\n================  %d passed, %d failed  ================\n', nPass, nFail);
if nFail > 0
    error('test_DatasetTracker:Failures', '%d checks failed.', nFail);
end
end


% =========================================================================
function touch(ffn)
fid = fopen(ffn, 'w');
assert(fid >= 0, 'cannot create %s', ffn);
fclose(fid);
end

function writeText(ffn, txt)
fid = fopen(ffn, 'w');
assert(fid >= 0, 'cannot create %s', ffn);
fwrite(fid, txt, 'char');
fclose(fid);
end

function writeJson(s, ffn)
writeText(ffn, jsonencode(s));
end

function leaf = getLeaf(p)
[~, leaf] = fileparts(char(p));
end
