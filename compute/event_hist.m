function h = event_hist(spikeTimes, eventTimes, bins)
% EVENT_HIST Computes trial-by-trial spike histograms aligned to events.
%
%   h = event_hist(spikeTimes, eventTimes, bins)
%
%   This function computes a histogram of spike times relative to a set of
%   event times on a trial-by-trial basis. Each trial corresponds to a row
%   in `eventTimes`, and the spike counts are computed within the specified 
%   bin edges.
%
%   Inputs:
%       spikeTimes  - Vector of spike timestamps (in seconds or ms).
%       eventTimes  - Vector of event timestamps (one per trial).
%       bins        - Vector of bin edges (relative to each event time).
%
%   Output:
%       h - Matrix of spike counts, size (numBins-1) x (numTrials),
%           where numBins = length(bins).
%
%   Example:
%       spikeTimes = sort(rand(1, 100) * 10); % 100 spikes in 10 sec
%       eventTimes = [1, 3, 5, 7]; % Event times at 1, 3, 5, and 7 sec
%       bins = -1:0.1:1; % 100 ms bins around each event (-1 to +1 sec)
%       
%       h = event_hist(spikeTimes, eventTimes, bins);
%       
%       % Plot histogram for first trial
%       figure;
%       bar(bins(1:end-1), h(:,1), 'histc');
%       xlabel('Time relative to event (s)');
%       ylabel('Spike Count');
%       title('Trial 1 Spike Histogram');
%



h = nan(length(bins) - 1, length(eventTimes));


for i = 1:length(eventTimes)
    st = spikeTimes - eventTimes(i);
    st(st < bins(1) | st >= bins(end)) = [];
    
    if isempty(st), continue; end 
    
    h(:, i) = histcounts(st, bins);
end
