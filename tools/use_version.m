function use_version(rootDir, tag, options)
% USE_VERSION Switch MATLAB path to a a version within rootDir.
% If called with no inputs, a folder chooser opens (uigetdir), defaulting
% to the hardcoded directory (or cd as fallback). If TAG is omitted/empty,
% a selection dialog (listdlg) lets you pick a version matching
% the repoNameRoot option under rootDir. Cancelling any dialog leaves the
% path unchanged. Hidden dot-folders (e.g., .git, .vscode) are excluded.

arguments
    rootDir (1,:) char = ''
    tag         (1,:) char = ''
    options.repoNameRoot (1,:) char = 'epsych2-'
    options.useGUI      (1,1) logical = false
end

% If no inputs, prompt for base folder (default to this file's directory)
if nargin == 0 || isempty(rootDir)
    startDir = "c:\src\versions";
    if ~isfolder(startDir), startDir = cd; end
    p = uigetdir(startDir, 'Select repository main directory');
    if isequal(p,0)
        fprintf('Selection cancelled. No changes made.\n');
        return
    end
    rootDir = p;
end

% If TAG not provided/empty, force GUI selection
if isempty(tag)
    options.useGUI = true;
end

% Resolve target release directory
if options.useGUI
    dlist = dir(fullfile(rootDir, [options.repoNameRoot '*']));
    dlist = dlist([dlist.isdir]);
    names = {dlist.name};
    if isempty(names)
        error('use_version:NoReleases', 'No release directories found in %s with prefix %s.', ...
              rootDir, options.repoNameRoot)
    end
    [idx, ok] = listdlg('ListString', names, 'SelectionMode','single', ...
                        'PromptString','Select a release', 'ListSize',[320 420]);
    if ~ok || isempty(idx)
        fprintf('Selection cancelled. No changes made.\n');
        return
    end
    relName = names{idx};
    d = fullfile(rootDir, relName);
else
    d = fullfile(rootDir, [options.repoNameRoot tag]);
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
