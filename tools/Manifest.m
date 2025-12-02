classdef Manifest < handle
    % Manifest
    % Track preprocessing progress as a list of entries.
    % Fields per entry: type, description, timestamp, notes, parameterValues.
    %
    % Examples
    % Basic usage:
    %   m = Manifest;
    %   m.add("load","Loaded raw data", struct("file","A1.mat"));
    %   m.add("filter","Bandpass", struct("lowHz",300,"highHz",3000), "FIR 300-3000 Hz");
    %   m.show(FlattenParams=true);
    %   T = m.toTable(FlattenParams=true);
    %
    % Search and access:
    %   % by substring (case-insensitive)
    %   m2 = m.search(Text="bandpass");
    %   % startsWith
    %   m2 = m.search(Text="band", Match="starts");
    %   % endsWith
    %   m2 = m.search(Text="pass", Match="ends");
    %   % exact, case-sensitive
    %   m2 = m.search(Text="Bandpass", Match="exact", IgnoreCase=false);
    %   % regex
    %   m2 = m.search(Text="^band.*", Match="regex");
    %   % restrict fields
    %   m2 = m.search(Text="note", Fields=["notes"]);
    %   % time window and parameter filter
    %   t0 = datetime(2025,10,14); t1 = datetime(2025,10,15);
    %   m2 = m.search(StartTime=t0, EndTime=t1, ParamName="lowHz", ParamValue=300);
    %   n  = m.count;
    %   e  = m.latest; % struct of the most recent entry
    %
    % Notes
    %   parameterValues can be any scalar struct. Use FlattenParams to expand.

    properties
        type string = string.empty(0,1)
        description string = string.empty(0,1)
        timestamp datetime = datetime.empty(0,1)
        notes string = string.empty(0,1)
        parameterValues cell = cell(0,1)   % cell array of scalar structs (heterogeneous allowed)
        verbosity (1,1) double {mustBeMember(verbosity,0:3)} = 0  % 0: silent, 1..3: increasing detail
    end

    methods
        function self = Manifest(opts)
            % self = Manifest(opts)
            %
            % Create an empty manifest.
            % Name-Value opts:
            %   Verbosity (double, 0..3) — controls printing on add. [0]
            arguments
                opts.Verbosity (1,1) double {mustBeMember(opts.Verbosity,0:3)} = 0
            end
            self.verbosity = opts.Verbosity;
        end

        function add(self, type, description, parameterValues, notes)
            % add(self, type, description, parameterValues, notes)
            %
            % Append a new entry to the manifest.
            %  type            — label for the step (string/char)
            %  description     — short summary (string/char)
            %  parameterValues — scalar struct of parameters (optional)
            %  notes           — free text notes (optional)

            arguments
                self (1,1) Manifest
                type (1,1) string
                description (1,1) string
                parameterValues (1,1) struct = struct()
                notes (1,1) string = ""
            end

            self.type(end+1,1) = type;
            self.description(end+1,1) = description;
            self.timestamp(end+1,1) = datetime('now');
            self.notes(end+1,1) = notes;
            self.parameterValues{end+1,1} = parameterValues;

            % optional display on add, controlled by self.verbosity
            self.printOnAdd(numel(self.type));
        end

        function T = toTable(self, opts)
            % T = toTable(self, opts)
            %
            % Return manifest as a table.
            % Name-Value opts:
            %  FlattenParams (logical) — expand parameterValues fields into columns.

            arguments
                self (1,1) Manifest
                opts.FlattenParams (1,1) logical = false
            end

            if isempty(self.type)
                T = table(string.empty(0,1), string.empty(0,1), datetime.empty(0,1), string.empty(0,1), cell.empty(0,1), ...
                          'VariableNames', {'type','description','timestamp','notes','parameterValues'});
                return
            end

            T = table(self.type(:), self.description(:), self.timestamp(:), self.notes(:), ...
                      self.parameterValues(:), 'VariableNames', ...
                      {'type','description','timestamp','notes','parameterValues'});

            if opts.FlattenParams
                pv = self.parameterValues(:);
                allFields = strings(0,1);
                for k = 1:numel(pv)
                    s = pv{k};
                    if ~isempty(s)
                        allFields = [allFields; string(fieldnames(s))]; %#ok<AGROW>
                    end
                end
                allFields = unique(allFields);

                for f = allFields.'
                    fname = char(f);
                    vals = cell(height(T),1);
                    for r = 1:height(T)
                        s = pv{r};
                        if ~isempty(s) && isfield(s, fname)
                            vals{r} = s.(fname);
                        else
                            vals{r} = [];
                        end
                    end
                    safename = matlab.lang.makeValidName("param_" + f);
                    T.(safename) = vals;
                end
            end
        end

        function T = show(self, opts)
            % T = show(self, opts)
            %
            % Display the manifest as a table. Returns the table.
            % Name-Value opts:
            %  FlattenParams (logical) — expand parameterValues.
            %  MaxRows (double) — limit rows shown.

            arguments
                self (1,1) Manifest
                opts.FlattenParams (1,1) logical = false
                opts.MaxRows (1,1) double {mustBeNonnegative} = inf
            end

            T = toTable(self, FlattenParams=opts.FlattenParams);
            if isfinite(opts.MaxRows) && height(T) > 0
                T = T(1:min(opts.MaxRows, height(T)), :);
            end
            disp(T)
            if nargout == 0, clear T; end
        end

        function M = search(self, opts)
            % M = search(self, opts)
            %
            % Return a new Manifest filtered by criteria.
            % Name-Value opts:
            %  Type (string) — exact match on type
            %  Text (string) — text to match in fields
            %  Match (string) — one of: "contains" | "starts" | "ends" | "exact" | "regex"
            %  Fields (string array) — any of: "type","description","notes". Default all.
            %  IgnoreCase (logical) — case-insensitive match for Text. Default true.
            %  Contains (string) — legacy alias for Text using 'contains'
            %  StartTime (datetime) — include entries at or after this time
            %  EndTime (datetime) — include entries at or before this time
            %  ParamName (string) — parameter field name to test
            %  ParamValue — value to match against ParamName (isequal)
            %
            % Examples
            %   m.search(Text="bandpass")
            %   m.search(Text="band", Match="starts")
            %   m.search(Text="pass$", Match="regex")
            %   m.search(Text="Band", IgnoreCase=false)
            %   m.search(Text="note", Fields=["notes"])
            %   m.search(StartTime=datetime(2025,10,14), EndTime=datetime(2025,10,15))
            %   m.search(ParamName="lowHz", ParamValue=300)

            arguments
                self (1,1) Manifest
                opts.Type (1,1) string = string(missing)
                opts.Text (1,1) string = ""
                opts.Match (1,1) string = "contains"
                opts.Fields (1,:) string = ["type","description","notes"]
                opts.IgnoreCase (1,1) logical = true
                opts.Contains (1,1) string = ""
                opts.StartTime (1,1) datetime = NaT
                opts.EndTime   (1,1) datetime = NaT
                opts.ParamName (1,1) string = ""
                opts.ParamValue = []
            end

            % normalize match mode
            validModes = ["contains","starts","ends","exact","regex"];
            if ~any(opts.Match == validModes)
                error('Manifest:search','Invalid Match mode.');
            end

            n = numel(self.type);
            if n == 0
                M = Manifest();
                return
            end

            % legacy alias
            text = opts.Text;
            mode = opts.Match;
            if strlength(text)==0 && strlength(opts.Contains)>0
                text = opts.Contains;
                mode = "contains";
            end

            idx = true(n,1);

            % exact Type filter
            if ~ismissing(opts.Type)
                idx = idx & (self.type == opts.Type);
            end

            % time window
            if ~isnat(opts.StartTime)
                idx = idx & (self.timestamp >= opts.StartTime);
            end
            if ~isnat(opts.EndTime)
                idx = idx & (self.timestamp <= opts.EndTime);
            end

            % parameter presence/value
            if strlength(opts.ParamName) > 0
                p = char(opts.ParamName);
                if ~isempty(opts.ParamValue)
                    idx = idx & cellfun(@(s) ~isempty(s) && isfield(s, p) && isequal(s.(p), opts.ParamValue), self.parameterValues);
                else
                    idx = idx & cellfun(@(s) ~isempty(s) && isfield(s, p), self.parameterValues);
                end
            end

            % text matching across selected fields
            if strlength(text) > 0
                fields = opts.Fields(ismember(opts.Fields, ["type","description","notes"]));
                if isempty(fields)
                    fields = ["type","description","notes"];
                end
                fmatch = false(n,1);
                for k = 1:n
                    hit = false;
                    for f = fields
                        switch f
                            case "type",        val = self.type(k);
                            case "description", val = self.description(k);
                            case "notes",       val = self.notes(k);
                        end
                        if Manifest.matchText(val, text, mode, opts.IgnoreCase)
                            hit = true; break
                        end
                    end
                    fmatch(k) = hit;
                end
                idx = idx & fmatch;
            end

            M = Manifest();
            M.type = self.type(idx);
            M.description = self.description(idx);
            M.timestamp = self.timestamp(idx);
            M.notes = self.notes(idx);
            M.parameterValues = self.parameterValues(idx);
        end

        function n = count(self)
            % n = count(self)
            %
            % Return number of entries.

            arguments
                self (1,1) Manifest
            end

            n = numel(self.type);
        end

        function e = latest(self)
            % e = latest(self)
            %
            % Return the most recent entry as a struct or empty if none.

            arguments
                self (1,1) Manifest
            end

            if isempty(self.type)
                e = struct([]);
                return
            end
            [~, idx] = max(self.timestamp);
            e = struct('type', self.type(idx), ...
                       'description', self.description(idx), ...
                       'timestamp', self.timestamp(idx), ...
                       'notes', self.notes(idx), ...
                       'parameterValues', self.parameterValues{idx});
        end

        function tf = isempty(self)
            % tf = isempty(self)
            %
            % True when the manifest has zero entries.
            arguments
                self (1,1) Manifest
            end
            tf = isempty(self.type);
        end

        function disp(self)
            % disp(self)
            %
            % Custom display: prints a brief summary and table.
            arguments
                self (1,1) Manifest
            end
            n = numel(self.type);
            fprintf('Manifest: %d entries\n', n);
            self.show;
        end
    end

    methods (Access = private)
        function printOnAdd(self, idx)
            % printOnAdd(self, idx)
            arguments
                self (1,1) Manifest
                idx (1,1) double {mustBeInteger, mustBePositive}
            end
            v = self.verbosity;
            if v <= 0
                return
            end

            tstr = char(string(self.timestamp(idx),"yyyy-MM-dd HH:mm:ss"));
            ty   = char(self.type(idx));
            ds   = char(self.description(idx));

            switch v
                case 1
                    fprintf('[Manifest] #%d %s — %s\n', idx, ty, ds);
                case 2
                    note = char(self.notes(idx));
                    if strlength(self.notes(idx))>0
                        fprintf('[Manifest] #%d [%s] %s — %s | notes: %s\n', idx, tstr, ty, ds, note);
                    else
                        fprintf('[Manifest] #%d [%s] %s — %s\n', idx, tstr, ty, ds);
                    end
                otherwise % v >= 3
                    fprintf('[Manifest] #%d [%s] %s — %s\n', idx, tstr, ty, ds);
                    if strlength(self.notes(idx))>0
                        fprintf('  notes: %s\n', char(self.notes(idx)));
                    end
                    s = self.parameterValues{idx};
                    if ~isempty(s)
                        f = fieldnames(s);
                        for k = 1:numel(f)
                            fprintf('  param.%s = %s\n', f{k}, Manifest.val2str(s.(f{k})));
                        end
                    end
            end
        end
    end

    methods (Static, Access = private)
        function tf = matchText(str, pat, mode, ignoreCase)
            % tf = matchText(str, pat, mode, ignoreCase)
            arguments
                str (1,1) string
                pat (1,1) string
                mode (1,1) string
                ignoreCase (1,1) logical
            end

            switch mode
                case "regex"
                    if ignoreCase
                        tf = ~isempty(regexp(str, pat, 'once', 'ignorecase'));
                    else
                        tf = ~isempty(regexp(str, pat, 'once'));
                    end
                case "contains"
                    tf = contains(str, pat, 'IgnoreCase', ignoreCase);
                case "starts"
                    tf = startsWith(str, pat, 'IgnoreCase', ignoreCase);
                case "ends"
                    tf = endsWith(str, pat, 'IgnoreCase', ignoreCase);
                case "exact"
                    if ignoreCase
                        tf = strcmpi(str, pat);
                    else
                        tf = strcmp(str, pat);
                    end
                otherwise
                    tf = false;
            end
        end

        function s = val2str(v)
            if isstring(v)
                s = char(strjoin(v, ","));
            elseif ischar(v)
                s = v;
            elseif islogical(v) && isscalar(v)
                s = char(string(v));
            elseif isnumeric(v) && isscalar(v)
                s = num2str(v);
            elseif isnumeric(v)
                s = mat2str(v);
            elseif iscell(v)
                sz = size(v);
                s = sprintf('cell[%dx%d]', sz(1), sz(2));
            elseif isstruct(v)
                s = 'struct';
            else
                s = class(v);
            end
        end
    end
end
