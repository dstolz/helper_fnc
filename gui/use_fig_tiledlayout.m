function tl = use_fig_tiledlayout(name,tlopts)
if nargin == 0, name = []; end
if nargin < 2
    tlopts = {"flow"};
end

f = use_fig(name);
tl = tiledlayout(f,tlopts{:});

if nargout == 0, clear tl; end