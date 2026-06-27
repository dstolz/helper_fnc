function [R, T, trl] = extract_trials(signal, onsets, Fs, twin)
%EXTRACT_TRIALS  Epoch a multichannel signal around event onsets.
%   [R,T,TRL] = EXTRACT_TRIALS(SIGNAL,ONSETS,FS,TWIN) extracts trial-aligned
%   epochs from a continuous multichannel signal using event onset times.
%
%   Inputs:
%     SIGNAL   [nSamples x nChan] numeric array of continuous data.
%     ONSETS   nTrials x 1 vector of event times (in seconds).
%     FS       scalar sampling rate in Hz (default = 1).
%     TWIN     1x2 vector [t0 t1] defining the window in seconds relative to
%              each onset (default = [-0.2 0.5]).
%
%   Outputs:
%     R     [nChan x nTime x nTrials] array of extracted signal epochs.
%     T     1xN vector of time (seconds) relative to event onset.
%     TRL   nTrials x 3 matrix following FieldTrip convention:
%              col 1 = begsample (start index)
%              col 2 = endsample (end index)
%              col 3 = offset (samples before t=0)
%
%   Example:
%     [R,T,trl] = extract_trials(signal, eventTimes, 1000, [-0.1 0.4]);
% 

arguments
    signal {mustBeReal, mustBeFinite}
    onsets double {mustBeFinite}
    Fs (1,1) double {mustBePositive,mustBeFinite} = 1
    twin (1,2) double {mustBeFinite} = [-0.2 0.5]
end



% Build TRL in samples
trl = round(onsets .* Fs);

% Fill TRL columns
swin = round(twin .* Fs);
trl(:,3) = swin(1);
trl(:,2) = trl(:,1) + swin(2);

% Prepare time base
[nSamps, nCh] = size(signal);
sbeg = min(trl(1,[1 3]));
send = trl(1,2) - trl(1,1);
T = (sbeg:send) ./ Fs;

% Extract
nTrials = size(trl,1);
R = nan(length(T),nCh,nTrials,like = signal);
for i = 1:nTrials
    sidx = (trl(i,1) + trl(i,3)):trl(i,2);
    nidx = find(sidx > 0 & sidx <= nSamps);
    sKeep = sidx(nidx);
    R(nidx,:,i) = signal(sKeep,:);
end


