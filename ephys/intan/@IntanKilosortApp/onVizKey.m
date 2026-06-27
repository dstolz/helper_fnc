function onVizKey(obj, evt, isPress)
%onVizKey  Track modifier keys and handle Visualize keyboard shortcuts.
%   Bound to both WindowKeyPressFcn (isPress=true) and WindowKeyReleaseFcn
%   (isPress=false). Scroll-wheel events carry no modifier state, so the set of
%   currently-held modifiers is cached here in obj.VizMods for onVizScroll to
%   read. On a key press a few view shortcuts are also handled:
%     <- / -> ... step the window by a quarter      r ... reset the view

% evt.Modifier is the list of modifiers held at the moment of the event, so it
% stays in sync for both press and release.
obj.VizMods = string(evt.Modifier);

if ~isPress || ~vizActive(obj); return; end

V = obj.VizView;
switch evt.Key
    case 'leftarrow'
        V.tLeft = V.tLeft - 0.25 * V.tWin;
    case 'rightarrow'
        V.tLeft = V.tLeft + 0.25 * V.tWin;
    case 'r'
        % Reset to the Start/Window fields at unit gain and zero baseline.
        V.tWin    = min(obj.VizDurField.Value, obj.VizData.nSamp / obj.VizData.Fs);
        V.tLeft   = obj.VizStartField.Value;
        V.ampGain = 1;
        V.yOffset = 0;
    otherwise
        return
end
obj.VizView = V;
obj.renderViz();
end
