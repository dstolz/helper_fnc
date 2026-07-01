classdef DatasetTracker < handle
    % DatasetTracker  Filesystem inventory of one dataset directory.
    %   Given a dataset directory, a DatasetTracker discovers every artifact
    %   the Intan -> Kilosort4 pipeline produces or consumes and exposes them in
    %   a uniform, read-only form so other classes and GUIs do not each have to
    %   re-implement the same `dir`/`jsondecode` scans. It tracks:
    %
    %     Recordings   folders that directly contain >=1 *.rhd file (one
    %                  IntanDataset's worth of raw data each)
    %     ProbeFiles   Kilosort4 probe .json maps (chanMap/xc/yc), including any
    %                  derived *_excluded.json written next to a sort
    %     BinFiles     streamed *.bin files plus their JSON sidecars
    %                  (n_chan_bin / fs / n_samples, written by IntanDataset.toBin)
    %     KilosortRuns kilosort4 output folders (params.py / run_ks4.py /
    %                  spike_clusters.npy / ks4_status.json), with run state
    %
    %   Discovery is purely filesystem-based (no amplifier data is read and no
    %   *.rhd header is parsed), so it is cheap and stays correct even if the
    %   on-disk layout differs from the pipeline defaults. The directory may be a
    %   single recording folder (*.rhd directly inside) or a parent containing
    %   many recording sub-folders; both are handled.
    %
    %   Construction
    %   ------------
    %     dt = DatasetTracker(folder)                    % auto-refresh
    %     dt = DatasetTracker(folder, AutoRefresh=false) % defer the scan
    %     dt = DatasetTracker(folder, Recursive=false)   % only the top level
    %     dt = DatasetTracker.fromDataset(intanDataset)  % track ds.Folder
    %
    %   Typical use
    %   -----------
    %     dt = DatasetTracker("D:\rec\subj1_day1");
    %     T  = dt.recordingTable();        % one row per recording (for a uigridtable)
    %     ds = dt.recording(1);            % an IntanDataset for further work
    %     if dt.hasKilosort
    %         r = dt.latestKilosortRun();  % most recent sort with results
    %         resultsDir = r.Dir;          % hand to the Review tab / phy / loaders
    %     end
    %
    %   The four inventory properties are protected struct arrays (read-only to
    %   callers); refresh re-scans the tree and refreshes them all. The struct
    %   field schemas are documented on each emptyX template below.
    %
    %   See also INTANDATASET, INTANKILOSORTPROJECT, INTANKILOSORTAPP.

    properties
        Root      (1,1) string  = ""      % the dataset directory being tracked
        Name      (1,1) string  = ""      % dataset name (defaults to folder leaf)
        Recursive (1,1) logical = true    % scan sub-folders (false = top level only)
    end

    properties (SetAccess = protected)
        % Inventory, filled by refresh. See the emptyX static templates for the
        % field schema of each struct array.
        Recordings    struct = DatasetTracker.emptyRecordings()
        ProbeFiles    struct = DatasetTracker.emptyProbes()
        BinFiles      struct = DatasetTracker.emptyBins()
        KilosortRuns  struct = DatasetTracker.emptyKSRuns()
        LastRefreshed datetime = NaT       % time of the last successful scan
    end

    properties (Dependent)
        NumRecordings    % number of recording folders found
        NumProbeFiles    % number of probe .json maps found
        NumBinFiles      % number of *.bin files found
        NumKilosortRuns  % number of kilosort4 output folders found
        NumRhdFiles      % total *.rhd files across all recordings
    end

    methods
        function obj = DatasetTracker(root, opts)
            %DatasetTracker  Construct a tracker for one dataset directory.
            arguments
                root (1,1) string = ""
                opts.Name (1,1) string = ""
                opts.Recursive (1,1) logical = true
                opts.AutoRefresh (1,1) logical = true
            end

            if root == ""
                return  % allow empty default object (arrays, preallocation)
            end
            if ~isfolder(root)
                error('DatasetTracker:NoFolder', 'Folder does not exist: %s', root);
            end

            obj.Root      = string(root);
            obj.Recursive = opts.Recursive;
            obj.Name      = opts.Name;
            if obj.Name == ""
                [~, leaf] = fileparts(char(obj.Root));
                obj.Name = string(leaf);
            end

            if opts.AutoRefresh
                obj.refresh();
            end
        end

        function refresh(obj)
            %refresh  Re-scan the directory and rebuild the whole inventory.
            if obj.Root == "" || ~isfolder(obj.Root)
                error('DatasetTracker:NoFolder', ...
                    'Root is not a valid folder: %s', obj.Root);
            end
            obj.Recordings   = obj.discoverRecordings();
            obj.ProbeFiles   = obj.discoverProbeFiles();
            obj.BinFiles     = obj.discoverBinFiles();
            obj.KilosortRuns = obj.discoverKilosortRuns();
            obj.LastRefreshed = datetime('now');
        end

        %% Dependent getters
        function n = get.NumRecordings(obj);   n = numel(obj.Recordings);   end
        function n = get.NumProbeFiles(obj);   n = numel(obj.ProbeFiles);   end
        function n = get.NumBinFiles(obj);     n = numel(obj.BinFiles);     end
        function n = get.NumKilosortRuns(obj); n = numel(obj.KilosortRuns); end
        function n = get.NumRhdFiles(obj)
            if isempty(obj.Recordings)
                n = 0;
            else
                n = sum([obj.Recordings.NumRhdFiles]);
            end
        end

        %% Accessors -------------------------------------------------------
        function ds = recording(obj, idxOrName, opts)
            %recording  Return an IntanDataset for a tracked recording folder.
            %   ds = dt.recording(i) or dt.recording("name"). Constructed with
            %   AutoMetadata=false (cheap); pass AutoMetadata=true to parse
            %   headers immediately. This is how other classes obtain a working
            %   object from the inventory.
            arguments
                obj (1,1) DatasetTracker
                idxOrName
                opts.AutoMetadata (1,1) logical = false
            end
            rec = obj.pickRecording(idxOrName);
            ds = IntanDataset(rec.Folder, AutoMetadata=opts.AutoMetadata, Name=rec.Name);
        end

        function p = probeFile(obj, idx)
            %probeFile  Full path to the idx-th discovered probe .json.
            arguments
                obj (1,1) DatasetTracker
                idx (1,1) double = 1
            end
            obj.assertIndex(obj.ProbeFiles, idx, 'probe file');
            p = obj.ProbeFiles(idx).Path;
        end

        function p = binFile(obj, idx)
            %binFile  Full path to the idx-th discovered *.bin file.
            arguments
                obj (1,1) DatasetTracker
                idx (1,1) double = 1
            end
            obj.assertIndex(obj.BinFiles, idx, 'bin file');
            p = obj.BinFiles(idx).Path;
        end

        function r = kilosortRun(obj, idx)
            %kilosortRun  The idx-th Kilosort4 run struct (see emptyKSRuns).
            arguments
                obj (1,1) DatasetTracker
                idx (1,1) double = 1
            end
            obj.assertIndex(obj.KilosortRuns, idx, 'Kilosort4 run');
            r = obj.KilosortRuns(idx);
        end

        function r = latestKilosortRun(obj)
            %latestKilosortRun  Most-recently-modified run, preferring sorts that
            %   actually produced results. Returns [] when none were found.
            r = [];
            if isempty(obj.KilosortRuns)
                return
            end
            runs = obj.KilosortRuns;
            withResults = runs([runs.HasResults]);
            if ~isempty(withResults)
                runs = withResults;
            end
            [~, ix] = max([runs.Modified]);
            r = runs(ix);
        end

        function tf = hasBin(obj);      tf = obj.NumBinFiles > 0;     end
        function tf = hasProbe(obj);    tf = obj.NumProbeFiles > 0;   end
        function tf = hasKilosort(obj)
            %hasKilosort  True when at least one run produced spike output.
            tf = ~isempty(obj.KilosortRuns) && any([obj.KilosortRuns.HasResults]);
        end

        %% Tabular views (for GUI tables) ---------------------------------
        function T = recordingTable(obj)
            %recordingTable  One row per recording (Name, NumRhdFiles, AcqDate, ...).
            if isempty(obj.Recordings)
                T = table('Size', [0 5], ...
                    'VariableTypes', {'string','string','double','datetime','double'}, ...
                    'VariableNames', {'Name','Folder','NumRhdFiles','AcqDate','SizeMB'});
                return
            end
            R = obj.Recordings;
            T = table([R.Name].', [R.Folder].', [R.NumRhdFiles].', ...
                [R.AcqDate].', round([R.Bytes].'/1e6, 1), ...
                'VariableNames', {'Name','Folder','NumRhdFiles','AcqDate','SizeMB'});
        end

        function T = kilosortTable(obj)
            %kilosortTable  One row per Kilosort4 run (State, HasResults, NumUnits, Dir).
            if isempty(obj.KilosortRuns)
                T = table('Size', [0 5], ...
                    'VariableTypes', {'string','string','logical','double','datetime'}, ...
                    'VariableNames', {'Name','State','HasResults','NumUnits','Modified'});
                return
            end
            K = obj.KilosortRuns;
            T = table([K.Name].', [K.State].', logical([K.HasResults].'), ...
                [K.NumUnits].', [K.Modified].', ...
                'VariableNames', {'Name','State','HasResults','NumUnits','Modified'});
        end

        function disp(obj)
            %disp  Concise inventory summary.
            if ~isscalar(obj)
                fprintf('  %s array\n', class(obj));
                builtin('disp', obj);
                return
            end
            if obj.Root == ""
                fprintf('  DatasetTracker (empty)\n\n');
                return
            end
            fprintf('  DatasetTracker "%s"\n', obj.Name);
            fprintf('    Root            : %s\n', obj.Root);
            fprintf('    Recordings      : %d (%d *.rhd file(s))\n', ...
                obj.NumRecordings, obj.NumRhdFiles);
            fprintf('    Probe files     : %d\n', obj.NumProbeFiles);
            fprintf('    Bin files       : %d\n', obj.NumBinFiles);
            nDone = 0;
            if ~isempty(obj.KilosortRuns); nDone = sum([obj.KilosortRuns.HasResults]); end
            fprintf('    Kilosort4 runs  : %d (%d with results)\n', ...
                obj.NumKilosortRuns, nDone);
            if ~isnat(obj.LastRefreshed)
                fprintf('    Last refreshed  : %s\n', ...
                    char(obj.LastRefreshed, 'yyyy-MM-dd HH:mm:ss'));
            end
            fprintf('\n');
        end
    end

    methods (Access = private)
        function rec = discoverRecordings(obj)
            %discoverRecordings  Group *.rhd files by their containing folder.
            %   Thin wrapper over the shared static DatasetTracker.findRecordings
            %   so this class and IntanKilosortProject agree on what a recording
            %   is (a folder directly containing >=1 *.rhd file).
            rec = DatasetTracker.findRecordings(obj.Root, obj.Recursive);
        end

        function probes = discoverProbeFiles(obj)
            %discoverProbeFiles  Find and classify probe .json maps.
            %   Every *.json is parsed once and classified; only those that are
            %   probe maps (chanMap or xc/yc, not a .bin sidecar / KS settings /
            %   status file) are kept. Channel/shank/depth/notes are read like
            %   IntanKilosortApp.refreshProbeList.
            D = obj.findFiles('*.json');
            probes = DatasetTracker.emptyProbes();
            k = 0;
            for i = 1:numel(D)
                pth = fullfile(D(i).folder, D(i).name);
                s = DatasetTracker.readJson(pth);
                if DatasetTracker.classifyJson(s) ~= "probe"
                    continue
                end
                m = DatasetTracker.probeMeta(s);
                [~, leaf] = fileparts(D(i).name);
                k = k + 1;
                probes(k).Name        = string(D(i).name);
                probes(k).Path        = string(pth);
                probes(k).NumChannels = m.nChan;
                probes(k).NumShanks   = m.nShank;
                probes(k).DepthUm      = m.depth;
                probes(k).Notes       = m.notes;
                % Derived per-sort probe written by runKilosort (writeExcludedProbe).
                probes(k).IsDerived   = endsWith(leaf, "_excluded");
            end
        end

        function bins = discoverBinFiles(obj)
            %discoverBinFiles  Find *.bin files and read their JSON sidecars.
            %   The sidecar (<name>.json, written by IntanDataset.toBin) carries
            %   n_chan_bin / fs / n_samples / source_folder; absent or unreadable
            %   sidecars leave those NaN/"" but the .bin is still listed.
            D = obj.findFiles('*.bin');
            bins = DatasetTracker.emptyBins();
            for i = 1:numel(D)
                pth  = fullfile(D(i).folder, D(i).name);
                [~, leaf] = fileparts(D(i).name);
                side = fullfile(D(i).folder, [leaf '.json']);
                meta = struct();
                if isfile(side); meta = DatasetTracker.readJson(side); end
                bins(i).Name         = string(D(i).name);
                bins(i).Path         = string(pth);
                bins(i).Bytes        = D(i).bytes;
                bins(i).Modified     = datetime(D(i).datenum, 'ConvertFrom', 'datenum');
                bins(i).SidecarPath  = string(ternary(isfile(side), side, ""));
                bins(i).NChanBin     = getfielddef(meta, 'n_chan_bin', NaN);
                bins(i).Fs           = getfielddef(meta, 'fs', NaN);
                bins(i).NSamples     = getfielddef(meta, 'n_samples', NaN);
                bins(i).SourceFolder = string(getfielddef(meta, 'source_folder', ""));
            end
        end

        function runs = discoverKilosortRuns(obj)
            %discoverKilosortRuns  Find kilosort4 output folders and their state.
            %   A run folder is any directory containing a recognised Kilosort4
            %   marker (spike output, the generated run script/settings, or the
            %   status file). State and the input bin/probe come from the files
            %   runKilosort writes (ks4_status.json / settings.json).
            markers = ["spike_clusters.npy", "params.py", "run_ks4.py", ...
                "settings.json", "ks4_status.json"];
            dirs = string.empty(1, 0);
            for m = markers
                D = obj.findFiles(m);
                if ~isempty(D)
                    dirs = [dirs, string({D.folder})]; %#ok<AGROW>
                end
            end
            dirs = unique(dirs, 'stable');
            runs = DatasetTracker.emptyKSRuns();
            for i = 1:numel(dirs)
                d = char(dirs(i));
                [~, leaf] = fileparts(d);
                hasResults = isfile(fullfile(d, 'spike_clusters.npy'));

                state = ""; message = "";
                statusFile = fullfile(d, 'ks4_status.json');
                if isfile(statusFile)
                    st = DatasetTracker.readJson(statusFile);
                    state   = string(getfielddef(st, 'state', ""));
                    message = string(getfielddef(st, 'message', ""));
                elseif hasResults
                    state = "done";   % results present, no status file (older run)
                end

                settingsFile = fullfile(d, 'settings.json');
                binFile = ""; probeFile = ""; fs = NaN; nChanBin = NaN;
                if isfile(settingsFile)
                    sj = DatasetTracker.readJson(settingsFile);
                    binFile   = string(getfielddef(sj, 'filename', ""));
                    probeFile = string(getfielddef(sj, 'probe', ""));
                    fs        = getfielddef(sj, 'fs', NaN);
                    nChanBin  = getfielddef(sj, 'n_chan_bin', NaN);
                end

                runs(i).Name         = string(leaf);
                runs(i).Dir          = dirs(i);
                runs(i).HasResults   = hasResults;
                runs(i).State        = state;
                runs(i).Message      = message;
                runs(i).NumUnits     = countClusters(d);
                runs(i).SettingsPath = string(ternary(isfile(settingsFile), settingsFile, ""));
                runs(i).ScriptPath   = string(ternary(isfile(fullfile(d,'run_ks4.py')), fullfile(d,'run_ks4.py'), ""));
                runs(i).LogPath      = string(ternary(isfile(fullfile(d,'ks4_run.log')), fullfile(d,'ks4_run.log'), ""));
                runs(i).StatusPath   = string(ternary(isfile(statusFile), statusFile, ""));
                runs(i).BinFile      = binFile;
                runs(i).ProbeFile    = probeFile;
                runs(i).Fs           = fs;
                runs(i).NChanBin     = nChanBin;
                runs(i).Modified     = folderModified(d);
            end
        end

        function D = findFiles(obj, pattern)
            %findFiles  Files matching PATTERN, recursive or top-level per Recursive.
            D = DatasetTracker.listFiles(obj.Root, pattern, obj.Recursive);
        end

        function rec = pickRecording(obj, idxOrName)
            %pickRecording  Resolve a recording by 1-based index or by Name.
            if isempty(obj.Recordings)
                error('DatasetTracker:NoRecordings', 'No recordings discovered.');
            end
            if isnumeric(idxOrName)
                obj.assertIndex(obj.Recordings, idxOrName, 'recording');
                rec = obj.Recordings(idxOrName);
            else
                ix = find([obj.Recordings.Name] == string(idxOrName), 1);
                if isempty(ix)
                    error('DatasetTracker:NoSuchRecording', ...
                        'No recording named "%s".', string(idxOrName));
                end
                rec = obj.Recordings(ix);
            end
        end
    end

    methods (Access = private, Static)
        function assertIndex(arr, idx, what)
            if ~isscalar(idx) || idx < 1 || idx > numel(arr) || idx ~= round(idx)
                error('DatasetTracker:BadIndex', ...
                    '%s index %g is out of range (1..%d).', what, idx, numel(arr));
            end
        end
    end

    methods (Static)
        function dt = fromDataset(ds)
            %fromDataset  Build a tracker for an existing IntanDataset's folder.
            arguments
                ds (1,1) IntanDataset
            end
            dt = DatasetTracker(ds.Folder);
        end

        %% Shared discovery / parsing helpers ------------------------------
        %  Public so IntanDataset / IntanKilosortProject / IntanKilosortApp can
        %  reuse one implementation of the scans they used to each hand-roll.
        function D = listFiles(root, pattern, recursive)
            %listFiles  Files matching PATTERN under ROOT (recursive or top-level).
            %   Excludes directories (a glob can match folder names too). Shared
            %   by every DatasetTracker scan and exposed for external callers.
            arguments
                root (1,1) string
                pattern (1,1) string
                recursive (1,1) logical = true
            end
            if recursive
                D = dir(fullfile(root, '**', char(pattern)));
            else
                D = dir(fullfile(root, char(pattern)));
            end
            if ~isempty(D)
                D = D(~[D.isdir]);
            end
        end

        function rec = findRecordings(root, recursive)
            %findRecordings  Group *.rhd files under ROOT by containing folder.
            %   Returns a Recordings struct array (see emptyRecordings): one row
            %   per folder that directly contains >=1 *.rhd file, files listed
            %   chronologically by datenum. This is the single definition of "a
            %   recording" shared by DatasetTracker.refresh and
            %   IntanKilosortProject.discover.
            arguments
                root (1,1) string
                recursive (1,1) logical = true
            end
            D = DatasetTracker.listFiles(root, '*.rhd', recursive);
            rec = DatasetTracker.emptyRecordings();
            if isempty(D)
                return
            end
            allFolders = string({D.folder});
            folders = unique(allFolders, 'stable');
            for i = 1:numel(folders)
                Di = D(allFolders == folders(i));
                [~, ix] = sort([Di.datenum]);
                Di = Di(ix);
                [~, leaf] = fileparts(char(folders(i)));
                rec(i).Name        = string(leaf);
                rec(i).Folder      = folders(i);
                rec(i).RhdFiles    = string({Di.name});
                rec(i).NumRhdFiles = numel(Di);
                rec(i).AcqDate     = datetime(min([Di.datenum]), 'ConvertFrom', 'datenum');
                rec(i).Bytes       = sum([Di.bytes]);
                rec(i).IsRoot      = folders(i) == root;
            end
        end

        function folders = findRecordingFolders(root, recursive)
            %findRecordingFolders  Folders directly containing >=1 *.rhd file.
            %   Stable order. Convenience over findRecordings for callers (e.g.
            %   IntanKilosortProject.discover) that only need the folder paths.
            arguments
                root (1,1) string
                recursive (1,1) logical = true
            end
            rec = DatasetTracker.findRecordings(root, recursive);
            if isempty(rec)
                folders = string.empty(1, 0);
            else
                folders = [rec.Folder];
            end
        end

        function s = readJson(pth)
            %readJson  jsondecode a file, returning [] on any read/parse failure.
            try
                s = jsondecode(fileread(pth));
            catch
                s = [];
            end
        end

        function kind = classifyJson(s)
            %classifyJson  Tag a parsed .json by the pipeline artifact it is.
            %   "ks-settings" (run_ks4 input), "bin-sidecar" (toBin meta),
            %   "ks-status", "probe" (chanMap/xc map), or "other". Checked
            %   most-specific-first so a probe (which also has n_chan) is not
            %   mistaken for a .bin sidecar or settings file.
            kind = "other";
            if isempty(s) || ~isstruct(s)
                return
            end
            if isfield(s, 'results_dir') && isfield(s, 'probe')
                kind = "ks-settings";
            elseif isfield(s, 'bin_file') || isfield(s, 'source_folder')
                kind = "bin-sidecar";
            elseif isfield(s, 'state')
                kind = "ks-status";
            elseif isfield(s, 'chanMap') || (isfield(s, 'xc') && isfield(s, 'yc'))
                kind = "probe";
            end
        end

        function m = probeMeta(s)
            %probeMeta  Channel/shank/depth/notes from a parsed probe struct.
            %   Single source of truth for probe-map metadata, reused by the
            %   app's Probe tab (see IntanKilosortApp.refreshProbeList).
            m = struct('nChan', NaN, 'nShank', NaN, 'depth', NaN, 'notes', "");
            if isempty(s) || ~isstruct(s)
                return
            end
            % Channel count: trust n_chan, but a chanMap can never have more
            % sites than total channels, so an n_chan that is missing or
            % SMALLER than numel(chanMap) (e.g. written from a 0-based map's
            % max index) is bogus -- fall back to the map length.
            nMap = NaN;
            if isfield(s, 'chanMap'); nMap = numel(s.chanMap); end
            if isfield(s, 'n_chan');  m.nChan = double(s.n_chan); end
            if ~isnan(nMap); m.nChan = max([m.nChan, nMap], [], 'omitnan'); end
            if isfield(s, 'kcoords') && ~isempty(s.kcoords)
                m.nShank = numel(unique(s.kcoords));
            end
            if isfield(s, 'yc') && ~isempty(s.yc)
                yc = double(s.yc(:));
                m.depth = max(yc) - min(yc);
            end
            if isfield(s, 'notes') && ~isempty(s.notes)
                m.notes = string(s.notes);
            end
        end

        %% Empty struct templates (define the inventory field schemas) -----
        function s = emptyRecordings()
            %emptyRecordings  0x0 struct array; one element per recording folder.
            s = struct('Name', {}, 'Folder', {}, 'RhdFiles', {}, ...
                'NumRhdFiles', {}, 'AcqDate', {}, 'Bytes', {}, 'IsRoot', {});
        end

        function s = emptyProbes()
            %emptyProbes  0x0 struct array; one element per probe .json.
            s = struct('Name', {}, 'Path', {}, 'NumChannels', {}, ...
                'NumShanks', {}, 'DepthUm', {}, 'Notes', {}, 'IsDerived', {});
        end

        function s = emptyBins()
            %emptyBins  0x0 struct array; one element per *.bin file.
            s = struct('Name', {}, 'Path', {}, 'Bytes', {}, 'Modified', {}, ...
                'SidecarPath', {}, 'NChanBin', {}, 'Fs', {}, 'NSamples', {}, ...
                'SourceFolder', {});
        end

        function s = emptyKSRuns()
            %emptyKSRuns  0x0 struct array; one element per kilosort4 folder.
            s = struct('Name', {}, 'Dir', {}, 'HasResults', {}, 'State', {}, ...
                'Message', {}, 'NumUnits', {}, 'SettingsPath', {}, ...
                'ScriptPath', {}, 'LogPath', {}, 'StatusPath', {}, ...
                'BinFile', {}, 'ProbeFile', {}, 'Fs', {}, 'NChanBin', {}, ...
                'Modified', {});
        end
    end
end


%% ===== file-local helpers ==================================================

function n = countClusters(folder)
%countClusters  Count clusters from a phy/KS .tsv (cheap; no .npy read).
%   Uses cluster_KSLabel.tsv (falling back to cluster_group.tsv): one data row
%   per cluster. Returns NaN when neither file is present.
n = NaN;
for fname = ["cluster_KSLabel.tsv", "cluster_group.tsv"]
    fp = fullfile(folder, char(fname));
    if ~isfile(fp); continue; end
    txt = fileread(fp);
    lines = splitlines(string(txt));
    lines = lines(strlength(strip(lines)) > 0);   % drop blank lines
    n = max(numel(lines) - 1, 0);                  % minus the header row
    return
end
end


function v = getfielddef(s, name, default)
%getfielddef  s.(name) when present and non-empty, else DEFAULT.
v = default;
if ~isempty(s) && isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end


function t = folderModified(folder)
%folderModified  Newest modification time among a folder's direct contents.
%   A run's age is "when did it last produce output", so this looks at the
%   files inside the folder (the folder's own datenum is unreliable on Windows).
D = dir(folder);
D = D(~[D.isdir]);
if isempty(D)
    t = datetime(NaN, 'ConvertFrom', 'datenum');
else
    t = datetime(max([D.datenum]), 'ConvertFrom', 'datenum');
end
end


function out = ternary(cond, a, b)
%ternary  a when COND else b (keeps the inventory builders terse).
if cond; out = a; else; out = b; end
end
