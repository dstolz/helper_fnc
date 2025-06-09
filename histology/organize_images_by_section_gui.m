% organize_images_by_section_gui.m
% GUI to select one or more subdirectories and organize .czi files by section
% Usage:
%   organize_images_by_section_gui()
%   organize_images_by_section_gui(basePath)

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
    subdirs = {d(isDir).name};
    if isempty(subdirs)
        fprintf('No subdirectories found under %s.\n', basePath);
        return;
    end
    % Build table data
    numDirs = numel(subdirs);
    dateCreated = datetime([d(isDir).datenum],'ConvertFrom','datenum');
    fileCount = zeros(numDirs,1);
    for i = 1:numDirs
        fileCount(i) = numel(dir(fullfile(basePath, subdirs{i}, '*.czi')));
    end
    tblData = table(subdirs(:), dateCreated(:), fileCount, ...
        'VariableNames', {'Subdirectory','DateCreated','FileCount'});

    % Initialize selection storage
    selectedRows = [];

    % Create UI
    fig = uifigure('Name','Select Directories to Process','Position',[200 200 500 350]);

    % Create sortable table
    tbl = uitable(fig, ...
        'Data', tblData, ...
        'ColumnName', {'Name','Date Created','#.czi Files'}, ...
        'ColumnSortable', true, ...
        'Position', [25 75 450 250], ...
        'CellSelectionCallback', @onCellSelect);

    % Process button
    uibutton(fig, 'push', ...
        'Text','Process', ...
        'Position',[200 20 100 40], ...
        'ButtonPushedFcn', @onProcess);

    % Callback: track selected rows
    function onCellSelect(src, event)
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
