function A = ecm_prepare_analysis_data(S, options)
% ecm_prepare_analysis_data
%   A = ecm_prepare_analysis_data(S)
%   A = ecm_prepare_analysis_data(S, peakRange = [0 300], smoothingWindow = 50)
%
% Derive aligned and grouped ECM analysis tables from structured combiner output.
%
% Parameters
%   S: Structured output from combine_values_csv.
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
    options.fileVar (1,1) string = ""
    options.groupVars (1,:) string = ["SubjectID", "Atlas Plate #", "Hemisphere"]
    options.surfaceThreshold (1,1) double {mustBeNonnegative,mustBeFinite} = 1
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

distanceVar = "distance_pixel_index";
intensityVar = "intensity";
fileVar = "Filename";


groupVars = options.groupVars;
groupVars = groupVars(ismember(groupVars, varNames));


if isempty(groupVars)
    error("ecm_prepare_analysis_data:NoGroupVars", ...
        "None of the selected grouping variables were found in the combined table.")
end

fileIds = unique(string(T.(fileVar)));
pointTables = cell(numel(fileIds), 1);
peakRows = repmat(struct("Filename", "", "PeakX", NaN, "PeakY", NaN, "NPoints", 0), numel(fileIds), 1);

for iFile = 1:numel(fileIds)
    try
        thisFile = fileIds(iFile);
        idxFile = string(T.(fileVar)) == thisFile;
        Tf = T(idxFile, :);

        fprintf('Processing file %d of %d: %s',iFile,numel(fileIds),thisFile)

        x = double(Tf.(distanceVar));
        y = double(Tf.(intensityVar));

        valid = isfinite(x) & isfinite(y);
        x = x(valid);
        y = y(valid);

        if isempty(x)
            continue
        end

        [x, sortIdx] = sort(x);
        y = y(sortIdx);

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


        yRange = y(x < min(500,length(x)));
        ix = find(yRange < options.surfaceThreshold,1,'last');
        xSurface = x(ix);



        alignedX = x - xSurface;

        inPeakRange = alignedX >= options.peakRange(1) & alignedX <= options.peakRange(2);
        if any(inPeakRange)
            [peakY, iPeak] = max(ySmooth(inPeakRange));
            peakXVec = alignedX(inPeakRange);
            peakX = peakXVec(iPeak);
        else
            peakX = NaN;
            peakY = NaN;
        end

        fileHash = filename_hash(thisFile);

        Tout = Tf(valid, :);
        Tout = Tout(sortIdx, :);
        Tout.file_id = repmat(fileHash, height(Tout), 1);
        Tout.aligned_distance = alignedX;
        Tout.intensity_raw = y;
        Tout.intensity_smoothed = ySmooth;

        pointTables{iFile} = Tout;

        peakRows(iFile).Filename = thisFile;
        peakRows(iFile).PeakX = peakX;
        peakRows(iFile).PeakY = peakY;
        peakRows(iFile).NPoints = numel(x);

    catch me
        fprintf(2,' ... Failed')
    end

    fprintf('\n')
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
A.groupVars = groupVars;
A.aligned = alignedTable;
A.peaks = peakTable;
A.grouped = groupedTable;

end

function h = filename_hash(str)
%FILENAME_HASH Return an 8-character lowercase hex hash of a string.
md = java.security.MessageDigest.getInstance('MD5');
md.update(unicode2native(char(str), 'UTF-8'));
bytes = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(bytes(1:4))', 1, []));
h = string(h);
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
