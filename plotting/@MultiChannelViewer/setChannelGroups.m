function setChannelGroups(obj, groups)
%setChannelGroups  Assign a group id (e.g. probe shank number) to each
%   data-column (raw channel), used by traces mode to color lines by group
%   when ColorByGroup is enabled (see setColorByGroup).
%
%   obj.setChannelGroups(groups)  GROUPS(c) is the group id of raw channel c,
%   using the same data-column indexing convention as ChannelOrder (i.e.
%   independent of display order/position). Need not be a permutation --
%   any integers, including repeats, are valid.
%
%   obj.setChannelGroups([])  clears grouping (all channels ungrouped).

arguments
    obj
    groups (1,:) double = double.empty(1,0)
end

if ~isempty(groups) && numel(groups) ~= obj.NumChannels
    error('MultiChannelViewer:BadChannelGroups', ...
        'groups must have one entry per channel (%d) or [].', obj.NumChannels);
end

obj.ChannelGroups = round(groups);
obj.render();
end
