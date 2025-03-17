
function [h, binCenters] = event_hist_sliding(spikeTimes, eventTimes, binEdges, winSize, stepSize)
% EVENT_HIST_SLIDING Computes histograms with overlapping bins.
%
% [h, binCenters] = event_hist_sliding(spikeTimes, eventTimes, binEdges, winSize, stepSize)
%
% spikeTimes  : Array of spike times
% eventTimes  : Array of event times
% binEdges    : Bin edges for the histogram
% winSize     : Window size for overlapping bins
% stepSize    : Step size for the sliding window
%
% Output:
% h          : Trial-by-trial histogram matrix (M bins × N trials)
% binCenters : Bin centers (M x 1)
%
% The function precomputes sliding window edges and applies them to all events.

% Compute bin start and end times relative to event time
numBins = floor((binEdges(end) - binEdges(1) - winSize) / stepSize) + 1;
winStart = binEdges(1) + (0:numBins-1) * stepSize; % Start points of bins
winEnd = winStart + winSize; % End points of bins
binCenters = winStart + winSize / 2; % Compute bin centers for plotting

% Initialize output histogram
h = nan(numBins,length(eventTimes));

% Loop over events
for i = 1:length(eventTimes)
    t0 = eventTimes(i); % Align bins to event time
    
    % Compute spike counts for each bin
    for j = 1:numBins
        h(j,i) = sum(spikeTimes >= (t0 + winStart(j)) & spikeTimes < (t0 + winEnd(j)));
    end
end
end




