function S = combine_values_csv(rootPath, options)
% combine_values_csv
%   S = combine_values_csv()
%   S = combine_values_csv(rootPath)
%   S = combine_values_csv(rootPath, metadataCSV = metadataPath)
%   S = combine_values_csv(rootPath, outCSV = outPath)
%
% Build a structured dataset from all *_values.csv files under a root folder.
% The output includes a combined table, per-file tracking, and diagnostics for
% skipped/error files so higher-level tools can continue on partial failures.
%
% Parameters
%   rootPath: Root folder containing values CSV files.
%   options.outCSV: Optional path to write the combined table.
%   options.metadataCSV: Optional metadata tracker CSV path.
%   options.continueOnError: Continue processing after file-level errors.
%   options.progressFcn: Optional callback progressFcn(iFile,nFiles,filePath).
%   options.cancelRequestedFcn: Optional callback that returns true to cancel.
%
% Returns
%   S: Struct with fields
%      - combined: Combined row-wise table across successfully processed files.
%      - files: Table describing each discovered file and processing result.
%      - diagnostics: Table of warnings/errors per file.
%      - metadata: Struct containing metadata load details.
%      - summary: Struct with aggregate counts and cancellation state.
%      - options: Resolved option values used for processing.

arguments
    rootPath (1,1) string = ""
    options.outCSV (1,1) string = ""
    options.metadataCSV (1,1) string = ""
    options.continueOnError (1,1) logical = true
    options.progressFcn = []
    options.cancelRequestedFcn = []
end

rootPath = resolve_root_path(rootPath);

if rootPath == ""
    S = initialize_output_struct(rootPath, options, load_metadata(""));
    return
end

resolvedOptions = options;
resolvedOptions.outCSV = string(options.outCSV);
resolvedOptions.metadataCSV = string(options.metadataCSV);

metadataInfo = load_metadata(resolvedOptions.metadataCSV);
% Match both "<base>_values.csv" and "<base>_proj_<ROI>values.csv", since the
% Fiji line-measure macro's suffix prompt does not always include the "_".
files = dir(fullfile(rootPath, "**", "*values.csv"));

S = initialize_output_struct(rootPath, resolvedOptions, metadataInfo);

if isempty(files)
    S.summary.nDiscoveredFiles = 0;
    return
end

nFiles = numel(files);
S.summary.nDiscoveredFiles = nFiles;

fileTables = cell(nFiles, 1);
fileRows = initialize_file_rows(nFiles);
diagRows = initialize_diag_rows(max(nFiles, 1));

nSucceeded = 0;
nFailed = 0;
nCancelled = 0;
diagCount = 0;

for iFile = 1:nFiles
    thisFilePath = string(fullfile(files(iFile).folder, files(iFile).name));
    thisFileName = string(files(iFile).name);

    fileRows(iFile).FileIndex = iFile;
    fileRows(iFile).FilePath = thisFilePath;
    fileRows(iFile).Filename = thisFileName;

    if has_callback(resolvedOptions.progressFcn)
        resolvedOptions.progressFcn(iFile, nFiles, thisFilePath);
    end

    if should_cancel(resolvedOptions.cancelRequestedFcn)
        nCancelled = nCancelled + 1;
        fileRows(iFile).Status = "cancelled";
        fileRows(iFile).Message = "Cancelled by request.";

        diagCount = diagCount + 1;
        diagRows(diagCount) = make_diagnostic_row(iFile, thisFilePath, thisFileName, ...
            "combine_values_csv:Cancelled", "Cancelled by request.", "cancel");
        break
    end

    try
        Ti = read_and_annotate_file(thisFilePath, thisFileName, iFile, metadataInfo);
        fileTables{iFile} = Ti;

        nSucceeded = nSucceeded + 1;
        fileRows(iFile).Status = "ok";
        fileRows(iFile).NRows = height(Ti);

    catch ME
        nFailed = nFailed + 1;
        fileRows(iFile).Status = "error";
        fileRows(iFile).Message = string(ME.message);

        diagCount = diagCount + 1;
        if diagCount > numel(diagRows)
            diagRows(diagCount) = make_diagnostic_row(NaN, "", "", "", "", "");
        end
        diagRows(diagCount) = make_diagnostic_row(iFile, thisFilePath, thisFileName, ...
            string(ME.identifier), string(ME.message), "file");

        if ~resolvedOptions.continueOnError
            break
        end
    end
end

validTables = fileTables(~cellfun(@isempty, fileTables));

if isempty(validTables)
    combined = table();
else
    combined = vertcat(validTables{:});
end

if resolvedOptions.outCSV ~= ""
    writetable(combined, resolvedOptions.outCSV);
