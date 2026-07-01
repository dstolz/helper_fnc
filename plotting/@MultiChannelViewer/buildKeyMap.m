function km = buildKeyMap(obj)
%buildKeyMap  Build (but do not attach) a KeyMap with this viewer's default
%   keyboard shortcuts, targeting the ancestor figure of obj.Axes (works
%   whether obj.Axes is a classic axes or a uiaxes). Also stored in
%   obj.KeyMapObj. Call km.attach() to install it -- the constructor does this
%   automatically when EnableKeyMap is true. Every registered callback is
%   wrapped in obj.guardedCall so it respects ActiveFcn, the same gate
%   onScroll/onButtonDown check.

km = KeyMap(obj.Axes);

km.add('leftarrow', @() obj.guardedCall(@() obj.panTime(-0.25 * obj.TimeWindowDuration)), ...
    Description="Step time back 25% of window", Category="Navigation");
km.add('rightarrow', @() obj.guardedCall(@() obj.panTime(0.25 * obj.TimeWindowDuration)), ...
    Description="Step time forward 25% of window", Category="Navigation");

km.add('uparrow', @() obj.guardedCall(@() obj.scrollChannels(-1)), ...
    Description="Scroll channel window up by 1", Category="Channels");
km.add('downarrow', @() obj.guardedCall(@() obj.scrollChannels(1)), ...
    Description="Scroll channel window down by 1", Category="Channels");
km.add('pageup', @() obj.guardedCall(@() obj.scrollChannels(-obj.NumVisibleChannels)), ...
    Description="Page channel window up", Category="Channels");
km.add('pagedown', @() obj.guardedCall(@() obj.scrollChannels(obj.NumVisibleChannels)), ...
    Description="Page channel window down", Category="Channels");
km.add('home', @() obj.guardedCall(@() obj.jumpToChannel(1)), ...
    Description="Jump to first channel", Category="Channels");
km.add('end', @() obj.guardedCall(@() obj.jumpToChannel(obj.NumChannels, Anchor="last")), ...
    Description="Jump to last channel", Category="Channels");

km.add('equal', @() obj.guardedCall(@() obj.setGain(1.2)), ...
    Description="Increase amplitude gain", Category="Display");
km.add('hyphen', @() obj.guardedCall(@() obj.setGain(1 / 1.2)), ...
    Description="Decrease amplitude gain", Category="Display");
km.add('leftbracket', @() obj.guardedCall(@() obj.setSpacing(currentSpacing(obj) * 0.8)), ...
    Description="Decrease channel spacing", Category="Display");
km.add('rightbracket', @() obj.guardedCall(@() obj.setSpacing(currentSpacing(obj) * 1.25)), ...
    Description="Increase channel spacing", Category="Display");

km.add('m', @() obj.guardedCall(@() obj.setMode(toggleMode(obj.Mode))), ...
    Description="Toggle traces/heatmap", Category="Display");
km.add('r', @() obj.guardedCall(@() obj.resetView()), ...
    Description="Reset view", Category="Navigation");

obj.KeyMapObj = km;
end


function m = toggleMode(m)
%toggleMode  Flip "traces"<->"heatmap".
if m == "traces"
    m = "heatmap";
else
    m = "traces";
end
end


function s = currentSpacing(obj)
%currentSpacing  Resolve TraceSpacing to its effective value (auto = 2*Clim0).
s = obj.TraceSpacing;
if s <= 0
    s = 2 * obj.Data.Clim0;
end
end
