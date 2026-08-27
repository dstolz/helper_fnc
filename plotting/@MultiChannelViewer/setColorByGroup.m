function setColorByGroup(obj, tf)
%setColorByGroup  Toggle coloring traces by ChannelGroups (e.g. probe shank)
%   instead of the default per-line color cycle. No effect in heatmap mode.
arguments
    obj
    tf (1,1) logical
end
obj.ColorByGroup = tf;
obj.render();
end
