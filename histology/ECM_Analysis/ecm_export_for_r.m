function outFiles = ecm_export_for_r(matFile, outDir)
% ecm_export_for_r
%   outFiles = ecm_export_for_r(matFile, outDir)
%
% Flatten the ECM section table into plain CSVs that R (or anything else that
% is not MATLAB) can read.
%
% "ECM Projects - GM6001 - full.mat" carries a single 85x52 table variable that
% nests one 1148x2 (Distance, Intensity) profile table per section inside a
% cell. No flat format can hold that nesting, so writetable on it does not fail
% -- it silently emits 1148 empty fields per row and shifts every column after
% Profile out of alignment with the header, losing all 110762 samples. This
% unnests the profiles into a long, one-row-per-sample file instead, and writes
% the section-level metadata alongside it.
%
% Parameters
%   matFile: Path to the saved table. Defaults to the GM6001 full export.
%   outDir:  Where the CSVs go. Defaults to the folder holding matFile.
%
% Returns
%   outFiles: Struct with fields profiles and sections, the two paths written.

arguments
    matFile (1,1) string = "D:/GM6001_HISTOLOGY/ECM Projects - GM6001 - full.mat"
    outDir  (1,1) string = ""
end

if outDir == "", outDir = string(fileparts(matFile)); end
if ~isfolder(outDir), mkdir(outDir); end

S = load(matFile, '-mat');
fn = fieldnames(S);
isTbl = cellfun(@(f) istable(S.(f)), fn);
assert(any(isTbl), "ecm_export_for_r:noTable", ...
    "%s holds no table variable (found: %s).", matFile, strjoin(fn', ', '));
T = S.(fn{find(isTbl, 1)});

% Section metadata: everything that is one value per section. Cells hold the
% nested profile and the values-file paths, neither of which flattens.
meta = T(:, ~varfun(@iscell, T, OutputFormat = "uniform"));
for j = 1:width(meta)
    if isdatetime(meta.(j)), meta.(j) = string(meta.(j), "yyyy-MM-dd HH:mm:ss"); end
end

profFile = fullfile(outDir, "ECM Projects - GM6001 - profiles.csv");
sectFile = fullfile(outDir, "ECM Projects - GM6001 - sections.csv");

writetable(meta, sectFile);

% Long profiles: repeat each section's metadata across its samples. Sections
% differ in sample count, so build per section and stack.
assert(any(T.Properties.VariableNames == "Profile"), "ecm_export_for_r:noProfile", ...
    "The table has no Profile column to unnest.");
parts = cell(height(T), 1);
for i = 1:height(T)
    p = T.Profile{i};
    if isempty(p), continue; end
    n = height(p);
    part = repmat(meta(i, :), n, 1);
    part.SampleIndex = (1:n)';
    part.Distance    = p.Distance;
    part.Intensity   = p.Intensity;
    parts{i} = part;
end
long = vertcat(parts{:});
writetable(long, profFile);

fprintf("Wrote %s (%d rows x %d vars)\n", sectFile, height(meta), width(meta));
fprintf("Wrote %s (%d rows x %d vars)\n", profFile, height(long), width(long));

outFiles = struct(profiles = profFile, sections = sectFile);
end
