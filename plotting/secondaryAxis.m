function [ax2, listeners] = secondaryAxis(ax, mapfun, opts)
%SECONDARYAXIS Add a synced secondary axis using a user-specified mapping.
%   [AX2, L] = SECONDARYAXIS(AX, MAPFUN) overlays a secondary axis on AX.
%   MAPFUN maps primary-axis ticks/limits to secondary units, e.g.,
%       @(oct) fc*(2.^oct - 1)   % octaves -> Hz
%
%   Name-Value options:
%     Axis            - "y" or "x"  (which primary axis to map)          ["y"]
%     Location        - "auto"|"right"|"top" (side for the secondary)    ["auto"]
%                       "auto" -> right for y, top for x
%     Label           - axis label text                                   [""]
%     Format          - sprintf/compose format for tick labels            ["%.0f"]
%     Interpreter     - 'tex'|'latex'|'none' for tick/label               ["tex"]
%     BackgroundColor - secondary axes background (mapped to 'Color')     ['none']
%     Box             - 'on'|'off'                                        ['off']
%
%   Notes:
%     - Preserves existing graphics by creating AX2 in the same parent figure
%       with NextPlot='add' temporarily, then restoring the previous state and
%       the current axes after setup.
%
%   Examples:
%     % Right Y axis showing Hz from octaves (fc=4000):
%     secondaryAxis(gca, @(o) 4000*(2.^o - 1), 'Axis',"y", 'Label','\Deltaf (Hz)')
%
%     % Top X axis converting seconds to ms:
%     secondaryAxis(gca, @(s) 1000*s, 'Axis',"x", 'Label','Time (ms)', 'Format','%.0f')
%
%   Outputs:
%     AX2       - handle to the overlaid secondary axes
%     L         - listeners that keep the axes in sync (also stored in AX2.UserData)

arguments
    ax (1,1) matlab.graphics.axis.Axes
    mapfun (1,1) function_handle
    opts.Axis (1,1) string {mustBeMember(opts.Axis,["y","x"])} = "y"
    opts.Location (1,1) string {mustBeMember(opts.Location,["auto","right","top"])} = "auto"
    opts.Label (1,1) string = ""
    opts.Format (1,1) string = "%.0f"
    opts.Interpreter (1,1) string {mustBeMember(opts.Interpreter,["tex","latex","none"])} = "tex"
    opts.BackgroundColor = 'none'
    opts.Box (1,1) string {mustBeMember(opts.Box,["on","off"])} = "off"
end

if isempty(ax), ax = gca; end

% Ensure we add a new overlaid axes without clearing existing content
fig  = ancestor(ax,'figure');
oldNP = fig.NextPlot;
oldCA = fig.CurrentAxes;
fig.NextPlot = 'add';

if opts.Location=="auto"
    if opts.Axis=="y", loc = "right"; else, loc = "top"; end
else
    loc = opts.Location;
end

box(ax,'off');

ax2 = axes('Parent',fig, 'Position',ax.Position, 'Color',opts.BackgroundColor, ...
    'Box',opts.Box, 'HitTest','off', 'PickableParts','none', 'HandleVisibility','off');
ax2.TickLabelInterpreter = opts.Interpreter;

if opts.Axis=="y"
    ax2.XTick = [];                      % only show secondary Y
    ax2.YAxisLocation = loc;             % 'right'
    lp = linkprop([ax ax2], {'Position','XLim','XScale'});
    ax2.YLim  = mapfun(ax.YLim);
    ax2.YTick = mapfun(ax.YTick);
    ax2.YTickLabel = compose(opts.Format, ax2.YTick);
    if opts.Label ~= ""
        ylabel(ax2, opts.Label, 'Interpreter',opts.Interpreter)
    end
    listeners(1) = addlistener(ax,'YLim','PostSet',  @(~,~) set(ax2,'YLim', mapfun(ax.YLim)));
    listeners(2) = addlistener(ax,'YTick','PostSet', @(~,~) set(ax2,'YTick', mapfun(ax.YTick), ...
        'YTickLabel', compose(opts.Format, mapfun(ax.YTick))));
    listeners(3) = addlistener(ax,'Position','PostSet', @(~,~) set(ax2,'Position', ax.Position));
else
    ax2.YTick = [];                      % only show secondary X
    ax2.XAxisLocation = loc;             % 'top'
    lp = linkprop([ax ax2], {'Position','YLim','YScale'});
    ax2.XLim  = mapfun(ax.XLim);
    ax2.XTick = mapfun(ax.XTick);
    ax2.XTickLabel = compose(opts.Format, ax2.XTick);
    if opts.Label ~= ""
        xlabel(ax2, opts.Label, 'Interpreter',opts.Interpreter)
    end
    listeners(1) = addlistener(ax,'XLim','PostSet',  @(~,~) set(ax2,'XLim', mapfun(ax.XLim)));
    listeners(2) = addlistener(ax,'XTick','PostSet', @(~,~) set(ax2,'XTick', mapfun(ax.XTick), ...
        'XTickLabel', compose(opts.Format, mapfun(ax.XTick))));
    listeners(3) = addlistener(ax,'Position','PostSet', @(~,~) set(ax2,'Position', ax.Position));
end

% Keep the secondary axes on top and persist link/listeners
uistack(ax2,'top');
ax2.UserData = struct('listeners',listeners,'link',lp);

% Restore figure state and current axes
fig.NextPlot = oldNP;
if isgraphics(oldCA)
    fig.CurrentAxes = oldCA;
end
