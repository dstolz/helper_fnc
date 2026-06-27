classdef IntanDataset < handle
    % IntanDataset  One folder of Intan *.rhd files -> Kilosort4 .bin + run.
    %   An IntanDataset represents a single recording: one folder containing
    %   one or more *.rhd files (traditional embedded-data format) recorded
    %   contiguously. It discovers the files, gathers header metadata cheaply
    %   (without reading amplifier data), reads/filters/screens the data,
    %   streams a Kilosort4 .bin file to disk, and spawns Kilosort4.
    %
    %   Existing helpers are reused, never forked:
    %     read_Intan_RHD2000_file_modified  per-file reader (called by readData/toBin)
    %     matrix2kilosort                   in-memory .bin writer (matrixToBin)
    %
    %   Construction
    %   ------------
    %     ds = IntanDataset(folder)                       % auto-refresh metadata
    %     ds = IntanDataset(folder, AutoMetadata=false)   % cheap; defer parsing
    %     ds = IntanDataset(folder, ProbeFile=..., PythonExe=..., OutputDir=...)
    %
    %   Typical workflow
    %   ----------------
    %     ds = IntanDataset("D:\rec\subj1_day1");
    %     T  = ds.PerFile;                 % per-file header summary
    %     info = ds.toBin();               % stream raw broadband int16 .bin
    %     ds.ProbeFile = "probe.json";
    %     ds.PythonExe = "C:\miniconda3\python.exe";
    %     res = ds.runKilosort();          % write run_ks4.py + settings.json, spawn
    %
    %   See also INTANKILOSORTPROJECT, READ_INTAN_RHD2000_FILE_MODIFIED,
    %   MATRIX2KILOSORT, EXTRACT_TRIALS.

    properties
        Folder   (1,1) string = ""      % directory containing the *.rhd files
        Files    (1,:) string = string.empty(1,0)  % *.rhd files, chronological (datenum)
        Name     (1,1) string = ""      % dataset name (defaults to folder name)
    end

    properties (SetAccess = protected)
        % Header metadata (filled by refreshMetadata; no amplifier data read)
        Fs           (1,1) double = NaN          % amplifier sample rate (Hz)
        NumChannels  (1,1) double = NaN          % amplifier channel count (first file)
        ChannelNames (1,:) string = string.empty(1,0)  % custom_channel_name
        NativeNames  (1,:) string = string.empty(1,0)  % native_channel_name
        DigInNames   (1,:) string = string.empty(1,0)  % board dig-in custom names
        Duration     (1,1) double = NaN          % total recording duration (s)
        AcqDate      datetime = NaT              % earliest file datenum
        NumFiles     (1,1) double = 0            % number of *.rhd files
        PerFile      struct = struct([])         % per-file header summary (struct array)
    end

    properties
        % Configuration (also pushed down from IntanKilosortProject)
        ProbeFile (1,1) string = ""              % existing KS4 probe .json (validated, never generated)

        % Amplifier channels to exclude from Kilosort4 sorting, as 1-based
        % indices into this recording's channels (matching the .bin row order
        % written by toBin, i.e. probe chanMap value + 1). May differ per
        % recording (bad/disconnected sites vary across sessions). Excluded
        % channels are still written to the .bin (n_chan_bin is unchanged); they
        % are simply dropped from the probe's chanMap/xc/yc/kcoords at run time
        % so Kilosort4 ignores them. The *.rhd files and probe .json are never
        % modified. See runKilosort, parseChannelList, formatChannelList.
        ExcludeChannels (1,:) double = double.empty(1,0)

        PythonExe (1,1) string = ""              % python/conda exe path for KS4 spawn
        CondaEnv  (1,1) string = ""              % conda env name (uses `conda run -n` when set)
        Scale     (1,1) double = 1/0.195         % int16 scale (restores native ADC resolution)
        Dtype     (1,1) string {mustBeMember(Dtype, ...
            ["int16","uint16","int32","single","float32"])} = "int16"
        OutputDir (1,1) string = ""              % output dir for .bin / KS4 results (default = Folder)
        Manifest                                  % optional Manifest for provenance

        % Manually defined artifact periods to blank before writing the .bin.
        % [k x 2] of [tStart tEnd] in seconds, recording-relative (file 1 = t0),
        % set on the Visualize tab. toBin zeros these samples on every channel;
        % the original *.rhd files are never modified. See addArtifact /
        % manualArtifactMask.
        ManualArtifacts (:,2) double = zeros(0,2)

        % Automatic artifact-detection configuration applied by toBin (when
        % Enabled) to zero large per-channel amplitude deviations before the
        % .bin is written; never touches the *.rhd files. Set from the Artifacts
        % tab. RmsWindowMs/MergeGapMs/PadMs are in milliseconds (converted to
        % samples with Fs). See detectArtifacts, analyzeArtifacts, toBin and
        % defaultArtifactConfig.
        ArtifactConfig struct = IntanDataset.defaultArtifactConfig()
    end

    properties (Dependent)
        BinFile     % full path to the .bin (OutputDir/Name.bin)
        NumSamples  % total amplifier samples across files (sum of PerFile)
    end

    methods
        % --- methods defined in separate files in this @-folder ---
        refreshMetadata(obj)
        data   = readData(obj, opts)
        X      = filterContinuous(obj, X, opts)
        [mask, intervals, stats] = detectArtifacts(obj, X, opts)
        summary = analyzeArtifacts(obj, opts)
        X      = blankArtifacts(obj, X, mask, opts)
        mask   = manualArtifactMask(obj, nSamp, sampleOffset, Fs)
        addArtifact(obj, t0, t1)
        info   = toBin(obj, opts)
        info   = matrixToBin(obj, X, opts)
        result = runKilosort(obj, opts)

        function obj = IntanDataset(folder, opts)
            %IntanDataset  Construct from a folder of *.rhd files.
            arguments
                folder (1,1) string = ""
                opts.AutoMetadata (1,1) logical = true
                opts.Name (1,1) string = ""
                opts.ProbeFile (1,1) string = ""
                opts.PythonExe (1,1) string = ""
                opts.CondaEnv  (1,1) string = ""
                opts.Scale     (1,1) double = 1/0.195
                opts.Dtype     (1,1) string = "int16"
                opts.OutputDir (1,1) string = ""
                opts.Manifest  = []
            end

            if folder == ""
                return  % allow empty default object (arrays, preallocation)
            end
            if ~isfolder(folder)
                error('IntanDataset:NoFolder', 'Folder does not exist: %s', folder);
            end

            obj.Folder    = string(folder);
            obj.Name      = opts.Name;
            obj.ProbeFile = opts.ProbeFile;
            obj.PythonExe = opts.PythonExe;
            obj.CondaEnv  = opts.CondaEnv;
            obj.Scale     = opts.Scale;
            obj.Dtype     = opts.Dtype;
            obj.OutputDir = opts.OutputDir;
            if ~isempty(opts.Manifest)
                obj.Manifest = opts.Manifest;
            end

            if obj.Name == ""
                [~, leaf] = fileparts(char(obj.Folder));
                obj.Name = string(leaf);
            end

            obj.discoverFiles();

            if opts.AutoMetadata
                obj.refreshMetadata();
            end
        end

        function discoverFiles(obj)
            %discoverFiles  Find *.rhd in Folder, sort chronologically by datenum.
            D = dir(fullfile(obj.Folder, '*.rhd'));
            if isempty(D)
                obj.Files = string.empty(1,0);
                obj.NumFiles = 0;
                return
            end
            [~, ix] = sort([D.datenum]);
            D = D(ix);
            obj.Files = string({D.name});
            obj.NumFiles = numel(D);
            obj.AcqDate = datetime(min([D.datenum]), 'ConvertFrom', 'datenum');
        end

        %% Dependent getters
        function f = get.BinFile(obj)
            f = fullfile(obj.outputFolder(), obj.Name + ".bin");
        end

        function n = get.NumSamples(obj)
            if isempty(obj.PerFile) || ~isfield(obj.PerFile, 'numAmplifierSamples')
                n = NaN;
                return
            end
            n = sum([obj.PerFile.numAmplifierSamples]);
        end

        function p = outputFolder(obj)
            %outputFolder  Resolve OutputDir, defaulting to the dataset Folder.
            if obj.OutputDir == ""
                p = obj.Folder;
            else
                p = obj.OutputDir;
            end
        end
    end

    methods (Static)
        function cfg = defaultArtifactConfig()
            %defaultArtifactConfig  Default automatic artifact-detection settings.
            %   Used to initialise ArtifactConfig. RmsWindowMs/MergeGapMs/PadMs
            %   are in milliseconds (converted to samples with Fs at run time);
            %   RmsWindowMs NaN means "auto" (~1 ms).
            cfg = struct( ...
                'Enabled',     false, ...   % toBin blanks only when true
                'Method',      "rms", ...   % running-RMS amplitude deviation
                'Threshold',   9, ...       % robust SDs above per-channel baseline
                'RmsWindowMs', NaN, ...     % ms; NaN = auto (~1 ms)
                'MergeGapMs',  0, ...       % ms; stitch gaps <= this
                'MinChannels', 2, ...       % channels exceeding simultaneously
                'PadMs',       0);          % ms to expand each flagged run
        end

        function cfg = normalizeArtifactConfig(cfg)
            %normalizeArtifactConfig  Fill missing fields from the defaults.
            %   Tolerates partial/stale ArtifactConfig structs (e.g. a project
            %   saved before a field such as RmsWindowMs was added) by merging
            %   the given struct onto defaultArtifactConfig; unknown extra
            %   fields are dropped.
            def = IntanDataset.defaultArtifactConfig();
            if isempty(cfg) || ~isstruct(cfg)
                cfg = def;
                return
            end
            fn = fieldnames(def);
            for k = 1:numel(fn)
                if isfield(cfg, fn{k})
                    def.(fn{k}) = cfg.(fn{k});
                end
            end
            cfg = def;
        end

        function ch = parseChannelList(s)
            %parseChannelList  Parse "1,3,5-8" / "1 3 5:8" / [] into channel indices.
            %   Accepts a char/string spec (commas, spaces, colon or hyphen
            %   ranges) or a numeric vector. Returns a sorted, unique row vector
            %   of positive integers (empty when nothing valid is given).
            if isnumeric(s)
                ch = s(:).';
            else
                t = char(string(s));
                t = strrep(strrep(t, ',', ' '), '-', ':');  % hyphen ranges -> colon
                ch = str2num(t); %#ok<ST2NM>  % supports colon ranges like 5:8
            end
            if isempty(ch); ch = double.empty(1,0); return; end
            ch = round(ch(:).');
            ch = unique(ch(ch >= 1));
        end

        function s = formatChannelList(ch)
            %formatChannelList  Compact a channel vector to "1,3,5-8" form.
            ch = IntanDataset.parseChannelList(ch);
            if isempty(ch); s = ""; return; end
            d = [true, diff(ch) ~= 1];          % run starts
            starts = ch(d);
            ends   = ch([d(2:end), true]);      % run ends
            parts = strings(1, numel(starts));
            for k = 1:numel(starts)
                if starts(k) == ends(k)
                    parts(k) = string(starts(k));
                else
                    parts(k) = starts(k) + "-" + ends(k);
                end
            end
            s = strjoin(parts, ",");
        end
    end

    methods (Static, Access = private)
        hdr = parseIntanHeader(ffn)
    end
end
