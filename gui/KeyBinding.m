classdef KeyBinding < handle
    % KeyBinding  A single GUI key binding (key + modifiers + action).
    %   Encapsulates the properties and behavior of one keyboard shortcut:
    %   which key/modifiers trigger it, what callback runs, and how it is
    %   described in a help dialog. Used by KeyMap, which manages a collection
    %   of KeyBinding objects and attaches them to a figure or app.
    %
    %   Usage:
    %     kb = KeyBinding('s', @() disp('saved'), ...
    %                     Modifiers="control", ...
    %                     Description="Save session", ...
    %                     Category="File");
    %     if kb.matches(evt), kb.execute(src,evt); end
    %     str = kb.label();   % "Ctrl+S"
    %
    %   See also KEYMAP.

    properties
        Key         (1,:) char        % normalized key name, e.g. 'a','uparrow','return','f1'
        Modifiers   (1,:) string      % normalized/sorted subset of {'shift','control','alt','command'}
        Callback    function_handle = function_handle.empty  % action; supports @() and @(src,evt)
        Description (1,1) string  = "" % human-readable action text for the help dialog
        Category    (1,1) string  = "General"  % group heading in the help dialog
        Enabled     (1,1) logical = true        % when false, never matches and is hidden from help
    end

    methods
        function obj = KeyBinding(key, callback, opts)
            arguments
                key                     {mustBeTextScalar}
                callback   (1,1)        function_handle
                opts.Modifiers          string = string.empty
                opts.Description (1,1)  string = ""
                opts.Category    (1,1)  string = "General"
                opts.Enabled     (1,1)  logical = true
            end

            obj.Key         = KeyBinding.normalizeKey(key);
            obj.Modifiers   = KeyBinding.normalizeModifiers(opts.Modifiers);
            obj.Callback    = callback;
            obj.Description = opts.Description;
            obj.Category    = opts.Category;
            obj.Enabled     = opts.Enabled;
        end

        function tf = matches(obj, evt)
            % MATCHES  True when key-press event EVT triggers this binding.
            %   Compares the key name (case-insensitive) and the modifier set
            %   (order-independent), and requires the binding to be enabled.
            tf = false;
            if ~obj.Enabled, return; end
            if ~strcmpi(evt.Key, obj.Key), return; end

            evtMods = KeyBinding.normalizeModifiers(evt.Modifier);
            tf = isequal(evtMods, obj.Modifiers);
        end

        function execute(obj, src, evt)
            % EXECUTE  Invoke the callback, matching its declared arity.
            %   Calls @()-style handlers with no arguments and @(src,evt)-style
            %   handlers with the event data. A failing handler is reported as a
            %   warning rather than thrown, so one bad binding cannot break the
            %   figure's key loop.
            if nargin < 3, evt = []; end
            if nargin < 2, src = []; end
            if isempty(obj.Callback), return; end

            try
                n = nargin(obj.Callback);   % -1 for varargin
            catch
                n = -1;
            end

            try
                if n == 0
                    obj.Callback();
                else
                    obj.Callback(src, evt);
                end
            catch err
                warning('KeyBinding:callbackError', ...
                    'Key binding "%s" callback failed: %s', obj.label(), err.message);
            end
        end

        function s = label(obj)
            % LABEL  Pretty shortcut string for display, e.g. "Ctrl+Shift+A", "↑", "Enter".
            modMap = containers.Map( ...
                {'control','shift','alt','command'}, ...
                {'Ctrl','Shift','Alt','Cmd'});

            parts = strings(1,0);
            % Display modifiers in a conventional order regardless of storage order.
            for m = ["control","shift","alt","command"]
                if any(obj.Modifiers == m)
                    parts(end+1) = modMap(char(m)); %#ok<AGROW>
                end
            end
            parts(end+1) = KeyBinding.prettyKey(obj.Key);
            s = strjoin(parts, "+");
        end
    end

    methods (Static, Access = private)
        function key = normalizeKey(key)
            key = lower(char(string(key)));
            switch key
                case 'esc',   key = 'escape';
                case 'enter', key = 'return';
                case 'del',   key = 'delete';
                % otherwise: leave as-is (single chars, 'uparrow', 'f1', ...)
            end
        end

        function mods = normalizeModifiers(mods)
            % Accept string array, cellstr, char, or empty; return sorted unique
            % lowercase string row vector using MATLAB modifier names.
            if isempty(mods)
                mods = string.empty(1,0);
                return;
            end
            mods = lower(string(mods(:)).');

            % Normalize common aliases to MATLAB's evt.Modifier names.
            mods(mods == "ctrl")    = "control";
            mods(mods == "cmd")     = "command";
            mods(mods == "windows") = "command";
            mods(mods == "option")  = "alt";

            mods = unique(mods);                 % unique() also sorts
            mods = reshape(mods, 1, []);
        end

        function p = prettyKey(key)
            switch lower(key)
                case 'uparrow',    p = "↑";
                case 'downarrow',  p = "↓";
                case 'leftarrow',  p = "←";
                case 'rightarrow', p = "→";
                case 'return',     p = "Enter";
                case 'escape',     p = "Esc";
                case 'space',      p = "Space";
                case 'delete',     p = "Del";
                case 'backspace',  p = "Backspace";
                case 'tab',        p = "Tab";
                case 'home',       p = "Home";
                case 'end',        p = "End";
                case 'pageup',     p = "PageUp";
                case 'pagedown',   p = "PageDown";
                otherwise
                    if ~isempty(regexp(lower(key), '^f([1-9]|1[0-2])$', 'once'))
                        p = upper(string(key));          % f1 -> F1
                    elseif isscalar(key)
                        p = upper(string(key));          % a -> A
                    else
                        p = string(key);                 % fallback: raw name
                    end
            end
        end
    end
end
