function onVizScroll(obj, evt)
%onVizScroll  Mouse-wheel navigation of the Visualize viewport.
%   Modifiers (tracked in obj.VizMods) select the action:
%     wheel ............... fine scroll in time (15% of the window per notch)
%     Ctrl+wheel ......... jog one full window at a time
%     Shift+wheel ........ zoom the time axis, anchored at the cursor
%     Ctrl+Shift+wheel ... scale channel amplitude (trace gain / heatmap clim)
%   Only fires when the Visualize tab is active and the cursor is over the axes.

if ~vizActive(obj); return; end
if ~cursorOverAxes(obj); return; end

sc = evt.VerticalScrollCount;        % +1 per notch toward the user (down)
mods = obj.VizMods;
hasShift = any(mods == "shift");
hasCtrl  = any(mods == "control");
V = obj.VizView;

if hasCtrl && hasShift
    % Scale amplitude: wheel up (sc < 0) makes signals bigger.
    V.ampGain = min(max(V.ampGain * 1.2^(-sc), 1e-3), 1e4);

elseif hasShift
    % Zoom time about the cursor: wheel up zooms in, keeping that time fixed.
    cx = obj.VizAxes.CurrentPoint(1, 1);
    f  = 1.2^sc;
    V.tLeft = cx - (cx - V.tLeft) * f;
    V.tWin  = V.tWin * f;

elseif hasCtrl
    % Jog one full window per notch.
    V.tLeft = V.tLeft + sc * V.tWin;

else
    % Fine scroll.
    V.tLeft = V.tLeft + sc * 0.15 * V.tWin;
end

obj.VizView = V;
obj.renderViz();
end
