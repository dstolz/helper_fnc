function fig = use_fig(name)
% USE_FIG Create or reuse a named figure window.
% 
%   USE_FIG(NAME) finds an existing figure with the specified NAME.
%   - If a figure with the given NAME exists, it is brought to the front and cleared.
%   - If no figure exists with that NAME, a new figure is created with the specified NAME.
% 
%   FIG = USE_FIG(NAME) returns the figure handle.
%   - If no output is requested, the function does not return the figure handle.
% 
%   Example:
%       use_fig('MyFigure');  % Creates or reuses a figure named 'MyFigure'
%       plot(1:10, rand(1,10)); % Plot data in the figure
 
if nargin == 0 || isempty(name), name = 'scratch'; end

fig = findobj('type','figure','-and','name',name);
if isempty(fig)
    fig = figure('name',name,'color','w','NumberTitle','off');
end
figure(fig);
clf(fig);
if nargout == 0, clear fig; end

