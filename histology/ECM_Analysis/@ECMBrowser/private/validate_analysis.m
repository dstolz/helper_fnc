function A = validate_analysis(A)
%VALIDATE_ANALYSIS Refuse anything that is not a populated analysis struct.

required = ["grid", "peaks", "aligned"];
missingFields = required(~isfield(A, required));

if ~isempty(missingFields)
    error("ECMBrowser:NotAnalysisStruct", ...
        "Expected the struct returned by ecm_prepare_analysis_data. Missing: %s", ...
        strjoin(missingFields, ", "))
end

if isempty(A.grid.depth) || isempty(A.grid.files)
    error("ECMBrowser:NothingToBrowse", ...
        "This analysis holds no profiles. Check A.diagnostics for why.")
end

end
