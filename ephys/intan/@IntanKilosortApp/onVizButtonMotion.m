function onVizButtonMotion(obj)
%onVizButtonMotion  Update the viewport while a middle-button pan is in progress.
%   Uses pixel deltas (not data coordinates, which move with the axes) so the
%   point grabbed under the cursor stays under the cursor. Horizontal motion
%   pans time in both modes; vertical motion shifts the channel baseline in
%   traces mode.

P = obj.VizPan;
if ~isstruct(P) || ~isfield(P, 'active') || ~P.active; return; end

cp = obj.Fig.CurrentPoint;
dx = cp(1) - P.startPix(1);
dy = cp(2) - P.startPix(2);

% Horizontal: seconds per pixel from the current window width.
sX = obj.VizView.tWin / max(P.axPix(3), 1);
obj.VizView.tLeft = P.tLeft0 - dx * sX;

% Vertical (traces only): data units per pixel from the current y-limits.
if obj.VizView.mode == "traces"
    yl = ylim(obj.VizAxes);
    sY = (yl(2) - yl(1)) / max(P.axPix(4), 1);
    obj.VizView.yOffset = P.yOff0 + dy * sY;
end

obj.renderViz();
end
