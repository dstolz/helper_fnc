function renderReviewPlots(obj)
%renderReviewPlots  Draw the four Review-tab axes from cached ReviewData.
%   Units-per-shank and firing-rate plots always show every unit; the waveform
%   and amplitude plots show all units when nothing is selected, or focus on
%   obj.ReviewSelectedUnit (a row index into ReviewData) when a table row is
%   picked. Reads only the cache, so it is cheap to call on every selection.

if isempty(obj.ReviewData); return; end
R = obj.ReviewData;
sel = obj.ReviewSelectedUnit;
U = numel(R.clusterID);

% Per-shank color, reused across panels for consistency.
nSh = max(R.nShank, 1);
shankColors = lines(nSh);
[~, shankIdx] = ismember(R.shank, R.shankIDs);
shankIdx(shankIdx < 1) = 1;

plotUnitsPerShank(obj.ReviewShankAxes, R, shankColors);
plotWaveforms(obj.ReviewWaveAxes, R, sel, shankColors, shankIdx);
plotAmplitudes(obj.ReviewAmpAxes, R, sel);
plotFiringRates(obj.ReviewRateAxes, R, sel, shankColors, shankIdx);
end


%% ---------------------------------------------------------------------------
function plotUnitsPerShank(ax, R, shankColors)
%plotUnitsPerShank  Stacked good/mua/other counts per shank.
cla(ax, 'reset');
nSh = R.nShank;
counts = zeros(nSh, 3);   % [good mua other]
for s = 1:nSh
    m = R.shank == R.shankIDs(s);
    counts(s, 1) = sum(m & R.label == "good");
    counts(s, 2) = sum(m & R.label == "mua");
    counts(s, 3) = sum(m) - counts(s, 1) - counts(s, 2);
end
b = bar(ax, 1:nSh, counts, 'stacked');
b(1).FaceColor = [0.20 0.60 0.25];   % good
b(2).FaceColor = [0.55 0.55 0.60];   % mua
b(3).FaceColor = [0.80 0.45 0.20];   % other
ax.XTick = 1:nSh;
ax.XTickLabel = string(R.shankIDs);
xlabel(ax, "Shank");
ylabel(ax, "# units");
title(ax, sprintf("Units per shank (%d total)", numel(R.clusterID)));
legend(ax, {'good', 'mua', 'other'}, 'Location', 'best', 'Box', 'off');
grid(ax, 'on');
end


function plotWaveforms(ax, R, sel, shankColors, shankIdx)
%plotWaveforms  Overlay peak-channel templates (all), or one unit's footprint.
cla(ax, 'reset');
hold(ax, 'on');
if sel < 1 || sel > numel(R.clusterID)
    % All units: peak-channel mean waveform, colored by shank.
    seen = false(R.nShank, 1);
    for u = 1:numel(R.clusterID)
        si = shankIdx(u);
        if ~seen(si)
            seen(si) = true;
            plot(ax, R.tms, R.wfPeak(:, u), 'Color', shankColors(si, :), ...
                'LineWidth', 1, 'DisplayName', sprintf('shank %g', R.shankIDs(si)));
        else
            plot(ax, R.tms, R.wfPeak(:, u), 'Color', shankColors(si, :), ...
                'LineWidth', 1, 'HandleVisibility', 'off');
        end
    end
    xlabel(ax, "Time (ms)");
    ylabel(ax, "Amplitude (a.u.)");
    title(ax, "Mean waveforms (peak channel, all units)");
    if R.nShank > 1
        legend(ax, 'Location', 'best', 'Box', 'off');
    end
else
    % Single unit: stack the strongest channels by depth.
    wf = R.wfFull(:, :, sel);                 % [nS x nCh]
    p2p = max(wf, [], 1) - min(wf, [], 1);
    K = min(8, size(wf, 2));
    [~, ord] = maxk(p2p, K);
    if ~isempty(R.chanPos) && size(R.chanPos, 1) >= max(ord)
        [~, byDepth] = sort(R.chanPos(ord, 2), 'descend');
        ord = ord(byDepth);
    else
        ord = sort(ord);
    end
    offset = 1.2 * max(p2p(ord));
    if offset == 0; offset = 1; end
    yt = zeros(K, 1);
    for k = 1:K
        base = (K - k) * offset;
        yt(k) = base;
        isPk = ord(k) == R.peakChan(sel);
        c = [0.2 0.2 0.2];
        if isPk; c = [0.85 0.1 0.1]; end
        plot(ax, R.tms, wf(:, ord(k)) + base, 'Color', c, ...
            'LineWidth', 1 + isPk);
    end
    ax.YTick = flipud(yt);
    ax.YTickLabel = flipud(string(ord(:)));
    ylabel(ax, "Channel");
    xlabel(ax, "Time (ms)");
    title(ax, sprintf("Unit %d waveform (top %d ch, peak ch %d)", ...
        R.clusterID(sel), K, R.peakChan(sel)));
end
hold(ax, 'off');
grid(ax, 'on');
end


function plotAmplitudes(ax, R, sel)
%plotAmplitudes  Spike amplitude vs time: all units (colored), or one unit.
cla(ax, 'reset');
budget = 30000;
if sel < 1 || sel > numel(R.clusterID)
    t = R.spikeSec;
    a = R.spikeAmp;
    cidx = R.spikeUnitIdx;
    N = numel(t);
    if N > budget
        keep = round(linspace(1, N, budget));
        t = t(keep); a = a(keep); cidx = cidx(keep);
    end
    cmapU = lines(max(numel(R.clusterID), 1));
    scatter(ax, t, a, 4, cmapU(cidx, :), 'filled', 'MarkerFaceAlpha', 0.35);
    title(ax, sprintf("Amplitudes over time (%d units, %s spikes)", ...
        numel(R.clusterID), thousands(numel(R.spikeSec))));
else
    m = R.spikeUnitIdx == sel;
    t = R.spikeSec(m);
    a = R.spikeAmp(m);
    N = numel(t);
    if N > budget
        keep = round(linspace(1, N, budget));
        t = t(keep); a = a(keep);
    end
    scatter(ax, t, a, 5, [0 0.35 0.75], 'filled', 'MarkerFaceAlpha', 0.4);
    title(ax, sprintf("Unit %d amplitudes (%s spikes)", ...
        R.clusterID(sel), thousands(N)));
end
xlabel(ax, "Time (s)");
ylabel(ax, "Amplitude (a.u.)");
grid(ax, 'on');
if isfinite(R.durSec) && R.durSec > 0; xlim(ax, [0 R.durSec]); end
end


function plotFiringRates(ax, R, sel, shankColors, shankIdx)
%plotFiringRates  Per-unit firing rate, bars colored by shank.
cla(ax, 'reset');
U = numel(R.clusterID);
b = bar(ax, 1:U, R.firingRate, 'FaceColor', 'flat');
b.CData = shankColors(shankIdx, :);
hold(ax, 'on');
if sel >= 1 && sel <= U
    bar(ax, sel, R.firingRate(sel), 'FaceColor', 'none', ...
        'EdgeColor', 'k', 'LineWidth', 1.5);
end
hold(ax, 'off');
xlabel(ax, "Unit index");
ylabel(ax, "Firing rate (Hz)");
title(ax, "Firing rate per unit (color = shank)");
grid(ax, 'on');
if U > 0; xlim(ax, [0.5 U + 0.5]); end
end


function s = thousands(n)
s = regexprep(sprintf('%d', round(n)), '\d(?=(\d{3})+$)', '$0,');
end
