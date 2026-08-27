function test_MultiChannelViewer()
%test_MultiChannelViewer  Verification suite for MultiChannelViewer.
%   Exercises construction defaults, both render modes, the in-place graphics-
%   reuse contract, time-window clamping, channel-window scrolling (in both
%   modes), edge cases, decimation correctness, the KeyMap/modifier-tracking
%   chain, and the optional digital/auxiliary track groups. No real ephys data
%   is required -- everything is synthetic.
%
%   Usage:  test_MultiChannelViewer

here = fileparts(mfilename('fullpath'));
addpath(here);                          % @MultiChannelViewer
addpath(fullfile(fileparts(here), 'gui'));   % KeyMap / KeyBinding

figsBefore = findall(groot, 'Type', 'figure');
cleanup = onCleanup(@() closeNewFigures(figsBefore));

nPass = 0; nFail = 0;
    function check(cond, msg)
        if cond
            nPass = nPass + 1;
            fprintf('  PASS: %s\n', msg);
        else
            nFail = nFail + 1;
            fprintf(2, '  FAIL: %s\n', msg);
        end
    end

rng(42);

%% 1-2. Construction defaults ------------------------------------------------
fprintf('\n== 1-2. Construction defaults ==\n');
Fs = 1000; nSamp = 5000; nCh = 8;
X = synthData(nSamp, nCh, Fs);

v = MultiChannelViewer(X, Fs);

check(isgraphics(v.Figure) && isvalid(v.Figure), 'figure auto-created');
check(isgraphics(v.Axes) && isvalid(v.Axes), 'axes auto-created');
check(v.NumChannels == nCh, 'NumChannels');
check(v.NumSamples == nSamp, 'NumSamples');

%% 3. Both render modes draw without error -----------------------------------
fprintf('\n== 3. Both render modes ==\n');
check(v.Mode == "traces", 'default Mode is traces');
check(numel(v.Lines) == v.NumVisibleChannels, 'line count == NumVisibleChannels (traces)');
v.setMode("heatmap");
check(isgraphics(v.Image) && isvalid(v.Image), 'image object created (heatmap)');
check(isgraphics(v.Colorbar) && isvalid(v.Colorbar), 'colorbar created (heatmap)');
v.setMode("traces");
check(numel(v.Lines) == v.NumVisibleChannels, 'line count restored after switching back to traces');

%% 4. Graphics-reuse contract --------------------------------------------------
fprintf('\n== 4. Graphics-object reuse ==\n');
linesBefore = v.Lines;
v.panTime(0.1);
check(isequal(linesBefore, v.Lines), 'Lines handles unchanged after panTime (in-place update)');

%% 5. Time-window clamping -----------------------------------------------------
fprintf('\n== 5. Time-window clamping ==\n');
v.TimeWindowDuration = 1e6;
v.render();
check(abs(v.TimeWindowDuration - nSamp/Fs) < 1e-9, 'window duration clamped to data span');
v.TimeWindowStart = -100;
v.render();
check(v.TimeWindowStart == 0, 'window start clamped to 0');
v.TimeWindowStart = 1e6;
v.render();
check(abs(v.TimeWindowStart - (nSamp/Fs - v.TimeWindowDuration)) < 1e-9, 'window start clamped to max left edge');
delete(v);

%% 6. Channel scrolling (both modes) ------------------------------------------
fprintf('\n== 6. Channel scrolling ==\n');
nCh2 = 64;
X2 = synthData(nSamp, nCh2, Fs);
v2 = MultiChannelViewer(X2, Fs, VisibleChannels=16);

