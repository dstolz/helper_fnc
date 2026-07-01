function onKeyRelease(obj, evt)
%onKeyRelease  Track currently-held modifier keys (WindowKeyReleaseFcn handler).
%   KeyMap never touches WindowKeyReleaseFcn, so this stays directly installed
%   for the object's lifetime.

obj.Mods = string(evt.Modifier);
end
