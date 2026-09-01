function A = ecm_prepare_analysis_data(T, options)
% ecm_prepare_analysis_data
%   A = ecm_prepare_analysis_data(T)
%   A = ecm_prepare_analysis_data(T, peakRange = [0 800], smoothingWindow = 25)
%
% Derive surface-aligned, grouped ECM analysis tables from the section table
% the histology browser exports.
%
% T carries one row per section with the measured line profile packed into a
% single cell holding a two-column table of distance and intensity (see
% HistologyImageBrowser/onExportWorkspace). A long, one-row-per-sample table is
% also accepted: when no profile column is found the distance and intensity
% samples are read from T directly and the rows are grouped by fileVar.
%
% Every variable this function reads is an option. The name defaults are ""
% meaning "resolve against the candidates this export is known to use", so the
% same call works on either layout; naming a variable that is not there is an
% error rather than a silent fallback.
%
% Distances are used in whatever unit the profile was measured in -- microns
% for a calibrated image, pixels for one without -- so surfaceSearch,
% peakRange, depthRange, binStep, and a distance-unit smoothing window are all
% in that same unit.
%
% Parameters
%   options.fileVar: Variable naming one profile's section. "" resolves to the
%       first of Stem, ImagePath, Filename, SourceFilePath, FilePath.
%   options.groupVars: Grouping variable names for the aggregate summary.
%       Names not present in T are dropped.
%   options.keepVars: Section variables copied onto every sample of the aligned
%       table. "all" keeps every non-cell variable except the profile itself.
%   options.profileVar: Cell variable holding the per-section profile tables.
%       "" resolves to Profile, and to "" (long layout) when there is none.
%   options.distanceVar: Distance variable inside the profile (nested layout)
%       or in T (long layout). "" resolves to the first of Distance, distance,
%       distance_pixel_index, distance_um, Distance_um.
%   options.intensityVar: Intensity variable, resolved the same way from
%       Intensity, intensity, Mean, mean, intensity_raw.
%   options.surfaceMode: How the cortical surface is found in each profile.
%       threshold -- last sample below surfaceThreshold, i.e. the last
%           background sample before the tissue starts (the line ROI is drawn
%           from off-section inward, so these profiles open on zeros).
%       fraction -- first sample reaching surfaceThreshold of the profile's own
%           range within the search window, for profiles with no true zero.
%       gradient -- steepest rise of the smoothed profile in the window.
%       none -- no alignment; aligned distance is the measured distance.
%   options.surfaceThreshold: Intensity for threshold mode, or a 0-1 fraction
%       of the searched range for fraction mode.
%   options.surfaceSearch: [min max] distance window the surface is looked for
%       in, measured from the start of the profile.
%   options.surfaceFallback: What a profile with no detectable surface does.
%       first -- align on its first sample. none -- leave it unaligned.
%       skip -- drop it, and say so in the diagnostics.
%   options.smoothingMethod: Method passed to smoothdata.
%   options.smoothingWindow: Window passed to smoothdata.
%   options.smoothingWindowUnit: samples, or distance to have the window read
%       in the profile's distance unit.
%   options.normalizeMode: none, zscore, or minmax. The transform is derived
%       from the smoothed profile and applied to both traces, so raw and
%       smoothed intensities stay on one scale.
%   options.peakRange: [min max] aligned distance searched for the peak.
%   options.peakSource: smoothed or raw trace the peak is taken from.
%   options.depthRange: [min max] aligned distance retained. Samples outside it
%       are dropped after alignment and before grouping.
%   options.binStep: Width of the depth bin samples are grouped and gridded on.
%       0 uses the median sample spacing, which leaves the native sampling
%       intact while making the bin edges shared across sections -- aligned
%       distances are differences of floating-point sample positions and do not
%       compare equal on their own.
%   options.errorMetric: sem, std, or ci95.
%   options.verbose: Print per-section progress.
%
% Returns
%   A: Struct with fields
%      - aligned: One row per retained sample: the section variables of
%        keepVars, file_id, distance, aligned_distance, depth_bin,
%        intensity_raw, and intensity_smoothed.
%      - peaks: One row per processed section: the section variables of
%        keepVars, file_id, surface distance, peak, and sample count.
%      - grouped: Mean, error, and n per group and depth bin.
%      - grid: Struct holding a common depth axis (depth) with every section
%        interpolated onto it (raw, smoothed, one column per section) and the
%        matching section rows (files), so profiles of unequal length can be
%        compared column-wise without re-interpolating.
%      - diagnostics: One row per input section with its status and message.
%      - vars: The variable names and layout that were resolved.
%      - options, groupVars: The resolved settings.
%
% See also HISTOLOGYIMAGEBROWSER, SMOOTHDATA, FINDGROUPS.

