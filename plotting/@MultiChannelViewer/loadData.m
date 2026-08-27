function loadData(obj, data, Fs, opts)
%loadData  Swap in new main-channel data without recreating the object.
%   obj.loadData(data, Fs, ChannelNames=..., Units=...) replaces the cached
%   signal matrix, recomputes the robust amplitude scale (Clim0), and resets
%   the time/channel window to start at the beginning of the new data. Mode,
%   AmpGain, TraceSpacing, PixelBudget, and Colormap are untouched, so repeated
%   reloads (e.g. re-plotting a new selection) keep the user's current display
%   settings.

arguments
    obj
    data (:,:) {mustBeNumeric}
    Fs (1,1) double {mustBePositive}
    opts.ChannelNames (1,:) string = string.empty(1,0)
    opts.Units (1,1) string = ""
end

if isempty(data) || size(data, 1) < 1
    error('MultiChannelViewer:EmptyData', 'data must have at least one sample.');
end

nSamp = size(data, 1);
nCh = size(data, 2);

names = opts.ChannelNames;
if isempty(names)
    names = "ch" + string(1:nCh);
elseif numel(names) ~= nCh
    error('MultiChannelViewer:NameCountMismatch', ...
        'ChannelNames must have one entry per channel (%d).', nCh);
end

X = single(data);

% Robust ~5-sigma-via-MAD amplitude scale (NaN-safe); falls back to max-abs,
% then to 1, for flat/all-NaN data. Drives default TraceSpacing/heatmap CLim.
samp = X(:);
clim0 = 5 * median(abs(samp - median(samp, 'omitnan')), 'omitnan');
if ~isfinite(clim0) || clim0 <= 0
    clim0 = max(abs(samp), [], 'omitnan');
end
if ~isfinite(clim0) || clim0 <= 0
    clim0 = 1;
end

obj.Data = struct('X', X, 'Fs', Fs, 'nSamp', nSamp, 'nCh', nCh, 'Clim0', clim0);
obj.NumSamples = nSamp;
obj.NumChannels = nCh;
obj.ChannelNames = names;
obj.Units = opts.Units;

% Start the view at the beginning of the new data; keep the user's current
% zoom/channel-window size (clamped to the new channel count).
obj.TimeWindowStart = 0;
obj.FirstVisibleChannel = 1;
obj.NumVisibleChannels = min(max(1, round(obj.NumVisibleChannels)), nCh);

% A new channel count invalidates any previous display-order permutation and
% any previous group assignment; callers that want them re-apply via
% setChannelOrder()/setChannelGroups() after loadData.
obj.ChannelOrder = double.empty(1,0);
obj.ChannelGroups = double.empty(1,0);

% Force a clean rebuild of the main-axes graphics on the next render().
obj.DrawnMode = "";
obj.Lines = gobjects(0, 1);
obj.Image = gobjects(0);
if ~isempty(obj.Colorbar) && isvalid(obj.Colorbar)
    delete(obj.Colorbar);
end
obj.Colorbar = gobjects(0);

if ~obj.Initializing
    obj.render();
end
end
