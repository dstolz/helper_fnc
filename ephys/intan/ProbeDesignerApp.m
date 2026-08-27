classdef ProbeDesignerApp < handle
%ProbeDesignerApp  Guided probeinterface front-end for building KS4 probe .json.
%   ProbeDesignerApp(APP) opens a modal designer that lets the user pick a
%   manufactured probe from the probeinterface library or generate a standard
%   geometry (linear / multi-column / tetrode), wire its contacts to Intan
%   amplifier channels, and Save the result as a Kilosort4 probe .json in the
%   app's probe folder. probeinterface is driven through APP.runProbeTool
%   (probe_tool.py in the sorting conda env); the app itself only ever sees the
%   plain KS4 JSON this designer writes, so the whole downstream pipeline is
%   unchanged.
%
%   APP is the parent IntanKilosortApp (supplies the Python/conda config via
%   runProbeTool, the target probe folder via ProbeFolderField, and
%   refreshProbeList on save). Optional NChanHint is the selected dataset's
%   channel count, used only for a soft channel-count warning.
%
%   See also IntanKilosortApp.onDesignProbe, IntanKilosortApp.runProbeTool.

    properties
        App                          % parent IntanKilosortApp
        NChanHint (1,1) double = NaN

        Fig
        % Source selection
        SourceDrop
        LibPanel
        GenPanel
        ManufacturerDrop
        ProbeDrop
        LoadListButton
        FetchButton
        GenTypeDrop
        LinPanel
        McPanel
        TetPanel
        NumElecField
        YpitchLinField
        NumColsField
        NumPerColField
        XpitchField
        YpitchColField
        TetRadiusField
        BuildButton
        % Preview + wiring
        PreviewAxes
        WiringTable
        IdentityButton
        ReverseButton
        LoadMapButton
        LabelChk
        % Meta + actions
        NameField
        NotesField
        StatusLabel
        SaveButton
        CancelButton

        % Cached library listing (struct array: manufacturer, probes)
        LibList = struct('manufacturer', {}, 'probes', {})
        % Geometry from the last Fetch/Build (contact order)
        Built = struct('xc', [], 'yc', [], 'kcoords', [], 'n_chan', 0, 'n', 0)
        Wiring double = []   % 1-based device channel per contact
    end

    methods
        function obj = ProbeDesignerApp(app, nChanHint)
            arguments
                app
                nChanHint (1,1) double = NaN
            end
            obj.App = app;
            obj.NChanHint = nChanHint;
            obj.build();
            obj.onSourceChanged();
            obj.onGenTypeChanged();
            if nargout == 0
                clear obj
            end
        end
    end

    methods (Access = private)
        function build(obj)
            obj.Fig = uifigure('Name', 'Probe designer (probeinterface)', ...
                'Position', [100 100 900 640], 'Resize', 'off');
            g = uigridlayout(obj.Fig, [5 1]);
            g.RowHeight = {'fit', 'fit', '1x', 'fit', 'fit'};
            g.Padding = [10 10 10 10];

            % ---- Row 1: source selector ----
            srow = uigridlayout(g, [1 2]);
            srow.Layout.Row = 1;
            srow.ColumnWidth = {'fit', 260};
            srow.Padding = [0 0 0 0];
            uilabel(srow, 'Text', 'Source:');
            obj.SourceDrop = uidropdown(srow, ...
                'Items', {'From probeinterface library', 'Generate geometry'}, ...
                'ItemsData', {'library', 'generate'}, ...
                'ValueChangedFcn', @(~,~) obj.onSourceChanged());

            % ---- Row 2: parameter cards (library / generate, toggled) ----
            card = uigridlayout(g, [1 1]);
            card.Layout.Row = 2;
            card.Padding = [0 0 0 0];

            % Library panel
            obj.LibPanel = uipanel(card, 'BorderType', 'none');
            obj.LibPanel.Layout.Row = 1; obj.LibPanel.Layout.Column = 1;
            lg = uigridlayout(obj.LibPanel, [1 6]);
            lg.ColumnWidth = {'fit', 150, 'fit', '1x', 'fit', 'fit'};
            lg.Padding = [0 0 0 0];
            uilabel(lg, 'Text', 'Manufacturer:');
            obj.ManufacturerDrop = uidropdown(lg, 'Items', {'(load list)'}, ...
                'ValueChangedFcn', @(~,~) obj.onManufacturerChanged());
            uilabel(lg, 'Text', 'Probe:');
            obj.ProbeDrop = uidropdown(lg, 'Items', {}, 'Editable', 'on');
            obj.LoadListButton = uibutton(lg, 'Text', 'Load list', ...
                'ButtonPushedFcn', @(~,~) obj.onLoadList());
            obj.FetchButton = uibutton(lg, 'Text', 'Fetch', ...
                'ButtonPushedFcn', @(~,~) obj.onFetch());

            % Generate panel: a type dropdown + one visible param sub-panel + Build.
            obj.GenPanel = uipanel(card, 'BorderType', 'none');
            obj.GenPanel.Layout.Row = 1; obj.GenPanel.Layout.Column = 1;
            gg = uigridlayout(obj.GenPanel, [1 4]);
            gg.ColumnWidth = {'fit', 130, '1x', 'fit'};
            gg.Padding = [0 0 0 0];
            uilabel(gg, 'Text', 'Type:');
            obj.GenTypeDrop = uidropdown(gg, ...
                'Items', {'Linear', 'Multi-column', 'Tetrode'}, ...
                'ValueChangedFcn', @(~,~) obj.onGenTypeChanged());

            paramCard = uigridlayout(gg, [1 1]);   % holds the 3 param panels (toggled)
            paramCard.Layout.Column = 3; paramCard.Padding = [0 0 0 0];

            obj.LinPanel = uipanel(paramCard, 'BorderType', 'none');
            obj.LinPanel.Layout.Row = 1; obj.LinPanel.Layout.Column = 1;
            lgp = uigridlayout(obj.LinPanel, [1 4]);
            lgp.ColumnWidth = {'fit', 70, 'fit', 70}; lgp.Padding = [0 0 0 0];
            uilabel(lgp, 'Text', 'num_elec:');
            obj.NumElecField = uieditfield(lgp, 'numeric', 'Value', 16, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
            uilabel(lgp, 'Text', 'ypitch:');
            obj.YpitchLinField = uieditfield(lgp, 'numeric', 'Value', 20, 'Limits', [0 Inf]);

            obj.McPanel = uipanel(paramCard, 'BorderType', 'none');
            obj.McPanel.Layout.Row = 1; obj.McPanel.Layout.Column = 1;
            mgp = uigridlayout(obj.McPanel, [1 8]);
            mgp.ColumnWidth = {'fit', 55, 'fit', 55, 'fit', 55, 'fit', 55}; mgp.Padding = [0 0 0 0];
            uilabel(mgp, 'Text', 'columns:');
            obj.NumColsField = uieditfield(mgp, 'numeric', 'Value', 2, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
            uilabel(mgp, 'Text', 'per col:');
            obj.NumPerColField = uieditfield(mgp, 'numeric', 'Value', 8, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
            uilabel(mgp, 'Text', 'xpitch:');
            obj.XpitchField = uieditfield(mgp, 'numeric', 'Value', 22, 'Limits', [0 Inf]);
            uilabel(mgp, 'Text', 'ypitch:');
            obj.YpitchColField = uieditfield(mgp, 'numeric', 'Value', 20, 'Limits', [0 Inf]);

            obj.TetPanel = uipanel(paramCard, 'BorderType', 'none');
            obj.TetPanel.Layout.Row = 1; obj.TetPanel.Layout.Column = 1;
            tgp = uigridlayout(obj.TetPanel, [1 2]);
            tgp.ColumnWidth = {'fit', 70}; tgp.Padding = [0 0 0 0];
            uilabel(tgp, 'Text', 'radius r:');
            obj.TetRadiusField = uieditfield(tgp, 'numeric', 'Value', 10, 'Limits', [0 Inf]);

            obj.BuildButton = uibutton(gg, 'Text', 'Build', ...
                'ButtonPushedFcn', @(~,~) obj.onBuild());

            % ---- Row 3: preview + wiring table ----
            mid = uigridlayout(g, [1 2]);
            mid.Layout.Row = 3;
            mid.ColumnWidth = {'1x', 320};
            mid.Padding = [0 0 0 0];
            obj.PreviewAxes = uiaxes(mid);
            title(obj.PreviewAxes, 'Contact arrangement');
            xlabel(obj.PreviewAxes, 'x (\mum)'); ylabel(obj.PreviewAxes, 'y (\mum)');

            wp = uipanel(mid, 'Title', 'Wiring: contact -> Intan channel');
            wg = uigridlayout(wp, [2 1]);
            wg.RowHeight = {'1x', 'fit'};
            obj.WiringTable = uitable(wg);
            obj.WiringTable.ColumnName = {'Contact', 'x', 'y', 'Shank', 'Device ch'};
            obj.WiringTable.ColumnEditable = [false false false false true];
            obj.WiringTable.ColumnWidth = {55, 45, 45, 45, 75};
            obj.WiringTable.CellEditCallback = @(~,evt) obj.onWiringEdited(evt);
            presets = uigridlayout(wg, [1 4]);
            presets.Padding = [0 0 0 0];
            obj.IdentityButton = uibutton(presets, 'Text', 'Identity', ...
                'ButtonPushedFcn', @(~,~) obj.applyPreset('identity'));
            obj.ReverseButton = uibutton(presets, 'Text', 'Reverse', ...
                'ButtonPushedFcn', @(~,~) obj.applyPreset('reverse'));
            obj.LoadMapButton = uibutton(presets, 'Text', 'Load map...', ...
                'ButtonPushedFcn', @(~,~) obj.onLoadMap());
            obj.LabelChk = uicheckbox(presets, 'Text', 'Label ch', 'Value', false, ...
                'ValueChangedFcn', @(~,~) obj.renderPreview());

            % ---- Row 4: name / notes ----
            meta = uigridlayout(g, [1 4]);
            meta.Layout.Row = 4;
            meta.ColumnWidth = {'fit', 200, 'fit', '1x'};
            meta.Padding = [0 0 0 0];
            uilabel(meta, 'Text', 'Name:');
            obj.NameField = uieditfield(meta, 'text', 'Placeholder', 'probe file name (no extension)');
            uilabel(meta, 'Text', 'Notes:');
            obj.NotesField = uieditfield(meta, 'text', 'Placeholder', 'optional');

            % ---- Row 5: status + actions ----
            act = uigridlayout(g, [1 3]);
            act.Layout.Row = 5;
            act.ColumnWidth = {'1x', 'fit', 'fit'};
            act.Padding = [0 0 0 0];
            obj.StatusLabel = uilabel(act, 'Text', ...
                'Pick a source, then Fetch/Build to preview.', 'WordWrap', 'on');
            obj.SaveButton = uibutton(act, 'Text', 'Save to probe folder', ...
                'Enable', 'off', 'ButtonPushedFcn', @(~,~) obj.onSave());
            obj.CancelButton = uibutton(act, 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~,~) obj.onCancel());
        end

        % ---- source / type toggling -------------------------------------
        function onSourceChanged(obj)
            isLib = strcmp(obj.SourceDrop.Value, 'library');
            obj.LibPanel.Visible = onoff(isLib);
            obj.GenPanel.Visible = onoff(~isLib);
        end

        function onGenTypeChanged(obj)
            t = obj.GenTypeDrop.Value;
            obj.LinPanel.Visible = onoff(strcmp(t, 'Linear'));
            obj.McPanel.Visible  = onoff(strcmp(t, 'Multi-column'));
            obj.TetPanel.Visible = onoff(strcmp(t, 'Tetrode'));
        end

        % ---- library ----------------------------------------------------
        function onLoadList(obj)
            obj.setStatus('Loading probeinterface library (first time may download)...', false);
            drawnow;
            try
                lst = obj.App.runProbeTool("list-library");
            catch ME
                obj.setStatus(ME.message, true); return
            end
            if iscell(lst)                       % non-uniform -> cell of structs
                lst = [lst{:}];
            end
            if ~isstruct(lst) || ~isfield(lst, 'manufacturer')
                obj.setStatus('Unexpected library response.', true); return
            end
            obj.LibList = lst;
            mans = string({lst.manufacturer});
            obj.ManufacturerDrop.Items = cellstr(mans);
            obj.ManufacturerDrop.Value = obj.ManufacturerDrop.Items{1};
            obj.onManufacturerChanged();
            obj.setStatus(sprintf('Loaded %d manufacturers.', numel(mans)), false);
        end

        function onManufacturerChanged(obj)
            if isempty(obj.LibList); return; end
            m = string(obj.ManufacturerDrop.Value);
            idx = find(string({obj.LibList.manufacturer}) == m, 1);
            probes = {};
            if ~isempty(idx)
                p = obj.LibList(idx).probes;
                if iscell(p); probes = cellstr(string(p)); elseif ~isempty(p); probes = cellstr(string(p)); end
            end
            if isempty(probes)
                obj.ProbeDrop.Items = {};
                obj.ProbeDrop.Value = '';
            else
                obj.ProbeDrop.Items = probes;
                obj.ProbeDrop.Value = probes{1};
            end
        end

        function onFetch(obj)
            man = strtrim(string(obj.ManufacturerDrop.Value));
            prb = strtrim(string(obj.ProbeDrop.Value));
            if man == "" || prb == "" || startsWith(man, "(")
                obj.setStatus('Choose a manufacturer and probe first (Load list).', true); return
            end
            outPath = string(tempname) + ".json";
            obj.setStatus(sprintf('Fetching %s / %s ...', man, prb), false); drawnow;
            try
                obj.App.runProbeTool("get-library", man, prb, outPath, "--name", prb);
                d = jsondecode(fileread(outPath));
            catch ME
                obj.setStatus(ME.message, true); return
            end
            if obj.NameField.Value == ""
                obj.NameField.Value = char(matlab.lang.makeValidName(prb));
            end
            obj.loadBuilt(d, sprintf('Fetched %s (%d contacts).', prb, numel(d.chanMap)));
        end

        % ---- generate ---------------------------------------------------
        function onBuild(obj)
            t = obj.GenTypeDrop.Value;
            spec = struct();
            switch t
                case 'Linear'
                    spec.type = 'linear';
                    spec.params = struct('num_elec', obj.NumElecField.Value, ...
                                         'ypitch', obj.YpitchLinField.Value);
                    defName = sprintf('linear%d', round(obj.NumElecField.Value));
                case 'Multi-column'
                    spec.type = 'multi_columns';
                    spec.params = struct('num_columns', obj.NumColsField.Value, ...
                        'num_contact_per_column', obj.NumPerColField.Value, ...
                        'xpitch', obj.XpitchField.Value, 'ypitch', obj.YpitchColField.Value);
                    defName = sprintf('mc%dx%d', round(obj.NumColsField.Value), round(obj.NumPerColField.Value));
                case 'Tetrode'
                    spec.type = 'tetrode';
                    spec.params = struct('r', obj.TetRadiusField.Value);
                    defName = 'tetrode';
                otherwise
                    obj.setStatus('Unknown geometry type.', true); return
            end
            spec.name = char(obj.NameField.Value);
            spec.notes = char(obj.NotesField.Value);

            specPath = string(tempname) + ".json";
            outPath  = string(tempname) + ".json";
            try
                obj.writeJsonFile(spec, specPath);
                obj.App.runProbeTool("generate", specPath, outPath);
                d = jsondecode(fileread(outPath));
            catch ME
                obj.setStatus(ME.message, true); return
            end
            if obj.NameField.Value == ""
                obj.NameField.Value = defName;
            end
            obj.loadBuilt(d, sprintf('Built %s (%d contacts).', t, numel(d.chanMap)));
        end

        % ---- shared: load a KS4 dict into the designer ------------------
        function loadBuilt(obj, d, statusMsg)
            n = numel(d.chanMap);
            obj.Built.xc = double(d.xc(:))';
            obj.Built.yc = double(d.yc(:))';
            if isfield(d, 'kcoords') && numel(d.kcoords) == n
                obj.Built.kcoords = double(d.kcoords(:))';
            else
                obj.Built.kcoords = zeros(1, n);
            end
            obj.Built.n = n;
            if isfield(d, 'n_chan'); obj.Built.n_chan = double(d.n_chan); else; obj.Built.n_chan = n; end
            if isfield(d, 'notes') && obj.NotesField.Value == ""
                obj.NotesField.Value = char(string(d.notes));
            end
            obj.Wiring = double(d.chanMap(:))' + 1;   % show 1-based device channels
            obj.fillWiringTable();
            obj.renderPreview();
            obj.SaveButton.Enable = 'on';
            hint = "";
            if ~isnan(obj.NChanHint) && obj.NChanHint ~= n
                hint = sprintf('  (note: dataset has %d channels)', obj.NChanHint);
            end
            obj.setStatus([statusMsg, char(hint)], false);
        end

        function fillWiringTable(obj)
            n = obj.Built.n;
            obj.WiringTable.Data = [ (1:n)', obj.Built.xc', obj.Built.yc', ...
                                     obj.Built.kcoords', obj.Wiring' ];
        end

        function onWiringEdited(obj, evt)
            r = evt.Indices(1); c = evt.Indices(2);
            if c ~= 5; return; end
            v = evt.NewData;
            if ~isscalar(v) || ~isfinite(v) || v < 1 || v ~= round(v)
                obj.WiringTable.Data(r, 5) = evt.PreviousData;   % reject
                obj.setStatus('Device channel must be a positive integer.', true);
                return
            end
            obj.Wiring(r) = v;
            obj.renderPreview();
        end

        function applyPreset(obj, kind)
            n = obj.Built.n;
            if n == 0; return; end
            switch kind
                case 'identity'; obj.Wiring = 1:n;
                case 'reverse';  obj.Wiring = n:-1:1;
            end
            obj.fillWiringTable();
            obj.renderPreview();
        end

        function onLoadMap(obj)
            n = obj.Built.n;
            if n == 0; obj.setStatus('Build/fetch a probe first.', true); return; end
            [f, p] = uigetfile({'*.csv;*.txt;*.json', 'Channel map (*.csv,*.txt,*.json)'}, ...
                'Load device-channel map (1-based, one per contact)');
            if isequal(f, 0); return; end
            file = fullfile(p, f);
            try
                [~, ~, ext] = fileparts(file);
                if strcmpi(ext, '.json')
                    v = jsondecode(fileread(file));
                    if isstruct(v) && isfield(v, 'chanMap'); v = double(v.chanMap(:)') + 1; else; v = double(v(:))'; end
                else
                    v = readmatrix(file);
                    v = double(v(:))';
                end
            catch ME
                obj.setStatus(['Could not read map: ' ME.message], true); return
            end
            if numel(v) ~= n
                obj.setStatus(sprintf('Map has %d entries; expected %d.', numel(v), n), true); return
            end
            obj.Wiring = v;
            obj.fillWiringTable();
            obj.renderPreview();
            obj.setStatus(sprintf('Loaded wiring from %s.', f), false);
        end

        % ---- preview ----------------------------------------------------
        function renderPreview(obj)
            ax = obj.PreviewAxes; cla(ax); hold(ax, 'on');
            n = obj.Built.n;
            if n == 0; hold(ax, 'off'); return; end
            xc = obj.Built.xc; yc = obj.Built.yc; kc = obj.Built.kcoords;
            shanks = unique(kc);
            cmap = lines(max(1, numel(shanks)));
            for s = 1:numel(shanks)
                m = kc == shanks(s);
                scatter(ax, xc(m), yc(m), 40, cmap(s, :), 'filled', ...
                    'DisplayName', sprintf('shank %g', shanks(s)));
            end
            if obj.LabelChk.Value
                for i = 1:n
                    text(ax, xc(i), yc(i), sprintf('  %d', obj.Wiring(i)), ...
                        'FontSize', 7, 'Parent', ax);
                end
            end
            hold(ax, 'off'); axis(ax, 'equal'); grid(ax, 'on');
            if numel(shanks) > 1; legend(ax, 'Location', 'eastoutside'); else; legend(ax, 'off'); end
        end

        % ---- save / cancel ----------------------------------------------
        function onSave(obj)
            if obj.Built.n == 0; obj.setStatus('Nothing to save.', true); return; end
            nm = strtrim(string(obj.NameField.Value));
            if nm == ""; obj.setStatus('Enter a name for the probe file.', true); return; end
            nm = regexprep(nm, '[^\w\-.]', '_');       % filesystem-safe
            if endsWith(lower(nm), ".json"); nm = extractBefore(nm, strlength(nm) - 4); end

            folder = string(obj.App.ProbeFolderField.Value);
            if folder == "" || ~isfolder(folder)
                folder = string(obj.App.defaultProbeFolder());
            end
            if ~isfolder(folder); mkdir(folder); end
            outPath = fullfile(folder, nm + ".json");

            if isfile(outPath)
                sel = uiconfirm(obj.Fig, sprintf('%s exists. Overwrite?', nm + ".json"), ...
                    'Overwrite probe', 'Options', {'Overwrite', 'Cancel'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(sel, 'Overwrite'); return; end
            end

            w = obj.Wiring(:)';
            if any(~isfinite(w)) || any(w < 1) || any(w ~= round(w))
                obj.setStatus('Wiring has invalid entries.', true); return
            end
            if numel(unique(w)) ~= numel(w)
                sel = uiconfirm(obj.Fig, ...
                    'Two or more contacts map to the same device channel. Save anyway?', ...
                    'Duplicate wiring', 'Options', {'Save anyway', 'Cancel'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(sel, 'Save anyway'); return; end
            end

            chanMap = w - 1;                             % back to 0-based KS4
            ks4 = struct();
            ks4.notes   = char(obj.NotesField.Value);
            ks4.chanMap = chanMap;
            ks4.xc      = obj.Built.xc;
            ks4.yc      = obj.Built.yc;
            ks4.kcoords = obj.Built.kcoords;
            ks4.n_chan  = max([obj.Built.n_chan, numel(chanMap), max(chanMap) + 1]);

            try
                obj.writeJsonFile(ks4, outPath);
            catch ME
                obj.setStatus(['Write failed: ' ME.message], true); return
            end

            try
                obj.App.refreshProbeList();
            catch
                % non-fatal: the file is written; the list will refresh next time
            end
            delete(obj.Fig);
        end

        function onCancel(obj)
            delete(obj.Fig);
        end

        % ---- helpers ----------------------------------------------------
        function setStatus(obj, msg, isError)
            obj.StatusLabel.Text = char(msg);
            if nargin > 2 && isError
                obj.StatusLabel.FontColor = [0.7 0 0];
            else
                obj.StatusLabel.FontColor = [0 0 0];
            end
        end

        function writeJsonFile(~, s, file)
            try
                txt = jsonencode(s, 'PrettyPrint', true);
            catch
                txt = jsonencode(s);
            end
            fid = fopen(file, 'w');
            if fid < 0
                error('ProbeDesignerApp:WriteFailed', 'Could not write %s', file);
            end
            fwrite(fid, txt, 'char'); fclose(fid);
        end
    end
end


function s = onoff(tf)
if tf; s = 'on'; else; s = 'off'; end
end