for m = ["traces", "heatmap"]
    v2.setMode(m);
    v2.jumpToChannel(1);
    check(v2.FirstVisibleChannel == 1, "jumpToChannel(1) -> FirstVisibleChannel==1 (" + m + ")");
    check(isequal(v2.Axes.YTickLabel, cellstr(v2.ChannelNames(1:16)).'), ...
        "YTickLabels show channels 1-16 (" + m + ")");

    v2.scrollChannels(1);
    check(v2.FirstVisibleChannel == 2, "scrollChannels(+1) increments by 1 (" + m + ")");
    check(isequal(v2.Axes.YTickLabel, cellstr(v2.ChannelNames(2:17)).'), ...
        "YTickLabels track channel window after scroll (" + m + ")");

    v2.scrollChannels(1000);
    check(v2.FirstVisibleChannel == nCh2 - v2.NumVisibleChannels + 1, ...
        "scrollChannels(+1000) clamps to last page (" + m + ")");

    v2.scrollChannels(-1000);
    check(v2.FirstVisibleChannel == 1, "scrollChannels(-1000) clamps to 1 (" + m + ")");

    v2.jumpToChannel(nCh2, Anchor="last");
    check(v2.FirstVisibleChannel == nCh2 - v2.NumVisibleChannels + 1, ...
        "jumpToChannel(nCh,last) lands on last page (" + m + ")");

    v2.jumpToChannel(1);
    v2.scrollChannels(v2.NumVisibleChannels);
    check(v2.FirstVisibleChannel == 1 + 16, "page-jump (PageDown-equivalent) moves by NumVisibleChannels (" + m + ")");
end

%% 7. Edge cases ----------------------------------------------------------------
fprintf('\n== 7. Edge cases ==\n');
v1ch = MultiChannelViewer(synthData(1000, 1, Fs), Fs);
before = v1ch.FirstVisibleChannel;
v1ch.scrollChannels(5);
check(v1ch.FirstVisibleChannel == before, 'nCh=1: scrollChannels is a no-op');

vBig = MultiChannelViewer(synthData(1000, 4, Fs), Fs, VisibleChannels=64);
check(vBig.NumVisibleChannels == 4, 'VisibleChannels > nCh clamps to nCh');
beforeBig = vBig.FirstVisibleChannel;
vBig.scrollChannels(10);
check(vBig.FirstVisibleChannel == beforeBig, 'channel-scroll inert when all channels already visible');

Xnan = synthData(1000, 4, Fs);
Xnan(10:20, 1) = NaN;
Xnan(30, 2) = Inf;
vNan = MultiChannelViewer(Xnan, Fs);
vNan.setMode("heatmap");
check(all(isfinite(vNan.Axes.CLim)), 'CLim stays finite with NaN/Inf in data');

[teBig, ~] = MultiChannelViewer.decimateMinMax((0:999)'/Fs, synthData(1000, 2, Fs), 1e6);
check(numel(teBig) == 1000, 'oversized PixelBudget returns undecimated decimateMinMax output');
Cbig = MultiChannelViewer.binColumnsMean(synthData(1000, 2, Fs), 1e6);
check(size(Cbig, 1) == 1000, 'oversized PixelBudget returns undecimated binColumnsMean output');

%% 8. Decimation correctness -----------------------------------------------------
fprintf('\n== 8. Decimation correctness ==\n');
flatSeg = zeros(2000, 1);
flatSeg(1000) = 500;   % single spike in an otherwise-flat segment
tSpike = (0:1999)' / Fs;
[~, YeS] = MultiChannelViewer.decimateMinMax(tSpike, flatSeg, 10);
check(max(YeS(:)) >= 500 - 1e-9, 'a single spike survives tiny-PixelBudget decimation');

%% 9. KeyMap / modifier-tracking chain --------------------------------------------
fprintf('\n== 9. KeyMap / modifier chain ==\n');
v3 = MultiChannelViewer(synthData(nSamp, 8, Fs), Fs, VisibleChannels=4);
check(~isempty(v3.KeyMapObj) && v3.KeyMapObj.Attached, 'KeyMap built and attached');
check(~isempty(v3.Figure.WindowKeyPressFcn), 'WindowKeyPressFcn installed');

firstBefore = v3.FirstVisibleChannel;
v3.KeyMapObj.dispatch(v3.Figure, struct('Key', 'downarrow', 'Modifier', {{}}));
check(v3.FirstVisibleChannel == firstBefore + 1, 'KeyMap dispatch of downarrow scrolls channels');

v3.Figure.WindowKeyPressFcn(v3.Figure, struct('Key', 'x', 'Modifier', {{'alt'}}));
check(any(v3.Mods == "alt"), 'non-shortcut keypress still reaches the modifier tracker via KeyMap chaining');

%% 10. Digital / auxiliary tracks --------------------------------------------------
fprintf('\n== 10. Digital / auxiliary tracks ==\n');
nSamp4 = 4000; nCh4 = 6;
X4 = synthData(nSamp4, nCh4, Fs);
Dig = double(rand(nSamp4, 2) > 0.7);
Aux = synthData(nSamp4, 3, Fs) * 0.01;

fig4 = uifigure('Name', 'MCV digital/aux test');
panel = uipanel(fig4);
v4 = MultiChannelViewer(X4, Fs, Parent=panel, DigitalData=Dig, AuxData=Aux);

check(v4.HasDigitalTracks, 'HasDigitalTracks true when DigitalData supplied');
check(v4.HasAuxTracks, 'HasAuxTracks true when AuxData supplied');
check(isgraphics(v4.DigitalAxes) && isvalid(v4.DigitalAxes), 'DigitalAxes created');
check(isgraphics(v4.AuxAxes) && isvalid(v4.AuxAxes), 'AuxAxes created');

v4.panTime(0.2);
check(isequal(v4.DigitalAxes.XLim, v4.Axes.XLim), 'DigitalAxes XLim tracks main axes after panTime');
check(isequal(v4.AuxAxes.XLim, v4.Axes.XLim), 'AuxAxes XLim tracks main axes after panTime');

v5 = MultiChannelViewer(synthData(1000, 4, Fs), Fs);
check(~v5.HasDigitalTracks && ~v5.HasAuxTracks, 'no digital/aux tracks when not supplied');
check(isempty(v5.DigitalAxes) && isempty(v5.AuxAxes), 'DigitalAxes/AuxAxes empty when unused');

try
    MultiChannelViewer(synthData(1000, 4, Fs), Fs, DigitalData=ones(999, 1));
    check(false, 'sample-count mismatch should have errored');
catch ME
    check(strlength(string(ME.identifier)) > 0, 'sample-count mismatch raises a clear error');
end

try
    axBare = axes(figure());
    MultiChannelViewer(synthData(1000, 4, Fs), Fs, Parent=axBare, DigitalData=ones(1000, 1));
    check(false, 'bare-axes Parent + DigitalData should have errored');
catch ME
    check(strlength(string(ME.identifier)) > 0, 'bare-axes Parent + DigitalData raises a clear error');
end

%% 11. Channel display order (setChannelOrder) --------------------------------
fprintf('\n== 11. Channel display order ==\n');
nCh6 = 6;
X6 = synthData(nSamp, nCh6, Fs);
v6 = MultiChannelViewer(X6, Fs, VisibleChannels=nCh6);
check(isequal(v6.ChannelOrder, double.empty(1,0)), 'ChannelOrder starts empty (natural order)');

revOrder = nCh6:-1:1;
v6.setChannelOrder(revOrder);
check(isequal(v6.ChannelOrder, revOrder), 'setChannelOrder stores the permutation');
check(isequal(v6.Axes.YTickLabel, cellstr(v6.ChannelNames(revOrder)).'), ...
    'YTickLabels follow the reordered channels (traces)');

v6.setMode("heatmap");
check(isequal(v6.Axes.YTickLabel, cellstr(v6.ChannelNames(revOrder)).'), ...
    'YTickLabels follow the reordered channels (heatmap)');
v6.setMode("traces");
linesRev = v6.Lines;   % re-baseline: setMode legitimately recreates the lines

v6.setChannelOrder([]);
check(isequal(v6.ChannelOrder, double.empty(1,0)), 'setChannelOrder([]) restores natural order');
check(isequal(v6.Axes.YTickLabel, cellstr(v6.ChannelNames(1:nCh6)).'), ...
    'YTickLabels back to natural order after clearing ChannelOrder');
check(isequal(linesRev, v6.Lines), 'Lines handles unchanged by reordering (in-place update)');

try
    v6.setChannelOrder([1 2 3]);   % wrong length
    check(false, 'non-permutation order should have errored');
catch ME
    check(strlength(string(ME.identifier)) > 0, 'non-permutation order raises a clear error');
end

X7 = synthData(nSamp, nCh6, Fs);
v6.loadData(X7, Fs);
check(isequal(v6.ChannelOrder, double.empty(1,0)), 'loadData resets ChannelOrder to natural order');

%% 12. Color by group (e.g. probe shank) ---------------------------------------
fprintf('\n== 12. Color by group ==\n');
check(isequal(v6.ChannelGroups, double.empty(1,0)), 'ChannelGroups starts empty');
check(v6.ColorByGroup == false, 'ColorByGroup starts false');

groups = [1 1 2 2 3 3];   % raw-channel (data-column) group ids
v6.setChannelGroups(groups);
check(isequal(v6.ChannelGroups, groups), 'setChannelGroups stores the group ids');

colorsBefore = get(v6.Lines, 'Color');
v6.setColorByGroup(true);
check(v6.ColorByGroup == true, 'setColorByGroup(true) sets ColorByGroup');
colorsAfter = get(v6.Lines, 'Color');
check(~isequal(colorsBefore, colorsAfter), 'enabling ColorByGroup changes line colors in place');
check(isequal(v6.Lines(1).Color, v6.Lines(2).Color), 'channels sharing a group get the same color (ch1,ch2)');
check(isequal(v6.Lines(3).Color, v6.Lines(4).Color), 'channels sharing a group get the same color (ch3,ch4)');
check(~isequal(v6.Lines(1).Color, v6.Lines(3).Color), 'channels in different groups get different colors');

% Grouping is keyed by raw data column, not display position: reordering
% display should carry each channel's color with it.
v6.setChannelOrder(nCh6:-1:1);
check(isequal(v6.Lines(nCh6).Color, v6.Lines(nCh6 - 1).Color), ...
    'group coloring follows the raw channel through a display reorder');
v6.setChannelOrder([]);

v6.setColorByGroup(false);
colorsOff = get(v6.Lines, 'Color');
check(isequal(colorsBefore, colorsOff), 'disabling ColorByGroup restores the default per-line palette');

try
    v6.setChannelGroups([1 2 3]);   % wrong length
    check(false, 'wrong-length group list should have errored');
catch ME
    check(strlength(string(ME.identifier)) > 0, 'wrong-length group list raises a clear error');
end

v6.loadData(synthData(nSamp, nCh6, Fs), Fs);
check(isequal(v6.ChannelGroups, double.empty(1,0)), 'loadData resets ChannelGroups to empty');

%% Summary -------------------------------------------------------------------
fprintf('\n================  %d passed, %d failed  ================\n', nPass, nFail);
if nFail > 0
    error('test_MultiChannelViewer:Failures', '%d checks failed.', nFail);
end
end


function X = synthData(nSamp, nCh, Fs)
%synthData  Deterministic sine+noise synthetic multichannel data.
t = (0:nSamp-1)' / Fs;
X = zeros(nSamp, nCh);
for k = 1:nCh
    X(:, k) = (10*k) * sin(2*pi*(5+k)*t) + 2 * randn(nSamp, 1);
end
end


function closeNewFigures(figsBefore)
%closeNewFigures  Close every figure that exists now but didn't exist in
%   figsBefore -- i.e. every figure this test created, regardless of which
%   section created it.
figsNow = findall(groot, 'Type', 'figure');
figsNew = setdiff(figsNow, figsBefore);
for k = 1:numel(figsNew)
    if isgraphics(figsNew(k)) && isvalid(figsNew(k))
        close(figsNew(k));
    end
end
end
