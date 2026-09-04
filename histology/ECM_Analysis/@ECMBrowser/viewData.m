function v = viewData(obj)
    %VIEWDATA The numbers behind the plot, as one struct.
    %   v = B.viewData()
    %
    % Everything the controls have settled: the depth axis, one column
    % of intensities per section on the scale they are drawn on, the
    % rows of A.grid.files they came from, each section's peak rescaled
    % the same way the profiles were, and the summary metric the Metric
    % control names taken over those same columns. The plot and the
    % numbers under it come out of the same call, so a figure and the
    % table beside it cannot disagree about what was normalized or
    % filtered.
    %
    % V.METRIC is there whether or not the plot is showing it: it is
    % read off the columns in V.VALUES, so it costs one pass over what
    % has already been assembled and saves anyone taking the summary
    % away from having to reproduce the depth window and the scale it
    % was taken under.
    %
    % Under a comparison a column is a comparison rather than a
    % section: V.SECTIONS is then the account of what was measured
    % against what, V.ROWS numbers the comparisons rather than the
    % rows of A.grid.files behind them, and V.COMPARISON says which
    % operation was taken across which field.

    [idx, Y, x] = obj.currentView();

    v = struct();
    v.depth = x;
    v.values = Y;
    v.rows = idx;
    v.sections = obj.View.Sections(idx, :);
    v.sectionNames = obj.View.Names(idx);
    v.peakDepth = obj.View.PeakX(idx);
    v.peakHeight = obj.View.PeakY(idx);
    v.metricName = string(obj.MetricDropDown.Value);
    v.metric = section_metrics(x, Y, v.metricName);
    v.comparison = obj.View.Comparison;
    v.unit = obj.Unit;
    v.settings = obj.captureSettings();

end
