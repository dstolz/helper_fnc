function refreshDatasetsTable(obj)
%refreshDatasetsTable  Rebuild the datasets table from project metadata.
%   Preserves the existing "Select" ticks where the row count is unchanged.

if isempty(obj.Project) || obj.Project.NumDatasets == 0
    obj.DatasetsTable.Data = table('Size', [0 10], ...
        'VariableTypes', {'logical','string','string','double','double', ...
                          'double','double','string','string','string'}, ...
        'VariableNames', {'Select','Name','AcqDate','NumFiles','NumChannels', ...
                          'Fs','DurationMin','Probe','Exclude','Bin'});
    return
end

n = obj.Project.NumDatasets;

% Preserve prior selection ticks when the row count matches.
prev = obj.DatasetsTable.Data;
Select = false(n, 1);
if istable(prev) && height(prev) == n && any(strcmp('Select', prev.Properties.VariableNames))
    Select = logical(prev.Select(:));
end

Name        = strings(n, 1);
AcqDate     = strings(n, 1);
NumFiles    = zeros(n, 1);
NumChannels = zeros(n, 1);
Fs          = zeros(n, 1);
DurationMin = zeros(n, 1);
Probe       = strings(n, 1);
Exclude     = strings(n, 1);
Bin         = strings(n, 1);

for i = 1:n
    d = obj.Project.Datasets(i);
    Name(i)        = d.Name;
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
    if isfile(d.BinFile); Bin(i) = "yes"; else; Bin(i) = "-"; end
end

T = table(Select, Name, AcqDate, NumFiles, NumChannels, Fs, ...
    round(DurationMin, 2), Probe, Exclude, Bin, ...
    'VariableNames', {'Select','Name','AcqDate','NumFiles','NumChannels', ...
                      'Fs','DurationMin','Probe','Exclude','Bin'});
obj.DatasetsTable.Data = T;
end
