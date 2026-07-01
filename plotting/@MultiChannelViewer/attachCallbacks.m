function attachCallbacks(obj)
%attachCallbacks  Install this viewer's figure-level mouse/keyboard callbacks.
%   WindowKeyPressFcn/WindowKeyReleaseFcn are set FIRST so that, if a KeyMap is
%   built afterward (see buildKeyMap), KeyMap.attach() captures obj.onKeyPress
%   as its PrevKeyFcn and chains to it -- keeping modifier tracking alive for
%   onScroll even once KeyMap owns WindowKeyPressFcn.

fig = obj.Figure;
fig.WindowKeyPressFcn   = @(~, evt) obj.onKeyPress(evt);
fig.WindowKeyReleaseFcn = @(~, evt) obj.onKeyRelease(evt);
fig.WindowScrollWheelFcn = @(~, evt) obj.onScroll(evt);
fig.WindowButtonDownFcn  = @(~, ~) obj.onButtonDown();
fig.WindowButtonUpFcn    = @(~, ~) obj.onButtonUp();
end