end

S.combined = combined;
S.files = struct2table(fileRows);

if diagCount == 0
    S.diagnostics = table();
else
    S.diagnostics = struct2table(diagRows(1:diagCount));
end

S.summary.nSucceeded = nSucceeded;
S.summary.nFailed = nFailed;
S.summary.nCancelled = nCancelled;
S.summary.wasCancelled = nCancelled > 0;
S.summary.nCombinedRows = height(combined);

end

function rootPath = resolve_root_path(rootPath)
%RESOLVE_ROOT_PATH Resolve and validate rootPath input.

if rootPath == ""
    selectedFolder = uigetdir(pwd, "Select root folder containing *_values.csv files");

    if isequal(selectedFolder, 0)
        rootPath = "";
        return
    end

    rootPath = string(selectedFolder);
end

if rootPath == ""
    return
end

if ~isfolder(rootPath)
    error("combine_values_csv:InvalidRootPath", ...
        "rootPath is not a valid folder: %s", rootPath)
end

end

function S = initialize_output_struct(rootPath, options, metadataInfo)
%INITIALIZE_OUTPUT_STRUCT Build default output struct.

S = struct();
S.combined = table();
S.files = table();
S.diagnostics = table();
S.metadata = metadataInfo;
S.summary = struct( ...
    "rootPath", rootPath, ...
    "nDiscoveredFiles", 0, ...
    "nSucceeded", 0, ...
    "nFailed", 0, ...
    "nCancelled", 0, ...
    "wasCancelled", false, ...
    "nCombinedRows", 0);
S.options = options;

end

function rows = initialize_file_rows(n)
%INITIALIZE_FILE_ROWS Preallocate file status rows.

rows = repmat(struct( ...
    "FileIndex", NaN, ...
    "FilePath", "", ...
    "Filename", "", ...
    "Status", "pending", ...
    "NRows", 0, ...
    "Message", ""), n, 1);

end

function rows = initialize_diag_rows(n)
%INITIALIZE_DIAG_ROWS Preallocate diagnostic rows.

rows = repmat(struct( ...
    "FileIndex", NaN, ...
    "FilePath", "", ...
    "Filename", "", ...
    "Identifier", "", ...
    "Message", "", ...
    "Stage", ""), n, 1);

end

function row = make_diagnostic_row(fileIndex, filePath, filename, identifier, message, stage)
%MAKE_DIAGNOSTIC_ROW Create one diagnostic row.

row = struct( ...
    "FileIndex", fileIndex, ...
    "FilePath", filePath, ...
    "Filename", filename, ...
    "Identifier", identifier, ...
    "Message", message, ...
    "Stage", stage);

end

function tf = has_callback(cb)
%HAS_CALLBACK Validate callback handle.

tf = isa(cb, "function_handle");

end

function tf = should_cancel(cancelRequestedFcn)
%SHOULD_CANCEL Safely evaluate cancellation callback.

tf = false;

if ~has_callback(cancelRequestedFcn)
    return
end

try
    tf = logical(cancelRequestedFcn());
catch
    tf = false;
end

end

function metadataInfo = load_metadata(metadataCSV)
%LOAD_METADATA Load and normalize metadata inputs.

metadataInfo = struct();
metadataInfo.hasMetadata = false;
metadataInfo.metadataCSV = metadataCSV;
metadataInfo.table = table();
metadataInfo.imageStems = strings(0, 1);
metadataInfo.imageFilenameColumn = "Image Filename";

if metadataCSV == ""
    return
end

if ~isfile(metadataCSV)
    error("combine_values_csv:InvalidMetadataCSV", ...
        "metadataCSV is not a valid file: %s", metadataCSV)
end

metadataTable = read_metadata_csv(metadataCSV, metadataInfo.imageFilenameColumn);
metadataTable = normalize_table_strings(metadataTable);
metadataImageStems = normalize_image_stems(metadataTable.(metadataInfo.imageFilenameColumn));

validRows = ~ismissing(metadataImageStems) & metadataImageStems ~= "";
metadataTable = metadataTable(validRows, :);
metadataImageStems = metadataImageStems(validRows);

if isempty(metadataImageStems)
    error("combine_values_csv:NoMetadataFilenames", ...
        "No valid entries were found in metadataCSV column: %s", metadataInfo.imageFilenameColumn)
end

metadataInfo.hasMetadata = true;
metadataInfo.table = metadataTable;
metadataInfo.imageStems = metadataImageStems;

end

function Ti = read_and_annotate_file(filePath, filename, fileIndex, metadataInfo)
%READ_AND_ANNOTATE_FILE Read one values file and append parsed metadata.