arguments
    T table
    options.fileVar (1,1) string = ""
    options.groupVars (1,:) string = ["SubjectID", "AtlasPlate", "Hemisphere"]
    options.keepVars (1,:) string = "all"
    options.profileVar (1,1) string = ""
    options.distanceVar (1,1) string = ""
    options.intensityVar (1,1) string = ""
    options.surfaceMode (1,1) string {mustBeMember(options.surfaceMode,["threshold","fraction","gradient","none"])} = "threshold"
    options.surfaceThreshold (1,1) double {mustBeNonnegative,mustBeFinite} = 1
    options.surfaceSearch (1,2) double = [0 500]
    options.surfaceFallback (1,1) string {mustBeMember(options.surfaceFallback,["first","none","skip"])} = "first"
    options.smoothingMethod (1,1) string = "gaussian"
    options.smoothingWindow (1,1) double {mustBePositive,mustBeFinite} = 50
    options.smoothingWindowUnit (1,1) string {mustBeMember(options.smoothingWindowUnit,["samples","distance"])} = "samples"
    options.normalizeMode (1,1) string {mustBeMember(options.normalizeMode,["none","zscore","minmax"])} = "none"
    options.peakRange (1,2) double = [0 Inf]
    options.peakSource (1,1) string {mustBeMember(options.peakSource,["smoothed","raw"])} = "smoothed"
    options.depthRange (1,2) double = [-Inf Inf]
    options.binStep (1,1) double {mustBeNonnegative} = 0
    options.errorMetric (1,1) string {mustBeMember(options.errorMetric,["sem","std","ci95"])} = "sem"
    options.verbose (1,1) logical = true
end

vars = resolve_variables(T, options);

groupVars = options.groupVars(ismember(options.groupVars, string(T.Properties.VariableNames)));

if isempty(groupVars)
    error("ecm_prepare_analysis_data:NoGroupVars", ...
        "None of the selected grouping variables were found in the section table.")
end

keepVars = resolve_keep_vars(T, options.keepVars, vars, groupVars);

% One entry per profile: the row of T it came from in the nested layout, every
% row of one file in the long one. Both are read through the same loop below.
fileGroups = group_rows(T, vars);
nFiles = numel(fileGroups);

pointTables = cell(nFiles, 1);
peakRows = cell(nFiles, 1);
diagRows = repmat(struct("FileIndex", 0, "FileID", "", "Status", "pending", ...
    "Message", "", "NSamples", 0, "SurfaceFound", false), nFiles, 1);

