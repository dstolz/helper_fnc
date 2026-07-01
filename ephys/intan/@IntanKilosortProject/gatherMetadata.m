function T = gatherMetadata(obj, opts)
%gatherMetadata  Parse headers for every dataset and return a summary table.
%   T = P.gatherMetadata() calls refreshMetadata on each dataset (header-only;
%   no amplifier data is read) and returns a table with one row per dataset:
%     Name, Folder, NumFiles, NumChannels, Fs, Duration, AcqDate,
%     ChannelNames, HasProbe, BinExists, HasKilosort
%
%   HasProbe/BinExists test the dataset's assigned probe and canonical .bin
%   path; HasKilosort comes from the dataset's DatasetTracker (true when any
%   kilosort4 run under its output folder produced spike results).
%
%   T = P.gatherMetadata(Force=true) re-parses even datasets that already have
%   metadata.
%
%   See also IntanDataset.refreshMetadata, IntanDataset.tracker,
%   IntanKilosortProject.discover.

arguments
    obj (1,1) IntanKilosortProject
    opts.Force (1,1) logical = false
end

n = obj.NumDatasets;
if n == 0
    T = table();
    warning('IntanKilosortProject:NoDatasets', 'No datasets to summarize.');
    return
end

Name        = strings(n, 1);
Folder      = strings(n, 1);
NumFiles    = zeros(n, 1);
NumChannels = zeros(n, 1);
Fs          = zeros(n, 1);
Duration    = zeros(n, 1);
AcqDate     = NaT(n, 1);
ChannelNames = cell(n, 1);
HasProbe    = false(n, 1);
BinExists   = false(n, 1);
HasKilosort = false(n, 1);

for i = 1:n
    d = obj.Datasets(i);
    if opts.Force || isnan(d.Fs)
        d.refreshMetadata();
    end
    Name(i)        = d.Name;
    Folder(i)      = d.Folder;
    NumFiles(i)    = d.NumFiles;
    NumChannels(i) = d.NumChannels;
    Fs(i)          = d.Fs;
    Duration(i)    = d.Duration;
    AcqDate(i)     = d.AcqDate;
    ChannelNames{i} = d.ChannelNames;
    HasProbe(i)    = d.ProbeFile ~= "" && isfile(d.ProbeFile);
    BinExists(i)   = isfile(d.BinFile);
    HasKilosort(i) = d.tracker().hasKilosort();
end

T = table(Name, Folder, NumFiles, NumChannels, Fs, Duration, AcqDate, ...
    ChannelNames, HasProbe, BinExists, HasKilosort);
end
