function onButtonMotion(obj)
%onButtonMotion  Update the viewport while a middle-drag pan is in progress.
%   Uses pixel deltas (not data coordinates, which move with the axes) so the
%   point grabbed under the cursor stays under the cursor. Horizontal motion
%   always pans time. Vertical motion scrolls the channel window when the
%   channel axis is currently windowed (NumVisibleChannels < NumChannels, in
%   either Mode); otherwise it pans the amplitude baseline in traces mode
%   (unchanged legacy behaviour), and is a no-op in heatmap mode.

P = obj.Pan;
if ~isstruct(P) || ~isfield(P, 'active') || ~P.active; return; end

cp = obj.Figure.CurrentPoint;
dx = cp(1) - P.startPix(1);
dy = cp(2) - P.startPix(2);

sX = obj.TimeWindowDuration / max(P.axPix(3), 1);
obj.TimeWindowStart = P.tLeft0 - dx * sX;

if P.chanMode
    chansPerPix = obj.NumVisibleChannels / max(P.axPix(4), 1);
    obj.FirstVisibleChannel = round(P.firstCh0 - dy * chansPerPix);
elseif obj.Mode == "traces"
    yl = ylim(obj.Axes);
    sY = (yl(2) - yl(1)) / max(P.axPix(4), 1);
    obj.YOffset = P.yOff0 + dy * sY;
end

obj.render();
end
