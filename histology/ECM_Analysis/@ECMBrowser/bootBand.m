function [lo, hi] = bootBand(obj, M)
    %BOOTBAND A bootstrap interval for one group's mean at each depth.
    % The sections are what was sampled, so a resample draws whole
    % sections and is read at every depth at once. Resampling depth by
    % depth would put a different pretend group behind each point and
    % return a band narrower and smoother than the sections it came
    % from -- the profiles are one measurement down a section, not a
    % row of independent ones.
    %
    % The interval is the percentile one rather than BOOTCI's
    % bias-corrected default: it is read straight off the resampled
    % means, which is what the band is drawn to show and what a
    % methods line can state in a clause, and it spares a jackknife
    % pass over every group on every draw. BOOTCI belongs to the
    % Statistics and Machine Learning Toolbox, and without it -- or
    % on any other failure -- the band is left out, not the plot.

    nDepth = size(M, 1);
    [lo, hi] = deal(nan(nDepth, 1));

    if size(M, 2) < 2
        return
    end

    try
        ci = bootci(obj.BootReps, ...
            {@(sections) mean(sections, 1, "omitnan"), M.'}, ...
            "type", "percentile");
    catch
        return
    end

    lo = ci(1, :).';
    hi = ci(2, :).';

end
