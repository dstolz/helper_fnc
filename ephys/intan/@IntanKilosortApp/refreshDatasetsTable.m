function refreshDatasetsTable(obj)
%refreshDatasetsTable  Rebuild the datasets table from project metadata.
%   Preserves the existing "Select" ticks where the row count is unchanged.

if isempty(obj.Project) || obj.Project.NumDatasets == 0
    obj.DatasetsTable.Data = table('Size', [0 12], ...
        'VariableTypes', {'logical','string','string','double','double', ...
                          'double','double','string','string','string', ...
                          'string','double'}, ...
        'VariableNames', {'Select','Name','AcqDate','NumFiles','NumChannels', ...
                          'Fs','DurationMin','Format','Probe','Exclude', ...
                          'Kilosort','DatasetIdx'});
    return
end

n = obj.Project.NumDatasets;

% Preserve prior selection ticks (matched by name, since sorting the table
% may have reordered rows relative to the last refresh).
prev = obj.DatasetsTable.Data;
Select = false(n, 1);
if istable(prev) && any(strcmp('Select', prev.Properties.VariableNames)) ...
        && any(strcmp('Name', prev.Properties.VariableNames))
    for i = 1:n
        m = strcmp(prev.Name, obj.Project.Datasets(i).Name);
        if any(m); Select(i) = prev.Select(find(m, 1)); end
    end
end

Name        = strings(n, 1);
AcqDate     = strings(n, 1);
NumFiles    = zeros(n, 1);
NumChannels = zeros(n, 1);
Fs          = zeros(n, 1);
DurationMin = zeros(n, 1);
Format      = strings(n, 1);
Probe       = strings(n, 1);
Exclude     = strings(n, 1);
Kilosort    = strings(n, 1);

for i = 1:n
    d = obj.Project.Datasets(i);
    Name(i)        = d.Name;
    Format(i)      = d.RecordingFormat;
    if ~isnat(d.AcqDate)
        AcqDate(i) = string(datetime(d.AcqDate, 'Format', 'yyyy-MM-dd HH:mm'));
    end
    NumFiles(i)    = d.NumFiles;
    NumChannels(i) = d.NumChannels;
    Fs(i)          = d.Fs;
    if ~isnan(d.Duration); DurationMin(i) = d.Duration / 60; end
    if d.ProbeFile ~= "" && isfile(d.ProbeFile)
        [~, pn, pe] = fileparts(d.ProbeFile);
        Probe(i) = pn + pe;
    else
        Probe(i) = "-";
    end
    if isempty(d.ExcludeChannels)
        Exclude(i) = "-";
    else
        Exclude(i) = IntanDataset.formatChannelList(d.ExcludeChannels);
    end
    % Cheap Kilosort4 status from the canonical results dir (no recursive scan
    % in this hot path; the manifest carries the full inventory). "results" when
    % spikes were written, "ready" when only params.py is present.
    if d.hasKilosortResults()
        Kilosort(i) = "results";
    elseif d.hasPhyOutput()
        Kilosort(i) = "ready";
    else
        Kilosort(i) = "-";
    end
end

% DatasetIdx records each row's position in obj.Project.Datasets so that row
% -> dataset lookups (currentDataset, selectedDatasetIndices) stay correct
% after the user sorts the table by clicking a column header.
DatasetIdx = (1:n)';

T = table(Select, Name, AcqDate, NumFiles, NumChannels, Fs, ...
    round(DurationMin, 2), Format, Probe, Exclude, Kilosort, DatasetIdx, ...
    'VariableNames', {'Select','Name','AcqDate','NumFiles','NumChannels', ...
                      'Fs','DurationMin','Format','Probe','Exclude', ...
                      'Kilosort','DatasetIdx'});
obj.DatasetsTable.Data = T;

% Keep "Open in phy" in sync with whatever is selected after the rebuild.
obj.updatePhyButtonState();
end
