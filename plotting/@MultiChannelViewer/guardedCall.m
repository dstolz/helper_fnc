function guardedCall(obj, fcn)
%guardedCall  Run FCN only when ActiveFcn() is true.
%   Used to wrap every KeyMap-registered shortcut so keyboard actions respect
%   the same "is this viewer currently active" gate as onScroll/onButtonDown.

if ~obj.ActiveFcn(); return; end
fcn();
end
