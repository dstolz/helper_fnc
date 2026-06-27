function results = runKilosortAll(obj, varargin)
%runKilosortAll  Launch Kilosort4 for every dataset in the project.
%   RESULTS = P.runKilosortAll() loops over P.Datasets and calls runKilosort on
%   each, returning a struct array of the per-dataset results. Any name-value
%   arguments are forwarded verbatim to IntanDataset.runKilosort (e.g.
%   DryRun=true, ExtraSettings=...). Errors on one dataset are caught and logged
%   so the batch continues.
%
%   RESULTS(i) has fields: Name, result (the runKilosort struct or []), error.
%
%   See also IntanDataset.runKilosort.

n = obj.NumDatasets;
results = struct('Name', {}, 'result', {}, 'error', {});
for i = 1:n
    d = obj.Datasets(i);
    fprintf('[%d/%d] runKilosort: %s\n', i, n, d.Name);
    try
        res = d.runKilosort(varargin{:});
        results(i) = struct('Name', d.Name, 'result', res, 'error', "");
    catch ME
        warning('IntanKilosortProject:runKilosortFailed', ...
            'runKilosort failed for %s: %s', d.Name, ME.message);
        results(i) = struct('Name', d.Name, 'result', [], 'error', string(ME.message));
    end
end
end
