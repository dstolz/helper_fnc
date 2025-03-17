function auroc_curve = auROC_response_curve(hist_data, edges, baselineWindow, auroc_binsize)
    % Receiver Operating Characteristic curve (auROC) calculation
    % Translated from Python to MATLAB

    % Determine baseline period histogram
    baseline_mask = (edges >= baselineWindow(1)) & (edges < baselineWindow(2));
    baseline_hist = hist_data(baseline_mask(1:end-1));

    max_criterion = max(hist_data) + 0.1; % Ensure nonzero maximum criterion

    % Initialize output
    auroc_curve = [];

    % Loop over response bins
    for start_bin = edges(1):auroc_binsize:edges(end)
        cur_mask = (edges >= start_bin) & (edges < start_bin + auroc_binsize);
        cur_hist_values = hist_data(cur_mask(1:end-1));

        if max_criterion > 0
            thresholds = linspace(0, max_criterion, floor(max_criterion / 0.1));
        else
            thresholds = [0, 1]; % Handle zero spikes case
        end

        false_positive = zeros(1, length(thresholds));
        true_positive = zeros(1, length(thresholds));

        for i = 1:length(thresholds)
            t = thresholds(i);
            false_positive(i) = sum(baseline_hist >= t) / length(baseline_hist);
            true_positive(i) = sum(cur_hist_values >= t) / length(cur_hist_values);
        end

        % Compute area under ROC curve
        auroc_curve = [auroc_curve, trapz(sort(false_positive), sort(true_positive))];
    end
end