for iFile = 1:nFiles
    rowIdx = fileGroups{iFile};
    thisId = string(T.(vars.file)(rowIdx(1)));

    diagRows(iFile).FileIndex = iFile;
    diagRows(iFile).FileID = thisId;

    if options.verbose
        fprintf("Processing profile %d of %d: %s", iFile, nFiles, thisId);
    end

    try
        [d, y] = read_samples(T, rowIdx, vars);

        finiteSample = isfinite(d) & isfinite(y);
        d = d(finiteSample);
        y = y(finiteSample);

        if isempty(d)
            diagRows(iFile).Status = "skipped";
            diagRows(iFile).Message = "No finite samples.";
            report_status(options.verbose, 1, " ... no finite samples");
            continue
        end

        [d, order] = sort(d);
        y = y(order);

        ySmooth = smooth_profile(d, y, options);

        [surfaceDistance, surfaceFound] = find_surface(d, y, ySmooth, options);
        diagRows(iFile).SurfaceFound = surfaceFound;

        if ~surfaceFound && options.surfaceFallback == "skip"
            diagRows(iFile).Status = "skipped";
            diagRows(iFile).Message = "No surface found in the search window.";
            report_status(options.verbose, 1, " ... no surface found");
            continue
        end

        alignedD = d - surfaceDistance;

        inDepth = alignedD >= options.depthRange(1) & alignedD <= options.depthRange(2);

        if ~any(inDepth)
            diagRows(iFile).Status = "skipped";
            diagRows(iFile).Message = "No samples inside depthRange.";
            report_status(options.verbose, 1, " ... outside depthRange");
            continue
        end

        [y, ySmooth] = normalize_profile(y, ySmooth, inDepth, options.normalizeMode);

        d = d(inDepth);
        alignedD = alignedD(inDepth);
        y = y(inDepth);
        ySmooth = ySmooth(inDepth);

        [peakX, peakY] = find_peak(alignedD, y, ySmooth, options);

        % The section columns, one copy per sample. In the long layout the
        % rows are already per-sample and are carried through the same
        % validity filter, sort, and depth trim as the samples themselves.
        if isscalar(rowIdx)
            meta = repmat(T(rowIdx, keepVars), numel(alignedD), 1);
        else
            meta = T(rowIdx, keepVars);
            meta = meta(finiteSample, :);
            meta = meta(order, :);
            meta = meta(inDepth, :);
        end

        meta.Properties.RowNames = {};

        meta.file_id = repmat(filename_hash(thisId), numel(alignedD), 1);
        meta.distance = d;
        meta.aligned_distance = alignedD;
        meta.intensity_raw = y;
        meta.intensity_smoothed = ySmooth;

        pointTables{iFile} = meta;

        % The same section columns the samples carry, so a section-level
        % question -- peak height by treatment, by infusion quality -- can be
        % asked of this table without joining back to T.
        peak = T(rowIdx(1), keepVars);
        peak.Properties.RowNames = {};
        peak.file_id = filename_hash(thisId);
        peak.SurfaceDistance = surfaceDistance;
        peak.SurfaceFound = surfaceFound;
        peak.PeakX = peakX;
        peak.PeakY = peakY;
        peak.NPoints = numel(alignedD);
        peakRows{iFile} = peak;

        diagRows(iFile).Status = "ok";
        diagRows(iFile).NSamples = numel(alignedD);
        report_status(options.verbose, 0, "");

    catch ME
        diagRows(iFile).Status = "error";
        diagRows(iFile).Message = string(ME.message);
        report_status(options.verbose, 2, " ... failed: " + string(ME.message));
    end
end

processed = ~cellfun(@isempty, pointTables);

if ~any(processed)
    alignedTable = table();
    peakTable = table();
else
    alignedTable = vertcat(pointTables{processed});
    peakTable = vertcat(peakRows{processed});
end

binStep = resolve_bin_step(options.binStep, pointTables(processed));

if ~isempty(alignedTable)
    alignedTable.depth_bin = round(alignedTable.aligned_distance ./ binStep) .* binStep;
    alignedTable = movevars(alignedTable, "depth_bin", After = "aligned_distance");
end

groupedTable = summarize_groups(alignedTable, groupVars, options.errorMetric);
grid = build_grid(pointTables(processed), peakTable, binStep);

A = struct();
A.options = options;
A.vars = vars;
A.groupVars = groupVars;
A.aligned = alignedTable;
A.peaks = peakTable;
A.grouped = groupedTable;
A.grid = grid;
A.diagnostics = struct2table(diagRows);

if options.verbose
    fprintf("Prepared %d of %d profiles (%d samples).\n", ...
        sum(processed), nFiles, height(alignedTable));
end

end

function vars = resolve_variables(T, options)
%RESOLVE_VARIABLES Settle which variables carry identity and samples.
% The layout is decided by whether a profile column is there, so one call
% handles both the nested export and a flattened one-row-per-sample table.

available = string(T.Properties.VariableNames);

vars = struct();
vars.file = resolve_variable_name(options.fileVar, ...
    ["Stem", "ImagePath", "Filename", "SourceFilePath", "FilePath"], available, "file identity");

if vars.file == ""
    error("ecm_prepare_analysis_data:NoFileVar", ...
        "No variable identifying each profile was found. Set fileVar.")
end

vars.profile = resolve_variable_name(options.profileVar, "Profile", available, "profile");

if vars.profile ~= "" && ~iscell(T.(vars.profile))
    error("ecm_prepare_analysis_data:InvalidProfileVar", ...
        "Profile variable ""%s"" must be a cell array of per-section tables.", vars.profile)
end

