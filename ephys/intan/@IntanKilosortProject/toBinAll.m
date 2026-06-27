function infos = toBinAll(obj, varargin)
%toBinAll  Stream a Kilosort4 .bin for every dataset in the project.
%   INFOS = P.toBinAll() loops over P.Datasets and calls toBin on each,
%   returning a struct array of the per-dataset results. Any name-value
%   arguments are forwarded verbatim to IntanDataset.toBin (e.g. Filter=true,
%   ChannelOrder=..., Blank=true). Errors on one dataset are caught and logged
%   so the batch continues; the failing entry's info is [] with an .error.
%
%   INFOS(i) has fields: Name, info (the toBin result struct or []), error.
%
%   See also IntanDataset.toBin.

n = obj.NumDatasets;
infos = struct('Name', {}, 'info', {}, 'error', {});
for i = 1:n
    d = obj.Datasets(i);
    fprintf('[%d/%d] toBin: %s\n', i, n, d.Name);
    try
        info = d.toBin(varargin{:});
        infos(i) = struct('Name', d.Name, 'info', info, 'error', "");
    catch ME
        warning('IntanKilosortProject:toBinFailed', ...
            'toBin failed for %s: %s', d.Name, ME.message);
        infos(i) = struct('Name', d.Name, 'info', [], 'error', string(ME.message));
    end
end
end
