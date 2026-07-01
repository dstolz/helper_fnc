function jumpToChannel(obj, idx, opts)
%jumpToChannel  Move the channel window so channel IDX is at the requested
%   edge. Anchor="first" (default) puts IDX at the top of the window (Home
%   equivalent); Anchor="last" puts IDX at the bottom (End equivalent).
arguments
    obj
    idx (1,1) double {mustBePositive, mustBeInteger}
    opts.Anchor (1,1) string {mustBeMember(opts.Anchor, ["first","last"])} = "first"
end
if opts.Anchor == "last"
    obj.FirstVisibleChannel = idx - obj.NumVisibleChannels + 1;
else
    obj.FirstVisibleChannel = idx;
end
obj.render();
end
