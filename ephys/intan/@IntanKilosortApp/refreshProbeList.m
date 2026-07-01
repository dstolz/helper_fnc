function refreshProbeList(obj)
%refreshProbeList  Populate the probe table from the probe folder.
%   One row per *.json, with parsed channel/shank/depth metadata and the
%   optional "notes" field. Full paths are kept in obj.ProbePaths (the table
%   shows only file names); the previously selected probe stays selected when
%   it still exists.

folder = string(obj.ProbeFolderField.Value);
if folder == "" || ~isfolder(folder)
    folder = string(obj.defaultProbeFolder());
    obj.ProbeFolderField.Value = char(folder);
end

prevSel = obj.selectedProbeFile();   % keep selection across refresh if possible

D = dir(fullfile(folder, '*.json'));
names = string({D.name});
if isempty(names)
    obj.ProbeTable.Data = emptyProbeTable();
    obj.ProbePaths = string.empty(1, 0);
    obj.SelectedProbeRow = 0;
    obj.ProbeInfoLabel.Text = sprintf("No .json probe files in:\n%s", folder);
    obj.ProbeCheckLabel.Text = "";
    cla(obj.ProbePreviewAxes);
    return
end

paths = fullfile(folder, names);
n = numel(names);
Probe  = strings(n, 1);
Ch     = nan(n, 1);
Shanks = nan(n, 1);
Depth  = nan(n, 1);
Notes  = strings(n, 1);
for i = 1:n
    Probe(i) = names(i);
    m = readProbeMeta(paths(i));
    Ch(i)     = m.nChan;
    Shanks(i) = m.nShank;
    Depth(i)  = m.depth;
    Notes(i)  = m.notes;
end

obj.ProbeTable.Data = table(Probe, Ch, Shanks, round(Depth), Notes, ...
    'VariableNames', {'Probe', 'Ch', 'Shanks', 'Depth', 'Notes'});
obj.ProbePaths = paths(:).';

% Restore the prior selection, else default to the first probe.
row = find(obj.ProbePaths == prevSel, 1);
if isempty(row); row = 1; end
obj.selectProbeRow(row);
end


function m = readProbeMeta(pf)
%readProbeMeta  Channel/shank/depth/notes via the shared DatasetTracker parser.
%   Unreadable files are flagged "(invalid JSON)" so they still show in the
%   probe table. The actual parsing lives in DatasetTracker so the Probe tab
%   and the dataset inventory stay in lockstep.
probe = DatasetTracker.readJson(pf);
if isempty(probe)
    m = struct('nChan', NaN, 'nShank', NaN, 'depth', NaN, 'notes', "(invalid JSON)");
    return
end
m = DatasetTracker.probeMeta(probe);
end


function T = emptyProbeTable()
%emptyProbeTable  Zero-row table matching the ProbeTable schema.
T = table('Size', [0 5], ...
    'VariableTypes', {'string', 'double', 'double', 'double', 'string'}, ...
    'VariableNames', {'Probe', 'Ch', 'Shanks', 'Depth', 'Notes'});
end
