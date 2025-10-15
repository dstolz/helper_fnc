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
    %   m2 = m.search(Contains="bandpass");
    %   n  = m.count;
    %   e  = m.latest;
    %
    % Notes
    %   parameterValues can be any scalar struct. Use FlattenParams to expand.
    
    properties (Access = private)
        items struct = struct('type', {}, 'description', {}, 'timestamp', {}, 'notes', {}, 'parameterValues', {})
    end

    methods
        function self = Manifest()
            % self = Manifest()
            %
            % Create an empty manifest.
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

            e = struct('type', type, ...
                       'description', description, ...
                       'timestamp', datetime('now','TimeZone','local'), ...
                       'notes', notes, ...
                       'parameterValues', parameterValues);

            if isempty(self.items)
                self.items = e;
            else
                self.items(end+1) = e; 
            end
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

            if isempty(self.items)
                T = table(string.empty(0,1), string.empty(0,1), datetime.empty(0,1), string.empty(0,1), cell.empty(0,1), ...
                          'VariableNames', {'type','description','timestamp','notes','parameterValues'});
                return
            end

            T = struct2table(self.items, 'AsArray', true);

            if opts.FlattenParams
                % Build columns for each parameter field
                pv = arrayfun(@(x) x.parameterValues, self.items, 'UniformOutput', false);
                allFields = strings(0,1);
                for k = 1:numel(pv)
                    if ~isempty(pv{k})
                        allFields = [allFields; string(fieldnames(pv{k}))]; %#ok<AGROW>
                    end
                end
                allFields = unique(allFields);

                for f = allFields.'
                    fname = char(f);
                    vals = cell(height(T),1);
                    for r = 1:height(T)
                        s = pv{r};
                        if isfield(s, fname)
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
            if isfinite(opts.MaxRows)
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
            %  Contains (string) — substring search in type/description/notes (case-insensitive)
            %  StartTime (datetime) — include entries at or after this time
            %  EndTime (datetime) — include entries at or before this time
            %  ParamName (string) — parameter field name to test
            %  ParamValue — value to match against ParamName (isequal)

            arguments
                self (1,1) Manifest
                opts.Type (1,1) string = string(missing)
                opts.Contains (1,1) string = ""
                opts.StartTime (1,1) datetime = NaT
                opts.EndTime   (1,1) datetime = NaT
                opts.ParamName (1,1) string = ""
                opts.ParamValue = []
            end

            if isempty(self.items)
                M = Manifest();
                return
            end

            idx = true(1, numel(self.items));

            if ~ismissing(opts.Type)
                idx = idx & arrayfun(@(e) e.type == opts.Type, self.items);
            end

            if strlength(opts.Contains) > 0
                pat = lower(opts.Contains);
                idx = idx & arrayfun(@(e) contains(lower(strjoin([e.type, e.description, e.notes]," ")), pat), self.items);
            end

            if ~isnat(opts.StartTime)
                idx = idx & arrayfun(@(e) e.timestamp >= opts.StartTime, self.items);
            end

            if ~isnat(opts.EndTime)
                idx = idx & arrayfun(@(e) e.timestamp <= opts.EndTime, self.items);
            end

            if strlength(opts.ParamName) > 0
                p = char(opts.ParamName);
                if ~isempty(opts.ParamValue)
                    idx = idx & arrayfun(@(e) isfield(e.parameterValues, p) && isequal(e.parameterValues.(p), opts.ParamValue), self.items);
                else
                    idx = idx & arrayfun(@(e) isfield(e.parameterValues, p), self.items);
                end
            end

            M = Manifest();
            M.items = self.items(idx);
        end

        function n = count(self)
            % n = count(self)
            %
            % Return number of entries.

            arguments
                self (1,1) Manifest
            end

            n = numel(self.items);
        end

        function e = latest(self)
            % e = latest(self)
            %
            % Return last entry struct or empty if none.

            arguments
                self (1,1) Manifest
            end

            if isempty(self.items)
                e = struct([]);
            else
                e = self.items(end);
            end
        end
    end
end
