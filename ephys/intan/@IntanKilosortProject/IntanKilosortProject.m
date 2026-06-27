classdef IntanKilosortProject < handle
    % IntanKilosortProject  Discover and batch many Intan recordings to Kilosort4.
    %   A project scans a root directory for folders containing *.rhd files,
    %   wraps each as an IntanDataset, and provides batch operations: gather
    %   metadata into a table, write all .bin files, and launch Kilosort4 for
    %   every dataset. Shared configuration (probe, python/conda, output root,
    %   scale, dtype) is pushed down into each IntanDataset.
    %
    %   Construction
    %   ------------
    %     P = IntanKilosortProject(root)
    %     P = IntanKilosortProject(root, ProbeFile=..., PythonExe=..., OutputRoot=...)
    %
    %   Workflow
    %   --------
    %     P = IntanKilosortProject("D:\experiments");
    %     T = P.gatherMetadata();        % one row per dataset
    %     P.toBinAll();                  % stream every dataset's .bin
    %     P.runKilosortAll();            % spawn Kilosort4 for each
    %
    %   See also INTANDATASET.

    properties
        Root (1,1) string = ""
        Datasets (1,:) IntanDataset = IntanDataset.empty(1,0)

        % Shared defaults pushed into each dataset
        ProbeFile  (1,1) string = ""
        PythonExe  (1,1) string = ""
        CondaEnv   (1,1) string = ""
        OutputRoot (1,1) string = ""    % per-dataset output goes under OutputRoot/<Name>
        Scale      (1,1) double = 1/0.195
        Dtype      (1,1) string = "int16"
        Manifest                          % optional shared Manifest
    end

    properties (Dependent)
        NumDatasets
    end

    methods
        % --- methods defined in separate files ---
        T       = gatherMetadata(obj, opts)
        infos   = toBinAll(obj, opts)
        results = runKilosortAll(obj, opts)

        function obj = IntanKilosortProject(root, opts)
            arguments
                root (1,1) string = ""
                opts.ProbeFile  (1,1) string = ""
                opts.PythonExe  (1,1) string = ""
                opts.CondaEnv   (1,1) string = ""
                opts.OutputRoot (1,1) string = ""
                opts.Scale      (1,1) double = 1/0.195
                opts.Dtype      (1,1) string = "int16"
                opts.Manifest   = []
                opts.AutoDiscover (1,1) logical = true
            end

            if root == ""
                return
            end
            if ~isfolder(root)
                error('IntanKilosortProject:NoRoot', 'Root does not exist: %s', root);
            end

            obj.Root       = string(root);
            obj.ProbeFile  = opts.ProbeFile;
            obj.PythonExe  = opts.PythonExe;
            obj.CondaEnv   = opts.CondaEnv;
            obj.OutputRoot = opts.OutputRoot;
            obj.Scale      = opts.Scale;
            obj.Dtype      = opts.Dtype;
            if ~isempty(opts.Manifest)
                obj.Manifest = opts.Manifest;
            end

            if opts.AutoDiscover
                obj.discover();
            end
        end

        function discover(obj)
            %discover  Find every folder under Root containing >=1 *.rhd file.
            %   One IntanDataset is created per folder with AutoMetadata=false
            %   (cheap); shared config is pushed into each.
            D = dir(fullfile(obj.Root, '**', '*.rhd'));
            if isempty(D)
                obj.Datasets = IntanDataset.empty(1,0);
                warning('IntanKilosortProject:NoData', ...
                    'No *.rhd files found under %s', obj.Root);
                return
            end
            folders = unique(string({D.folder}), 'stable');

            ds = IntanDataset.empty(1, 0);
            for i = 1:numel(folders)
                d = IntanDataset(folders(i), AutoMetadata=false);
                obj.pushConfig(d);
                ds(end+1) = d; %#ok<AGROW>
            end
            obj.Datasets = ds;

            fprintf('Discovered %d dataset folder(s) under %s\n', numel(ds), obj.Root);
        end

        function pushConfig(obj, d)
            %pushConfig  Copy shared defaults into one IntanDataset.
            arguments
                obj (1,1) IntanKilosortProject
                d (1,1) IntanDataset
            end
            d.ProbeFile = obj.ProbeFile;
            d.PythonExe = obj.PythonExe;
            d.CondaEnv  = obj.CondaEnv;
            d.Scale     = obj.Scale;
            d.Dtype     = obj.Dtype;
            if ~isempty(obj.Manifest)
                d.Manifest = obj.Manifest;
            end
            if obj.OutputRoot ~= ""
                d.OutputDir = fullfile(obj.OutputRoot, d.Name);
            end
        end

        function d = dataset(obj, idxOrName)
            %dataset  Return one dataset by index or by Name.
            arguments
                obj (1,1) IntanKilosortProject
                idxOrName
            end
            if isnumeric(idxOrName)
                d = obj.Datasets(idxOrName);
            else
                names = [obj.Datasets.Name];
                ix = find(names == string(idxOrName), 1);
                if isempty(ix)
                    error('IntanKilosortProject:NoSuchDataset', ...
                        'No dataset named "%s".', string(idxOrName));
                end
                d = obj.Datasets(ix);
            end
        end

        function n = get.NumDatasets(obj)
            n = numel(obj.Datasets);
        end
    end
end