Ti = readtable(filePath);
Ti = normalize_table_strings(Ti);
Ti = drop_annotation_columns(Ti);
nRows = height(Ti);

[~, stem] = fileparts(filename);

[stem, roi] = strip_values_suffix(stem);
fileInfo = parse_values_filename(stem, filename);

Ti.SourceFileIndex = repmat(fileIndex, nRows, 1);
Ti.SourceFilePath = repmat(filePath, nRows, 1);
Ti.Filename = repmat(filename, nRows, 1);
Ti.SubjectID = repmat(string(fileInfo.SubjectID), nRows, 1);
Ti.SampleID = repmat(string(fileInfo.SampleID), nRows, 1);
Ti.SectionID = repmat(string(fileInfo.SectionID), nRows, 1);
Ti.Hemisphere = repmat(string(fileInfo.Hemisphere), nRows, 1);
Ti.Stain = repmat(string(fileInfo.Stain), nRows, 1);
Ti.ZPlane = repmat(string(fileInfo.ZPlane), nRows, 1);
Ti.DateCode = repmat(string(fileInfo.DateCode), nRows, 1);
Ti.ImageNumber = repmat(string(fileInfo.ImageNumber), nRows, 1);
Ti.Protocol = repmat(string(fileInfo.Protocol), nRows, 1);
Ti.Series = repmat(string(fileInfo.Series), nRows, 1);
Ti.ROI = repmat(roi, nRows, 1);

if metadataInfo.hasMetadata
    metadataRow = match_metadata_row(metadataInfo.table, metadataInfo.imageStems, stem, filename);
    Ti = append_metadata_columns(Ti, metadataRow, nRows, metadataInfo.imageFilenameColumn);
end

end

function [stem, roi] = strip_values_suffix(stem)
%STRIP_VALUES_SUFFIX Remove the values/projection markers and extract the ROI.
% Tolerates both naming conventions produced by MACRO_Batch_LineMeasure:
%   <base>_values                 -> stem = <base>,  roi = ""
%   <base>_proj_values            -> stem = <base>,  roi = ""
%   <base>_proj_<ROI>_values      -> stem = <base>,  roi = <ROI>
%   <base>_proj_<ROI>values       -> stem = <base>,  roi = <ROI>   (missing "_")

stem = string(stem);

roiToken = regexp(stem, "_proj_(\w*?)_?values$", "tokens", "once");
roi = "";
if ~isempty(roiToken)
    roi = string(roiToken{1});
end

stem = regexprep(stem, "_?values$", "");
stem = regexprep(stem, "_proj\w*$", "");

end

function T = drop_annotation_columns(T)
%DROP_ANNOTATION_COLUMNS Remove columns that will be replaced by parsed annotations.
% Handles the case where a CSV already contains these columns and MATLAB has
% auto-renamed duplicates with _1, _2, ... suffixes (e.g. SubjectID_1).

annotationCols = ["SourceFileIndex", "SourceFilePath", "Filename", ...
    "SubjectID", "SampleID", "SectionID", "Hemisphere", "Stain", ...
    "ZPlane", "DateCode", "ImageNumber", "Protocol", "Series", "ROI"];

varNames = string(T.Properties.VariableNames);
toRemove = false(size(varNames));

for iCol = 1:numel(annotationCols)
    base = annotationCols(iCol);
    toRemove = toRemove | (varNames == base) | ~cellfun(@isempty, regexp(varNames, "^" + base + "_\d+$", "once"));
end

if any(toRemove)
    T = removevars(T, varNames(toRemove));
end

end

function T = normalize_table_strings(T)
%NORMALIZE_TABLE_STRINGS Convert text-like table variables to string arrays.

varNames = string(T.Properties.VariableNames);

for iVar = 1:numel(varNames)
    varName = varNames(iVar);
    column = T.(char(varName));

    if isstring(column)
        continue
    end

    if ischar(column) || iscellstr(column)
        T.(char(varName)) = string(column);
        continue
    end

    if iscell(column)
        isTextCell = cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)) || isempty(x), column);

        if all(isTextCell)
            T.(char(varName)) = string(column);
        end
    end
end

end

function metadataTable = read_metadata_csv(metadataCSV, imageFilenameColumn)
%READ_METADATA_CSV Read tracker CSV whose header may be preceded by blank rows.

lines = readlines(metadataCSV);
headerLine = find(contains(lines, imageFilenameColumn), 1, "first");

if isempty(headerLine)
    error("combine_values_csv:MissingImageFilenameColumn", ...
        "metadataCSV must contain a column named ""%s"".", imageFilenameColumn)
