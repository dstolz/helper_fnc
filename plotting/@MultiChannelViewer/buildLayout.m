function buildLayout(obj, parent, hasDigital, hasAux)
%buildLayout  Resolve Figure/Axes/DigitalAxes/AuxAxes from the given Parent.
%   A bare Axes/UIAxes Parent is only valid when neither digital nor auxiliary
%   tracks are requested (the simple, backward-compatible single-axes case).
%   Otherwise Parent must be a container (a figure, uipanel/uitab, or
%   uigridlayout) so a 1-3-row tiledlayout (digital / main / auxiliary) can be
%   built inside it, with the main row given most of the height via TileSpan.
%   An empty Parent creates an owned classic figure.

isAxesLike = ~isempty(parent) && ...
    (isa(parent, 'matlab.graphics.axis.Axes') || isa(parent, 'matlab.ui.control.UIAxes'));

if isAxesLike
    if hasDigital || hasAux
        error('MultiChannelViewer:ParentMustBeContainer', ...
            ['Parent is a single axes, but DigitalData/AuxData were supplied. Pass ', ...
             'a container (a figure, uipanel/uitab, or uigridlayout) instead so this ', ...
             'class can build its own internal digital/main/auxiliary layout inside it.']);
    end
    obj.Axes = parent;
    obj.Figure = ancestor(parent, 'figure');
    obj.DigitalAxes = gobjects(0);
    obj.AuxAxes = gobjects(0);
    obj.OwnsFigure = false;
    return
end

if isempty(parent)
    obj.Figure = figure('Name', 'MultiChannelViewer', 'NumberTitle', 'off');
    obj.OwnsFigure = true;
    container = obj.Figure;
else
    fig = ancestor(parent, 'figure');
    obj.Figure = fig;
    obj.OwnsFigure = false;
    container = parent;
end

if ~hasDigital && ~hasAux
    obj.Axes = axes('Parent', container);
    obj.DigitalAxes = gobjects(0);
    obj.AuxAxes = gobjects(0);
    return
end

% tiledlayout has no per-row-height property, so a weighted layout is built
% via TileSpan over a finer grid instead: the main view gets 8 "units", a
% digital row (if present) gets 2, an auxiliary row (if present) gets 3.
digitalUnits = 2 * double(hasDigital);
mainUnits = 8;
auxUnits = 3 * double(hasAux);
totalRows = digitalUnits + mainUnits + auxUnits;

tl = tiledlayout(container, totalRows, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

row = 1;
if hasDigital
    obj.DigitalAxes = nexttile(tl, row, [digitalUnits, 1]);
    row = row + digitalUnits;
else
    obj.DigitalAxes = gobjects(0);
end

obj.Axes = nexttile(tl, row, [mainUnits, 1]);
row = row + mainUnits;

if hasAux
    obj.AuxAxes = nexttile(tl, row, [auxUnits, 1]);
else
    obj.AuxAxes = gobjects(0);
end
end
