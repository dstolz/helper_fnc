

function c = event_spike_count(spikeTimes,eventTimes,win)
c = arrayfun(@(a) sum(spikeTimes>=a+win(1) & spikeTimes<=a+win(2)),eventTimes);
end
