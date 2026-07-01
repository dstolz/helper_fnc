function onScroll(obj, evt)
%onScroll  Mouse-wheel navigation (WindowScrollWheelFcn handler).
%   Modifiers (tracked in obj.Mods, since scroll events carry none of their
%   own) select the action:
%     wheel ................. fine scroll in time (15% of the window/notch)
%     Ctrl+wheel ............ jog one full window at a time
%     Shift+wheel ........... zoom the time axis, anchored at the cursor
%     Ctrl+Shift+wheel ...... scale channel amplitude (trace gain / heatmap clim)
%     Alt+wheel ............. scroll the channel window by 1 channel
%     Alt+Ctrl+wheel ........ page the channel window by NumVisibleChannels

if ~obj.ActiveFcn(); return; end
if ~obj.cursorOverAxes(); return; end

sc = evt.VerticalScrollCount;
mods = obj.Mods;
hasShift = any(mods == "shift");
hasCtrl  = any(mods == "control");
hasAlt   = any(mods == "alt");

if hasAlt && hasCtrl
    obj.scrollChannels(sc * obj.NumVisibleChannels);
elseif hasAlt
    obj.scrollChannels(sc);
elseif hasCtrl && hasShift
    obj.setGain(1.2 ^ (-sc));
elseif hasShift
    cx = obj.Axes.CurrentPoint(1, 1);
    obj.zoomTime(1.2 ^ sc, cx);
elseif hasCtrl
    obj.panTime(sc * obj.TimeWindowDuration);
else
    obj.panTime(sc * 0.15 * obj.TimeWindowDuration);
end
end
