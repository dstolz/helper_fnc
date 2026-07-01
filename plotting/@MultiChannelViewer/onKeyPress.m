function onKeyPress(obj, evt)
%onKeyPress  Track currently-held modifier keys (WindowKeyPressFcn handler).
%   Installed BEFORE the KeyMap (see attachCallbacks), so KeyMap.dispatch
%   chains to this on every keypress that doesn't match a registered shortcut
%   (e.g. a bare Alt/Shift/Ctrl keydown) -- this is how onScroll/onButtonDown
%   learn about held modifiers, since scroll-wheel events carry none of their
%   own.

obj.Mods = string(evt.Modifier);
end