distanceCandidates = ["Distance", "distance", "distance_pixel_index", "distance_um", "Distance_um"];
intensityCandidates = ["Intensity", "intensity", "Mean", "mean", "intensity_raw"];

if vars.profile == ""
    vars.layout = "long";
    sampleVars = available;
else
    vars.layout = "nested";
    sampleVars = profile_variable_names(T.(vars.profile), vars.profile);
end

vars.distance = resolve_variable_name(options.distanceVar, distanceCandidates, sampleVars, "distance");
vars.intensity = resolve_variable_name(options.intensityVar, intensityCandidates, sampleVars, "intensity");

if vars.distance == "" || vars.intensity == ""
    error("ecm_prepare_analysis_data:NoSampleVars", ...
        "No distance and intensity variables were found in the %s layout. Set distanceVar and intensityVar.", ...
        vars.layout)
end

end

function sampleVars = profile_variable_names(profiles, profileVar)
%PROFILE_VARIABLE_NAMES Read the sample variable names off the first profile.

for iProfile = 1:numel(profiles)
    P = profiles{iProfile};

    if istable(P) || istimetable(P)
        if height(P) > 0 || width(P) > 0
            sampleVars = string(P.Properties.VariableNames);
            return
        end
    elseif isstruct(P) && ~isempty(fieldnames(P))
        sampleVars = string(fieldnames(P))';
        return
    end
end

error("ecm_prepare_analysis_data:EmptyProfiles", ...
    "Profile variable ""%s"" holds no readable profile table.", profileVar)

end

function keepVars = resolve_keep_vars(T, requested, vars, groupVars)
%RESOLVE_KEEP_VARS Choose the section columns carried onto every sample.
% "all" drops the cell columns -- the profile itself and the values-file list --
% because they are per-section containers that would be copied once per sample.

available = string(T.Properties.VariableNames);

if isscalar(requested) && requested == "all"
    isCellVar = varfun(@iscell, T, OutputFormat = "uniform");
    keepVars = available(~isCellVar);
else
    missingVars = requested(~ismember(requested, available));

    if ~isempty(missingVars)
        error("ecm_prepare_analysis_data:MissingKeepVars", ...
            "keepVars named variables that are not in the table: %s", strjoin(missingVars, ", "))
    end

    keepVars = requested;
end

% Identity and grouping have to survive whatever keepVars asked for, or the
% aligned table cannot be grouped or traced back to its sections.
keepVars = unique([vars.file, groupVars, keepVars], "stable");

if vars.layout == "long"
    keepVars = keepVars(~ismember(keepVars, [vars.distance, vars.intensity]));
else
    keepVars = keepVars(keepVars ~= vars.profile);
end

end

function fileGroups = group_rows(T, vars)
%GROUP_ROWS List the rows of T making up each profile.

