% organize_images_by_section_gui.m
% GUI to select one or more subdirectories and organize .czi files by section
%
% This function launches a graphical interface that:
%   • Remembers your last base folder selection
%   • Displays subdirectories in a sortable table with creation date, modification date, and file count
%   • Allows multi-selection of folders to process
%   • Automatically creates subject-section subfolders and moves .czi files accordingly
%   • Reports progress and summary in the Command Window
%
% Usage:
%   organize_images_by_section_gui()
%     - Prompts for a base folder via dialog, remembering last used location.
%
%   organize_images_by_section_gui(basePath)
%     - Uses provided basePath after validating it exists and is a folder.
%     - Skips the initial directory picker but still updates the stored preference.

function organize_images_by_section_gui(basePath)
    % Preference settings
    prefGroup = 'organizeImages';
    prefName  = 'lastBasePath';

    % Validate or prompt for basePath
    if nargin < 1 || isempty(basePath)
        if ispref(prefGroup, prefName)
            defaultDir = getpref(prefGroup, prefName);
        else
            defaultDir = pwd;
        end
        basePath = uigetdir(defaultDir, 'Select base folder containing subdirectories');
        if isequal(basePath, 0)
            disp('No base folder selected. Exiting.');
            return;
        end
    else
        if ~isfolder(basePath)
            error('Provided basePath is not a valid folder:\n%s', basePath);
        end
    end
    % Store for next call
    if ispref(prefGroup, prefName)
        setpref(prefGroup, prefName, basePath);
    else
        addpref(prefGroup, prefName, basePath);
    end

    % Gather subdirectory info
    d = dir(basePath);
    isDir = [d.isdir] & ~ismember({d.name}, {'.','..'});
    d_sub = d(isDir);
    subdirs = {d_sub.name}';
    if isempty(subdirs)
        fprintf('No subdirectories found under %s.\n', basePath);
        return;
    end
    numDirs = numel(d_sub);

    % Use dir fields directly
    dateModified = datetime([d_sub.datenum]', 'ConvertFrom', 'datenum');
    dateCreated  = dateModified;  % Default to modified if no separate created info available
    fileCount = zeros(numDirs,1);
    for i = 1:numDirs
        folderPath = fullfile(basePath, d_sub(i).name);
        fileCount(i) = numel(dir(fullfile(folderPath, '*.czi')));
    end

    % Build table data
    tblData = table(subdirs, dateCreated, dateModified, fileCount, ...
        'VariableNames', {'Subdirectory','DateCreated','DateModified','FileCount'});

    % Initialize selection storage
    selectedRows = [];

    % Create UI
    fig = uifigure('Name','Select Directories to Process','Position',[200 200 600 350]);

    % Create sortable table
    tbl = uitable(fig, ...
        'Data', tblData, ...
        'ColumnName', {'Name','Date Created','Date Modified','#.czi Files'}, ...
        'ColumnSortable', true, ...
        'Position', [25 75 550 250], ...
        'CellSelectionCallback', @onCellSelect);

    % Process button
    uibutton(fig, 'push', ...
        'Text','Process', ...
        'Position',[250 20 100 40], ...
        'ButtonPushedFcn', @onProcess);

    % Callback: track selected rows
    function onCellSelect(~, event)
        if isempty(event.Indices)
            selectedRows = [];
        else
            selectedRows = unique(event.Indices(:,1));
        end
    end

    % Callback: process selected directories
    function onProcess(~, ~)
        if isempty(selectedRows)
            uialert(fig, 'Please select at least one subdirectory.','No Selection');
            return;
        end
        for idx = selectedRows'
            sub = subdirs{idx};
            pth = fullfile(basePath, sub);
            fprintf('\n=== Processing %s ===\n', pth);
            files = dir(fullfile(pth, '*.czi'));
            total = numel(files);
            if total == 0
                fprintf(' No .czi files found. Skipping.\n');
                continue;
            end
            moved = 0; skipped = 0;
            for k = 1:total
                fname = files(k).name;
                fprintf(' File %d/%d: %s\n', k, total, fname);
                info = regexp(fname, '^(?<subj>[^_]+)_(?<section>\d+[A-Za-z]_[RL])_', 'names');
                if isempty(info)
                    fprintf('  Skipped.\n'); skipped = skipped + 1; continue;
                end
                destFolder = fullfile(pth, [info.subj '_' info.section]);
                if ~exist(destFolder, 'dir')
                    mkdir(destFolder);
                    fprintf('  Created folder %s\n', destFolder);
                end
                try
                    movefile(fullfile(pth, fname), fullfile(destFolder, fname));
                    fprintf('  Moved.\n'); moved = moved + 1;
                catch ME
                    fprintf('  Error: %s\n', ME.message);
                end
            end
            fprintf(' Summary for %s: Total=%d, Moved=%d, Skipped=%d\n', sub, total, moved, skipped);
        end
        fprintf('\nAll selected directories processed.\n');
    end
end
