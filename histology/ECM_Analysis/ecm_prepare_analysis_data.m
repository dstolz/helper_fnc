function A = ecm_prepare_analysis_data(S, options)
% ecm_prepare_analysis_data
%   A = ecm_prepare_analysis_data(S)
%   A = ecm_prepare_analysis_data(S, peakRange = [0 300], smoothingWindow = 50)
%
% Derive aligned and grouped ECM analysis tables from structured combiner output.
%
% Parameters
%   S: Structured output from combine_values_csv.
%   options.distanceVar: Variable name for distance values.
%   options.intensityVar: Variable name for intensity values.
%   options.fileVar: Variable name for unique file identity.
%   options.groupVars: Grouping variable names for aggregate summaries.
%   options.peakRange: [min max] range for peak search in distance units.
%   options.smoothingMethod: Method passed to smoothdata.
%   options.smoothingWindow: Window size passed to smoothdata.
%   options.errorMetric: sem, std, or ci95.
%   options.normalizeMode: none, zscore, or minmax.
%
% Returns
%   A: Struct containing aligned point-level data and summary tables.

arguments
    S struct
    options.distanceVar (1,1) string = ""
    options.intensityVar (1,1) string = ""
    options.fileVar (1,1) string = ""
    options.distanceVarCandidates (1,:) string = ["distance_pixel_index", "distance", "Distance", "x"]
    options.intensityVarCandidates (1,:) string = ["intensity", "MeanIntensity", "Intensity", "y"]
    options.fileVarCandidates (1,:) string = ["Filename", "SourceFilePath", "ImageFilename", "Image Filename"]
    options.groupVars (1,:) string = ["SubjectID", "Atlas Plate #", "Hemisphere"]
    options.peakRange (1,2) double = [0 300]
    options.smoothingMethod (1,1) string = "gaussian"
    options.smoothingWindow (1,1) double {mustBePositive,mustBeFinite} = 50
    options.errorMetric (1,1) string {mustBeMember(options.errorMetric,["sem","std","ci95"])} = "sem"
    options.normalizeMode (1,1) string {mustBeMember(options.normalizeMode,["none","zscore","minmax"])} = "none"
end

if ~isfield(S, "combined") || ~istable(S.combined)
    error("ecm_prepare_analysis_data:InvalidInput", ...
        "Input S must contain a table field named combined.")
end

T = S.combined;

varNames = string(T.Properties.VariableNames);

distanceVar = resolve_variable_name(options.distanceVar, options.distanceVarCandidates, varNames, "distance");
intensityVar = resolve_variable_name(options.intensityVar, options.intensityVarCandidates, varNames, "intensity");
fileVar = resolve_variable_name(options.fileVar, options.fileVarCandidates, varNames, "file");

requiredVars = [distanceVar, intensityVar, fileVar];
missingVars = requiredVars(requiredVars == "");

if ~isempty(missingVars)
    error("ecm_prepare_analysis_data:MissingVariables", ...
        "Could not resolve required variables. Missing roles: %s", strjoin(missingVars, ", "))
end

groupVars = options.groupVars;
groupVars = groupVars(ismember(groupVars, varNames));

missingGroupVars = setdiff(options.groupVars, groupVars);

if isempty(groupVars)
    error("ecm_prepare_analysis_data:NoGroupVars", ...
        "None of the selected grouping variables were found in the combined table.")
end

fileIds = unique(string(T.(fileVar)));
pointTables = cell(numel(fileIds), 1);
peakRows = repmat(struct("Filename", "", "PeakX", NaN, "PeakY", NaN, "NPoints", 0), numel(fileIds), 1);

for iFile = 1:numel(fileIds)
    thisFile = fileIds(iFile);
    idxFile = string(T.(fileVar)) == thisFile;
    Tf = T(idxFile, :);

    x = double(Tf.(distanceVar));
    y = double(Tf.(intensityVar));

    valid = isfinite(x) & isfinite(y);
    x = x(valid);
    y = y(valid);

    if isempty(x)
        continue
    end

    [x, ix] = sort(x);
    y = y(ix);

    ySmooth = smoothdata(y, options.smoothingMethod, max(1, round(options.smoothingWindow)));

    switch options.normalizeMode
        case "zscore"
            ySmooth = normalize(ySmooth, "zscore");
        case "minmax"
            mn = min(ySmooth);
            mx = max(ySmooth);
            if mx > mn
                ySmooth = (ySmooth - mn) ./ (mx - mn);
            else
                ySmooth = zeros(size(ySmooth));
            end
    end

    inPkRange = x >= options.peakRange(1) & x <= options.peakRange(2);

    if any(inPkRange)
        yRange = ySmooth(inPkRange);
        xRange = x(inPkRange);
        [peakY, kRange] = max(yRange);
        peakX = xRange(kRange);
    else
        [peakY, kAll] = max(ySmooth);
        peakX = x(kAll);
    end

    alignedX = x - peakX;

    Tout = Tf(valid, :);
    Tout = Tout(ix, :);
    Tout.aligned_distance = alignedX;
    Tout.intensity_raw = y;
    Tout.intensity_smoothed = ySmooth;

    pointTables{iFile} = Tout;

    peakRows(iFile).Filename = thisFile;
    peakRows(iFile).PeakX = peakX;
    peakRows(iFile).PeakY = peakY;
    peakRows(iFile).NPoints = numel(x);
end

pointTables = pointTables(~cellfun(@isempty, pointTables));
peakRows = peakRows(~cellfun(@isempty, {peakRows.Filename}));

if isempty(pointTables)
    alignedTable = table();
else
    alignedTable = vertcat(pointTables{:});
end

if isempty(peakRows)
    peakTable = table();
else
    peakTable = struct2table(peakRows);
end

if isempty(alignedTable)
    groupedTable = table();
else
    groupCols = [groupVars, "aligned_distance"];
    [G, groupedTable] = findgroups(alignedTable(:, groupCols));

    ySm = alignedTable.intensity_smoothed;
    n = splitapply(@numel, ySm, G);
    m = splitapply(@mean, ySm, G);
    sd = splitapply(@std, ySm, G);

    switch options.errorMetric
        case "sem"
            e = sd ./ sqrt(n);
        case "std"
            e = sd;
        case "ci95"
            e = 1.96 * (sd ./ sqrt(n));
    end

    groupedTable.mean_intensity = m;
    groupedTable.error_intensity = e;
    groupedTable.n = n;
end

A = struct();
A.options = options;
A.resolvedVariables = struct( ...
    "distanceVar", distanceVar, ...
    "intensityVar", intensityVar, ...
    "fileVar", fileVar);
A.validation = struct( ...
    "missingGroupVars", missingGroupVars, ...
    "selectedGroupVars", groupVars, ...
    "availableVariables", varNames);
A.groupVars = groupVars;
A.aligned = alignedTable;
A.peaks = peakTable;
A.grouped = groupedTable;

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
