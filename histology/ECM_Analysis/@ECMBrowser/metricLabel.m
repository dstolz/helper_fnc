function label = metricLabel(obj, metric)
    %METRICLABEL Name what one point of a metric summary measures.
    %   label = B.metricLabel()
    %   label = B.metricLabel("integral")
    %
    % The metrics are summaries of the curve on screen, so each one is
    % named in the units that curve is drawn in: the intensity ones
    % carry whatever the Signal and Normalize controls have made of the
    % intensity, and the depth ones the distance unit the profiles were
    % measured in. A metric that is neither -- an integral is one times
    % the other, a slope one over the other, a coefficient of variation
    % neither -- says so rather than borrowing a unit it does not have.
    %
    % See also SECTION_METRICS, LABELLAYOUT, WITHNORMALIZATION.

    arguments
        obj
        metric (1,1) string = string(obj.MetricDropDown.Value)
    end

    intensity = obj.withNormalization( ...
        string(obj.SignalDropDown.Value) + " intensity");

    % The unit written as a factor and as a divisor, for the two metrics
    % that are an intensity taken over a depth rather than at one. An
    % analysis that never recorded a distance unit leaves both empty,
    % and the label falls back to naming the quantity alone.
    if obj.Unit == "" || ismissing(obj.Unit)
        [times, per] = deal("");
    else
        times = " x " + obj.Unit;
        per = " per " + obj.Unit;
    end

    switch metric

        case "mean"
            label = "mean " + intensity;

        case "median"
            label = "median " + intensity;

        case "integral"
            label = "integral of " + intensity + times;

        case "peak height"
            label = "peak " + intensity;

        case "peak depth"
            label = obj.withUnit("peak depth from surface");

        case "peak1 - peak2 (height)"
            label = "peak1 - peak2, " + intensity;

        case "peak1 to peak2 (depth)"
            label = obj.withUnit("peak1 to peak2 separation");

        case "FWHM"
            label = obj.withUnit("full width at half maximum");

        case "centroid depth"
            label = obj.withUnit("centroid depth from surface");

        case "range (max - min)"
            label = "range of " + intensity;

        case "variance"
            label = "variance of " + intensity;

        case "std. dev."
            label = "std. dev. of " + intensity;

        case "coeff. of variation"
            label = "coefficient of variation";

        case "slope"
            label = "slope of " + intensity + per;

        otherwise
            label = metric;

    end

end
