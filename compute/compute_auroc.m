function auroc = compute_auroc(FR, bins,options)
% compute auROC based on baseline earlier than -1 seconds
%
% Inputs:
%   FR - MxN matrix of firing rates (M time bins x N trials)
%   bins         - Mx1 vector of time values for each bin (e.g., in s)
% 
%   optional:
%       baselineWindow - 1x2 window indicating the baseline relative to
%                        bins. The first value is inclusive and the second
%                        value is exclusive. Default = [-inf 0]
%
% Output:
%   auroc - Mx1 vector of auROC values per time bin
%
% adapted from Matt's calculate_auROC.py

arguments
    FR %(:,:) double {mustBeNonempty}
    bins (1,:) double {mustBeNonempty}
    options.baselineWindow (1,2) double = [-inf 0]; % where window is [ )
    options.aurocBinwidth (1,1) double = 0.1; 
end

blind = bins >= options.baselineWindow(1) & bins < options.baselineWindow(2);

% Ensure there are baseline bins
if ~any(blind)
    error('No baseline bins found! Ensure timepoints include values < 0.');
end


auBins = bins(1):options.aurocBinwidth:bins(end);

max_criterion = max(FR) + 0.1; %  Add a bit more to the max criterion so create a true-positive = 0


blFR = FR(blind);

auroc = nan(1,length(auBins)-1);
for i = 1:length(auBins)-1
    ind = bins >= auBins(i) & bins < auBins(i+1);
    cFR = FR(ind);

    if max_criterion > 0
        thresholds = linspace(0,max_criterion, round(max_criterion / 0.1));
    else % is this condition even possible given the + 0.1 above?
        thresholds = [0,1];
    end

    false_positive = nan(size(thresholds));
    true_positive = nan(size(thresholds));
    for t = 1:length(thresholds)
        response_above_t = cFR >= thresholds(t);
        baseline_above_t = blFR >= thresholds(t);

        false_positive(t) = sum(baseline_above_t) / length(blFR);
        true_positive(t) = sum(response_above_t) / length(cFR);
    end

    if isequal(true_positive,0) && isequal(false_positive,0), continue; end

    auroc(i) = trapz(sort(false_positive),sort(true_positive));

end