if vars.layout == "nested"
    fileGroups = num2cell((1:height(T))');
    return
end

G = findgroups(string(T.(vars.file)));
fileGroups = splitapply(@(idx) {idx}, (1:height(T))', G);

end

function [d, y] = read_samples(T, rowIdx, vars)
%READ_SAMPLES Pull one profile's distance and intensity samples.

if vars.layout == "nested"
    P = T.(vars.profile){rowIdx};

    if isempty(P)
        d = zeros(0, 1);
        y = zeros(0, 1);
        return
    end

    d = double(P.(vars.distance));
    y = double(P.(vars.intensity));
else
    d = double(T.(vars.distance)(rowIdx));
    y = double(T.(vars.intensity)(rowIdx));
end

d = d(:);
y = y(:);

if numel(d) ~= numel(y)
    error("ecm_prepare_analysis_data:SampleCountMismatch", ...
        "Distance and intensity hold different numbers of samples (%d and %d).", numel(d), numel(y))
end

end

function ySmooth = smooth_profile(d, y, options)
%SMOOTH_PROFILE Smooth one profile in samples or in distance units.

if options.smoothingWindowUnit == "distance"
    ySmooth = smoothdata(y, options.smoothingMethod, options.smoothingWindow, SamplePoints = d);
    return
end

ySmooth = smoothdata(y, options.smoothingMethod, max(1, round(options.smoothingWindow)));

end

function [surfaceDistance, found] = find_surface(d, y, ySmooth, options)
%FIND_SURFACE Locate the tissue surface the depth axis is measured from.
% Returned as a distance along the profile, not an index, so the caller can
% subtract it whatever the sampling is.

surfaceDistance = 0;
found = true;

if options.surfaceMode == "none"
    return
end

inWindow = d - d(1) >= options.surfaceSearch(1) & d - d(1) <= options.surfaceSearch(2);

if ~any(inWindow)
    [surfaceDistance, found] = surface_fallback(d, options);
    return
end

dWindow = d(inWindow);

switch options.surfaceMode
    case "threshold"
        % The last background sample before the tissue: the line ROI starts
        % off-section, so a profile opens on a run of near-zero samples and
        % the tissue begins where that run ends.
        idx = find(y(inWindow) < options.surfaceThreshold, 1, "last");

    case "fraction"
        yWindow = ySmooth(inWindow);
        span = max(yWindow) - min(yWindow);

        if span <= 0
            idx = [];
        else
            idx = find(yWindow >= min(yWindow) + options.surfaceThreshold * span, 1, "first");
        end

    case "gradient"
        yWindow = ySmooth(inWindow);

        if numel(yWindow) < 3
            idx = [];
        else
            [~, idx] = max(gradient(yWindow, dWindow));
        end
end

if isempty(idx)
    [surfaceDistance, found] = surface_fallback(d, options);
    return
end

surfaceDistance = dWindow(idx);

end

function [surfaceDistance, found] = surface_fallback(d, options)
%SURFACE_FALLBACK Decide the offset of a profile with no detectable surface.

found = false;

switch options.surfaceFallback
    case "first"
        surfaceDistance = d(1);
    otherwise
        surfaceDistance = 0;
end

end

function [y, ySmooth] = normalize_profile(y, ySmooth, inDepth, normalizeMode)
%NORMALIZE_PROFILE Rescale both traces by one transform.
% The parameters come from the smoothed trace over the retained depth range so
% that noise and discarded samples outside the analysis window cannot set the
% scale, and both traces stay comparable on the same axis.

reference = ySmooth(inDepth);

switch normalizeMode
    case "zscore"
        centre = mean(reference, "omitnan");
        scale = std(reference, "omitnan");

    case "minmax"
        centre = min(reference);
        scale = max(reference) - centre;

    otherwise
        return
end

if ~isfinite(scale) || scale <= 0
    scale = 1;
end

y = (y - centre) ./ scale;
ySmooth = (ySmooth - centre) ./ scale;

end

function [peakX, peakY] = find_peak(alignedD, y, ySmooth, options)
%FIND_PEAK Take the maximum inside the peak search window.

if options.peakSource == "raw"
    trace = y;
else
    trace = ySmooth;
end

inPeakRange = alignedD >= options.peakRange(1) & alignedD <= options.peakRange(2);

if ~any(inPeakRange)
    peakX = NaN;
    peakY = NaN;
    return
end

[peakY, iPeak] = max(trace(inPeakRange));
peakXVec = alignedD(inPeakRange);
peakX = peakXVec(iPeak);

end

function binStep = resolve_bin_step(requested, pointTables)
%RESOLVE_BIN_STEP Settle the depth bin width shared by every profile.
% Aligned distances are differences of sampled positions, so two sections that
% sampled the same depth do not hold bit-identical values and cannot be grouped
% by equality. Binning at the native spacing groups them without resampling.

if requested > 0
    binStep = requested;
    return
end

steps = zeros(numel(pointTables), 1);

for iTable = 1:numel(pointTables)
    d = pointTables{iTable}.aligned_distance;

    if numel(d) > 1
        steps(iTable) = median(diff(d));
    end
end

steps = steps(steps > 0);

if isempty(steps)
    binStep = 1;
    return
end

binStep = median(steps);

end

function groupedTable = summarize_groups(alignedTable, groupVars, errorMetric)
%SUMMARIZE_GROUPS Average the smoothed profiles within each group and depth bin.

if isempty(alignedTable)
    groupedTable = table();
    return
end

groupCols = [groupVars, "depth_bin"];
[G, groupedTable] = findgroups(alignedTable(:, groupCols));

ySm = alignedTable.intensity_smoothed;
n = splitapply(@numel, ySm, G);
m = splitapply(@(v) mean(v, "omitnan"), ySm, G);
sd = splitapply(@(v) std(v, 0, "omitnan"), ySm, G);
mRaw = splitapply(@(v) mean(v, "omitnan"), alignedTable.intensity_raw, G);

switch errorMetric
    case "sem"
        e = sd ./ sqrt(n);
    case "std"
        e = sd;
    case "ci95"
        e = 1.96 * (sd ./ sqrt(n));
end

groupedTable.mean_intensity = m;
groupedTable.error_intensity = e;
groupedTable.mean_intensity_raw = mRaw;
groupedTable.n = n;

end

function grid = build_grid(pointTables, peakTable, binStep)
%BUILD_GRID Interpolate every profile onto one depth axis.
% Sections are sampled over different depths and lengths, so anything that
% compares them column-wise -- a mean across sections, a heatmap -- has to
% resample first. Doing it once here keeps that out of every caller, and NaN
% outside a section's own range keeps a short profile from being extrapolated
% into depths it never measured.

grid = struct("depth", zeros(0, 1), "raw", zeros(0, 0), "smoothed", zeros(0, 0), ...
    "files", table(), "binStep", binStep);

if isempty(pointTables)
    return
end

lo = Inf;
hi = -Inf;

for iTable = 1:numel(pointTables)
    d = pointTables{iTable}.aligned_distance;
    lo = min(lo, min(d));
    hi = max(hi, max(d));
end

if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    return
end

depth = (floor(lo / binStep) : ceil(hi / binStep))' * binStep;

raw = nan(numel(depth), numel(pointTables));
smoothed = nan(numel(depth), numel(pointTables));

for iTable = 1:numel(pointTables)
    P = pointTables{iTable};
    [d, iUnique] = unique(P.aligned_distance);

    if numel(d) < 2
        continue
    end

    raw(:, iTable) = interp1(d, P.intensity_raw(iUnique), depth, "linear", NaN);
    smoothed(:, iTable) = interp1(d, P.intensity_smoothed(iUnique), depth, "linear", NaN);
end

grid.depth = depth;
grid.raw = raw;
grid.smoothed = smoothed;
grid.files = peakTable;

end

function report_status(verbose, stream, message)
%REPORT_STATUS Close out one profile's progress line.
% Warnings go to stdout beside the line they belong to; only a failure is
% written to stderr, so a red line in the log is a profile that was lost.

if ~verbose
    return
end

if strlength(message) > 0
    if stream == 2
        fprintf(2, "%s", message);
    else
        fprintf("%s", message);
    end
end

fprintf("\n");

end

function h = filename_hash(str)
%FILENAME_HASH Return an 8-character lowercase hex hash of a string.
% FNV-1a rather than a MessageDigest, so the identity of a profile does not
% depend on the JVM being there.

bytes = double(unicode2native(char(str), "UTF-8"));

hash = uint64(14695981039346656037);
prime = uint64(1099511628211);

for iByte = 1:numel(bytes)
    hash = bitxor(hash, uint64(bytes(iByte)));
    hash = mod_multiply(hash, prime);
end

h = string(lower(dec2hex(bitand(bitshift(hash, -32), uint64(4294967295)), 8)));

end

function product = mod_multiply(a, b)
%MOD_MULTIPLY Multiply two uint64 values modulo 2^64 without saturating.
% MATLAB saturates integer arithmetic at INTMAX, so the 64-bit product is
% assembled from 32-bit halves and the terms that overflow are dropped.

mask = uint64(4294967295);

aLo = bitand(a, mask);
aHi = bitshift(a, -32);
bLo = bitand(b, mask);
bHi = bitshift(b, -32);

lo = aLo * bLo;
mid = bitand(aLo * bHi, mask) + bitand(aHi * bLo, mask);

product = bitand(lo, mask) + bitshift(bitand(bitshift(lo, -32) + mid, mask), 32);

end

function varName = resolve_variable_name(preferred, candidates, available, roleName)
%RESOLVE_VARIABLE_NAME Resolve a role to an existing variable name.

if preferred ~= ""
    if ismember(preferred, available)
        varName = preferred;
        return
    end

    error("ecm_prepare_analysis_data:MissingPreferredVariable", ...
        "Preferred %s variable was not found: %s", roleName, preferred)
end

for i = 1:numel(candidates)
    if ismember(candidates(i), available)
        varName = candidates(i);
        return
    end
end

varName = "";

end
