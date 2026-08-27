function setChannelOrder(obj, order)
%setChannelOrder  Reorder which raw channel is shown at each display position,
%   without touching the cached data (e.g. to display channels in probe-depth
%   order instead of their raw column order).
%
%   obj.setChannelOrder(order)  ORDER is a permutation of 1:NumChannels;
%   ORDER(k) is the data-column (raw channel) index shown at display position
%   k. FirstVisibleChannel/scrollChannels/jumpToChannel keep addressing
%   display position, not the raw channel, so the channel window continues to
%   behave the same way once reordered.
%
%   obj.setChannelOrder([])  restores natural order (display position k ==
%   data column k), e.g. to undo a probe-depth sort.

arguments
    obj
    order (1,:) double = double.empty(1,0)
end

if ~isempty(order) && (numel(order) ~= obj.NumChannels || ~isequal(sort(round(order)), 1:obj.NumChannels))
    error('MultiChannelViewer:BadChannelOrder', ...
        'order must be a permutation of 1:NumChannels (%d) or [].', obj.NumChannels);
end

obj.ChannelOrder = round(order);
obj.render();
end
