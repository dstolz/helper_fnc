function showGUI(obj, idxVisible, doBlock)
%SHOWGUI  Open/raise GUI to edit XML fields for each file in a DataPrefs object.
%   SHOWGUI(OBJ) opens (or raises) the GUI showing all file entries.
%
%   SHOWGUI(OBJ, IDXVISIBLE) filters visible rows using a logical mask
%   the same length as OBJ.Entries.
%
%   SHOWGUI(OBJ, IDXVISIBLE, DOBLOCK) when DOBLOCK=true, blocks code
%   execution until the user presses Confirm/Cancel.

if nargin < 2 || isempty(idxVisible)
    idxVisible = [];
end
if nargin < 3 || isempty(doBlock)
    doBlock = false;
end

% Tag used to uniquely identify the GUI for this XML file
thisId = string(obj.xmlFile);
figTag = ['DataPrefsGUI_' matlab.lang.makeValidName(char(thisId))];

% Look for an existing figure with this tag
hFig = findall(0, 'Type','figure', 'Tag',figTag);

if ~isempty(hFig) && isvalid(hFig)
    % Existing GUI: update its table and raise it
    hTable    = findobj(hFig, 'Type','uitable');
    fullTable = getappdata(hFig,'fullTable');

    if ~isempty(idxVisible) && islogical(idxVisible) && ...
            numel(idxVisible) == height(fullTable)
        hTable.Data = fullTable(idxVisible, :);
    else
        hTable.Data = fullTable;
    end

    % Raise the window
    hFig.Visible     = 'on';
    hFig.WindowState = 'normal';
    
    figure(hFig);
    drawnow;

    if doBlock
        uiwait(hFig);
    end
    return
end

% Build a new GUI
entries = obj.Entries;
if isempty(entries)
    uialert(uifigure,'No <file> entries found in XML.','DataPrefs');
    return
end

n = numel(entries);

% Determine field names and order: name first, then included, then others
allFields = fieldnames(entries);
allFields = allFields(:).';

allFields(strcmp(allFields,'name')) = [];
allFields = ['name', allFields];

hasIncluded = any(strcmp(allFields,'included'));
if hasIncluded
    allFields(strcmp(allFields,'included')) = [];
    allFields = ['name','included', allFields(2:end)];
end

nCols = numel(allFields);
data  = cell(n, nCols);

for i = 1:n
    for j = 1:nCols
        fld = allFields{j};
        v   = entries(i).(fld);
        if isstring(v)
            data{i,j} = char(v);
        else
            data{i,j} = v;
        end
    end
end

colNames = allFields;

% Build table array for use with uifigure/uitable
T = cell2table(data, 'VariableNames', colNames);

% Apply initial logical filter if requested
if ~isempty(idxVisible) && islogical(idxVisible) && numel(idxVisible) == height(T)
    Tview = T(idxVisible, :);
else
    Tview = T;
end

f = uifigure( ...
    'Name', sprintf('Edit file list: %s', obj.xmlFile), ...
    'Position',[300 200 900 600], ...
    'Tag',figTag, ...
    'WindowStyle','modal');

colEditable = [false true(1,nCols-1)];

t = uitable( ...
    'Parent',f, ...
    'Data',Tview, ...
    'ColumnName',colNames, ...
    'ColumnEditable',colEditable, ...
    'ColumnSortable',true, ...
    'ColumnRearrangeable','on', ...
    'Units','normalized', ...
    'Position',[0.05 0.15 0.9 0.8]);

uibutton( ...
    f, 'Text','Confirm', ...
    'Position',[500 20 150 40], ...
    'ButtonPushedFcn',@onConfirm);

uibutton( ...
    f, 'Text','Cancel', ...
    'Position',[680 20 150 40], ...
    'ButtonPushedFcn',@onCancel);

% Store full table and metadata
setappdata(f,'fullTable',T);
setappdata(f,'colNames',colNames);
setappdata(f,'nCols',nCols);

    function onConfirm(~,~)
        tbl      = t.DisplayData;
        colNames = getappdata(f,'colNames');
        nColsLoc = getappdata(f,'nCols');

        for iRow = 1:height(tbl)
            fname = string(tbl.name(iRow));
            for jCol = 2:nColsLoc
                fld = colNames{jCol};
                v   = tbl.(fld)(iRow);

                if isstring(v) || ischar(v)
                    vNorm = string(v);
                else
                    vNorm = v;
                end

                if strcmp(fld,'included')
                    obj.setIncluded(fname, logical(vNorm));
                else
                    obj.setField(fname, fld, vNorm);
                end
            end
        end

        obj.save();
        delete(f);
    end

    function onCancel(~,~)
        delete(f);
    end

% Block if requested
if doBlock
    uiwait(f);
end

end