end

opts = detectImportOptions(metadataCSV, ...
    "NumHeaderLines", headerLine - 1, ...
    "VariableNamingRule", "preserve");
metadataTable = readtable(metadataCSV, opts);

if ~ismember(imageFilenameColumn, string(metadataTable.Properties.VariableNames))
    error("combine_values_csv:MissingImageFilenameColumn", ...
        "metadataCSV must contain a column named ""%s"".", imageFilenameColumn)
end

end

function fileInfo = parse_values_filename(stem, filename)
%PARSE_VALUES_FILENAME Parse metadata encoded in the values CSV filename.
% Parsing is performed from the right so SampleID may contain underscores.

parts = split(stem, "_");

if numel(parts) < 7
    error("combine_values_csv:InvalidFilename", ...
        "Filename does not match expected pattern: %s", filename)
end

samplePrefix = join(parts(1:end-6), "_");
subjectInfo = regexp(samplePrefix, "^(?<SubjectID>SUBJ-ID-[0-9]+)(?<SampleID>.*)$", "names");

if isempty(subjectInfo)
    error("combine_values_csv:InvalidFilename", ...
        "Filename does not match expected pattern: %s", filename)
end

fileInfo.SubjectID = string(subjectInfo.SubjectID);
fileInfo.SampleID = string(subjectInfo.SampleID);
fileInfo.SectionID = parts(end-5);
fileInfo.Hemisphere = parts(end-4);
fileInfo.Stain = parts(end-3);
fileInfo.ZPlane = parts(end-2);
fileInfo.DateCode = parts(end-1);
fileInfo.ImageNumber = parts(end);

sampleInfo = regexp(fileInfo.SampleID, "^(?<Protocol>.*?)\d{6}S(?<Series>\d+)$", "names");
if ~isempty(sampleInfo)
    fileInfo.Protocol = string(sampleInfo.Protocol);
    fileInfo.Series = string(sampleInfo.Series);
else
    fileInfo.Protocol = "";
    fileInfo.Series = "";
end

end

function stems = normalize_image_stems(names)
%NORMALIZE_IMAGE_STEMS Remove paths, extensions, and values-file suffixes.

names = strtrim(string(names));
stems = strings(size(names));

for iName = 1:numel(names)
    thisName = names(iName);

    if ismissing(thisName) || thisName == ""
        stems(iName) = "";
        continue
    end

    [~, baseName, ext] = fileparts(thisName);

    if ext == ""
        baseName = thisName;
    end

    stems(iName) = strip_values_suffix(baseName);
end

end

function metadataRow = match_metadata_row(metadataTable, metadataImageStems, stem, filename)
%MATCH_METADATA_ROW Find one tracker row corresponding to one values CSV.

stem = normalize_image_stems(stem);
isMatch = metadataImageStems == stem;

% Fallback where tracker entry is a true prefix of the image stem.
if ~any(isMatch)
    isMatch = false(size(metadataImageStems));

    for iRow = 1:numel(metadataImageStems)
        thisStem = metadataImageStems(iRow);

        if thisStem ~= "" && startsWith(stem, thisStem + "_")
            isMatch(iRow) = true;
        end
    end
end

matchIdx = find(isMatch);

if isempty(matchIdx)
    error("combine_values_csv:NoMetadataMatch", ...
        "No row in metadataCSV matched filename: %s", filename)
end

if numel(matchIdx) > 1
    error("combine_values_csv:MultipleMetadataMatches", ...
        "Multiple rows in metadataCSV matched filename: %s", filename)
end

metadataRow = metadataTable(matchIdx, :);

end

function T = append_metadata_columns(T, metadataRow, nRows, imageFilenameColumn)
%APPEND_METADATA_COLUMNS Append non-key metadata columns to every row of T.

metadataVars = string(metadataRow.Properties.VariableNames);
metadataVars = metadataVars(metadataVars ~= imageFilenameColumn);
existingVars = string(T.Properties.VariableNames);

for iVar = 1:numel(metadataVars)
    sourceName = metadataVars(iVar);
    outputName = sourceName;

    if any(existingVars == outputName)
        outputName = sourceName + "_metadata";
    end

    suffixNumber = 2;
    while any(existingVars == outputName)
        outputName = sourceName + "_metadata" + suffixNumber;
        suffixNumber = suffixNumber + 1;
    end

    value = metadataRow.(char(sourceName));

    if ischar(value) || iscellstr(value) || isstring(value)
        value = string(value);
    end

    T.(char(outputName)) = repmat(value, nRows, 1);
    existingVars(end + 1) = outputName; %#ok<AGROW>
end

end
