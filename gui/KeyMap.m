classdef KeyMap < handle
    % KeyMap  Manage and attach keyboard shortcuts to a GUI, with a help dialog.
    %   KeyMap holds a collection of KeyBinding objects (composition), attaches
    %   them to a target figure/uifigure/app via WindowKeyPressFcn (which works
    %   for both classic figures and App Designer uifigures), and auto-generates
    %   a polished modal "keyboard shortcuts" dialog (opened with a hotkey,
    %   default F1).
    %
    %   It is framework-agnostic about the target: pass a classic figure, a
    %   uifigure, any graphics child of one, or an app object exposing a figure
    %   property (UIFigure, Fig, or FigureHandle).
    %
    %   Existing key handlers are preserved: the previous WindowKeyPressFcn is
    %   chained when no binding matches, and restored on detach().
    %
    %   Usage:
    %     km = KeyMap(app);   % app = a uifigure, a figure, or an app object
    %     km.add('s', @() app.onSave(), Description="Save session", ...
    %            Category="File", Modifiers="control");
    %     km.add('rightarrow', @() app.next(), Description="Next image", ...
    %            Category="Navigation");
    %     km.attach();        % F1 now shows the shortcuts dialog
    %
    %   See also KEYBINDING.

    properties
        Bindings    (1,:) KeyBinding = KeyBinding.empty   % the managed bindings
        Target                                            % original handle/app passed in
        Fig         matlab.ui.Figure                      % resolved figure the callback attaches to
        HelpKey     (1,1) string  = "f1"                  % key that opens the help dialog
        Title       (1,1) string  = "Keyboard Shortcuts"  % help dialog title
        PrevKeyFcn                = []                    % previous WindowKeyPressFcn (for chaining/restore)
        Attached    (1,1) logical = false
    end

    properties (Constant, Access = private)
        HelpCategory = "Help"
    end

    methods
        function obj = KeyMap(target, opts)
            arguments
                target
                opts.HelpKey (1,1) string = "f1"
                opts.Title   (1,1) string = "Keyboard Shortcuts"
            end
            obj.Target  = target;
            obj.HelpKey = opts.HelpKey;
            obj.Title   = opts.Title;
        end

        function kb = add(obj, key, callback, opts)
            % ADD  Create and register a KeyBinding. Returns the new binding.
            arguments
                obj
                key
                callback   (1,1) function_handle
                opts.Modifiers          string  = string.empty
                opts.Description (1,1)  string  = ""
                opts.Category    (1,1)  string  = "General"
                opts.Enabled     (1,1)  logical = true
            end
            kb = KeyBinding(key, callback, ...
                Modifiers   = opts.Modifiers, ...
                Description = opts.Description, ...
                Category    = opts.Category, ...
                Enabled     = opts.Enabled);
            obj.addBinding(kb);
        end

        function addBinding(obj, kb)
            % ADDBINDING  Register a pre-built KeyBinding (warns on duplicate combo).
            arguments
                obj
                kb (1,1) KeyBinding
            end
            if obj.findIndex(kb.Key, kb.Modifiers) > 0
                warning('KeyMap:duplicateBinding', ...
                    'A binding for "%s" already exists; adding anyway.', kb.label());
            end
            obj.Bindings(end+1) = kb;
        end

        function remove(obj, key, opts)
            % REMOVE  Drop binding(s) matching KEY (and optional Modifiers).
            arguments
                obj
                key
                opts.Modifiers string = string.empty
            end
            probe = KeyBinding(key, @()[], Modifiers=opts.Modifiers);
            keep = true(1, numel(obj.Bindings));
            for i = 1:numel(obj.Bindings)
                if strcmpi(obj.Bindings(i).Key, probe.Key) && ...
                        isequal(obj.Bindings(i).Modifiers, probe.Modifiers)
                    keep(i) = false;
                end
            end
            obj.Bindings = obj.Bindings(keep);
        end

        function attach(obj)
            % ATTACH  Resolve the target figure and start handling key presses.
            obj.Fig = obj.resolveFigure(obj.Target);

            % Auto-register the help binding once.
            if obj.findIndex(obj.helpBindingKey(), string.empty) <= 0
                obj.addBinding(KeyBinding(obj.HelpKey, @(~,~) obj.showHelp(), ...
                    Description = "Show this shortcuts list", ...
                    Category    = obj.HelpCategory));
            end

            % Preserve any existing handler for chaining/restore, then take over.
            obj.PrevKeyFcn = obj.Fig.WindowKeyPressFcn;
            obj.Fig.WindowKeyPressFcn = @obj.dispatch;
            obj.Attached = true;
        end

        function detach(obj)
            % DETACH  Restore the previous key handler and stop dispatching.
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                obj.Fig.WindowKeyPressFcn = obj.PrevKeyFcn;
            end
            obj.Attached = false;
        end

        function dispatch(obj, src, evt)
            % DISPATCH  WindowKeyPressFcn entry point: run first matching binding.
            for i = 1:numel(obj.Bindings)
                if obj.Bindings(i).matches(evt)
                    obj.Bindings(i).execute(src, evt);
                    return;
                end
            end
            % No match: chain to whatever handler was there before us.
            obj.callPrev(src, evt);
        end

        function showHelp(obj)
            % SHOWHELP  Open (or raise) a modal dialog listing all shortcuts.
            figTag = "KeyMapHelp_" + string(class(obj.Target));

            existing = findall(0, 'Type','figure', 'Tag', char(figTag));
            if ~isempty(existing) && isvalid(existing(1))
                figure(existing(1));
                return;
            end

            rows = obj.helpRows();

            dlgW = 560; dlgH = 420;
            pos = [100 100 dlgW dlgH];
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                fp = obj.Fig.Position;
                pos(1) = fp(1) + (fp(3)-dlgW)/2;
                pos(2) = fp(2) + (fp(4)-dlgH)/2;
            end

            dlg = uifigure( ...
                'Name', char(obj.Title), ...
                'Position', pos, ...
                'Tag', char(figTag), ...
                'WindowStyle', 'modal', ...
                'WindowKeyPressFcn', @(s,e) closeOnKey(e));

            uitable(dlg, ...
                'Data', rows, ...
                'ColumnName', {'Category','Shortcut','Action'}, ...
                'ColumnEditable', false(1,3), ...
                'ColumnWidth', {120, 110, 'auto'}, ...
                'RowName', {}, ...
                'Units', 'normalized', ...
                'Position', [0.03 0.13 0.94 0.84]);

            uibutton(dlg, ...
                'Text', 'Close', ...
                'Position', [dlgW-110 15 90 30], ...
                'ButtonPushedFcn', @(s,e) delete(dlg));

            function closeOnKey(e)
                if any(strcmp(e.Key, {'escape','return'}))
                    delete(dlg);
                end
            end
        end
    end

    methods (Access = private)
        function callPrev(obj, src, evt)
            fcn = obj.PrevKeyFcn;
            if isempty(fcn), return; end
            try
                if isa(fcn, 'function_handle')
                    fcn(src, evt);
                elseif iscell(fcn) && ~isempty(fcn)
                    fcn{1}(src, evt, fcn{2:end});
                end
            catch err
                warning('KeyMap:prevHandlerError', ...
                    'Chained key handler failed: %s', err.message);
            end
        end

        function idx = findIndex(obj, key, mods)
            % Index of a binding with matching key + modifier set, else 0.
            probe = KeyBinding(key, @()[], Modifiers=mods);
            idx = 0;
            for i = 1:numel(obj.Bindings)
                if strcmpi(obj.Bindings(i).Key, probe.Key) && ...
                        isequal(obj.Bindings(i).Modifiers, probe.Modifiers)
                    idx = i;
                    return;
                end
            end
        end

        function k = helpBindingKey(obj)
            % Normalized form of HelpKey for de-duplication lookups.
            k = KeyBinding(obj.HelpKey, @()[]).Key;
        end

        function rows = helpRows(obj)
            % Build sorted {Category, Shortcut, Action} cell array of enabled bindings.
            n = numel(obj.Bindings);
            cat = strings(n,1); sc = strings(n,1); act = strings(n,1);
            keep = false(n,1);
            for i = 1:n
                if ~obj.Bindings(i).Enabled, continue; end
                keep(i) = true;
                cat(i) = obj.Bindings(i).Category;
                sc(i)  = obj.Bindings(i).label();
                act(i) = obj.Bindings(i).Description;
            end
            cat = cat(keep); sc = sc(keep); act = act(keep);

            [~, order] = sortrows([cat, sc]);
            rows = [cellstr(cat(order)), cellstr(sc(order)), cellstr(act(order))];
        end

        function fig = resolveFigure(~, target)
            % Framework-agnostic resolution of TARGET to a figure handle.
            if isa(target, 'matlab.ui.Figure')
                fig = target;                              % classic figure or uifigure
            elseif isgraphics(target)
                fig = ancestor(target, 'figure');          % a child graphics object
            elseif isobject(target) && isprop(target, 'UIFigure')
                fig = target.UIFigure;                     % App Designer app
            elseif isobject(target) && isprop(target, 'Fig')
                fig = target.Fig;                          % e.g. ECMAnalysisApp
            elseif isobject(target) && isprop(target, 'FigureHandle')
                fig = target.FigureHandle;                 % e.g. InteractiveRotator
            else
                error('KeyMap:unresolvedTarget', ...
                    ['Cannot resolve a figure from the target. Pass a figure, a ', ...
                     'uifigure, a graphics child, or an app exposing UIFigure/Fig/FigureHandle.']);
            end
            if isempty(fig) || ~isvalid(fig)
                error('KeyMap:invalidFigure', 'Resolved target figure is empty or invalid.');
            end
        end
    end
end
