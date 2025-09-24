function use_version(repoMainDir, tag, options)
% USE_VERSION Switch MATLAB path to a tagged release inside repoMainDir.
% If called with no inputs, a folder chooser opens (uigetdir), defaulting
% to the directory that contains use_version.m. If TAG is omitted/empty,
% a selection dialog (listdlg) lets you pick a release matching
% options.repoNameRoot under repoMainDir. Cancelling any dialog leaves the
% path unchanged. Hidden dot-folders (e.g., .git, .vscode) are excluded.

arguments
    repoMainDir (1,:) char = ''
    tag         (1,:) char = ''
    options.repoNameRoot (1,:) char = 'epsych2-'
    options.useGUI      (1,1) logical = false
end

% If no inputs, prompt for base folder (default to this file's directory)
if nargin == 0 || isempty(repoMainDir)
    startDir = fileparts(mfilename('fullpath'));
    p = uigetdir(startDir, 'Select repository main directory');
    if isequal(p,0)
        fprintf('Selection cancelled. No changes made.\n');
        return
    end
    repoMainDir = p;
end

% If TAG not provided/empty, force GUI selection
if isempty(tag)
    options.useGUI = true;
end

% Resolve target release directory
if options.useGUI
    dlist = dir(fullfile(repoMainDir, [options.repoNameRoot '*']));
    dlist = dlist([dlist.isdir]);
    names = {dlist.name};
    if isempty(names)
        error('use_version:NoReleases', 'No release directories found in %s with prefix %s.', ...
              repoMainDir, options.repoNameRoot)
    end
    [idx, ok] = listdlg('ListString', names, 'SelectionMode','single', ...
                        'PromptString','Select a release', 'ListSize',[320 420]);
    if ~ok || isempty(idx)
        fprintf('Selection cancelled. No changes made.\n');
        return
    end
    relName = names{idx};
    d = fullfile(repoMainDir, relName);
else
    d = fullfile(repoMainDir, [options.repoNameRoot tag]);
end

if ~isfolder(d)
    error('use_version:MissingDir','Release directory not found: %s', d)
end

% Remove any existing paths that include a path segment starting with repoNameRoot
curp = strsplit(path, pathsep);
for i = 1:numel(curp)
    pth = curp{i};
    if isempty(pth), continue, end
    segs = regexp(pth, '[\\/]', 'split');
    if any(startsWith(segs, options.repoNameRoot))
        rmpath(pth)
    end
end

% Build filtered subpaths under d, excluding any segment starting with '.'
allp = genpath(d);
subpaths = strsplit(allp, pathsep);
subpaths = subpaths(~cellfun('isempty', subpaths));
keep = true(size(subpaths));
for i = 1:numel(subpaths)
    segs = regexp(subpaths{i}, '[\\/]', 'split');
    if any(startsWith(segs, '.'))
        keep(i) = false; % drop hidden/dot folders
    end
end
subpaths = subpaths(keep);

% Add selected release (filtered) to path
if ~isempty(subpaths)
    addpath(subpaths{:})
else
    addpath(d)
end
rehash toolboxcache

fprintf('Using %s\n', d)
