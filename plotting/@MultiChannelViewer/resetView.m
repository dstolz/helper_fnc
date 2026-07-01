function resetView(obj)
%resetView  Restore the view (mode/time/gain/offset/channel window) to what it
%   was right after construction (or the most recent loadData call).
if isempty(obj.InitView); return; end
iv = obj.InitView;
obj.Mode = iv.Mode;
obj.TimeWindowStart = iv.TimeWindowStart;
obj.TimeWindowDuration = iv.TimeWindowDuration;
obj.AmpGain = iv.AmpGain;
obj.YOffset = iv.YOffset;
obj.FirstVisibleChannel = iv.FirstVisibleChannel;
obj.NumVisibleChannels = iv.NumVisibleChannels;
obj.render();
end
