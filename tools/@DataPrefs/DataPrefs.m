classdef DataPrefs < handle
    % DATAPREFS  Manage XML file lists stored in an XML file.
    %   XML structure:
    %     <files>
    %       <file name="SUBJ-ID-1118_19-Nov-2025.mat">
    %         <folder>Z:\RIG3_Backup_2025\epsych_files\Data\SUBJ-ID-1118\</folder>
    %         <included>true</included>
    %         <otherField>...</otherField>
    %       </file>
    %       ...
    %     </files>
    %
    %   Core properties:
    %     xmlFile       : path to the XML file
    %     Doc           : DOM document handle
    %     DefaultFields : struct of default subfields for new files
    %
    %   Dependent properties:
    %     FileNames : 1×N string, all <file name="...">
    %     Entries   : 1×N struct, all fields per file (name, folder, included, ...)
    %
    %   All per-file information is accessed via the Entries dependent
    %   property (struct array), or via helper methods like getFile,
    %   setField, set, setIncluded, addFile, and save().

    properties
        xmlFile (1,1) string
        Doc
        DefaultFields (1,1) struct = struct('included', true)
    end

    properties (Dependent)
        FileNames   % 1×N string
        Entries     % 1×N struct
        Included    % 1xN logical
    end

    methods
        showGUI(obj,idxVisible,block)

        function obj = DataPrefs(xmlFilename, Files, options)
            %DATAPREFS  Construct from XML file OR list of data files.
            %
            %   DP = DATAPREFS(XMLFILE) loads an existing XML prefs file.
            %
            %   DP = DATAPREFS(XMLFILE, FILES) creates/overwrites an XML
            %   prefs file at XMLFILE from FILES (cell/char/string of
            %   fullpaths) without prompting.
            %
            %   DP = DATAPREFS("", FILES) prompts for an XML filename via
            %   uiputfile, then creates the XML and returns the object.
            %
            %   DP = DATAPREFS(FILES) is a convenience form that assumes
            %   XMLFILENAME = "" when the first input looks like a list of
            %   non-XML file paths.
            %
            %   DP = DATAPREFS(..., options) where options.defaultFields is
            %   a struct uses DEFAULTFIELDS for any additional XML
            %   subfields (e.g. notes, quality, etc.).

            arguments
                xmlFilename = ""
                Files = []
                options.defaultFields (1,1) struct = struct()
            end

            % Default fields
            defaultFields = options.defaultFields;
            if ~isfield(defaultFields,'included')
                defaultFields.included = true;
            end

            % Convenience: DP = DataPrefs(FILES) where first arg is not an XML
            if ~isempty(xmlFilename) && isempty(Files)
                asStr = string(xmlFilename);
                if ~(isscalar(asStr) && endsWith(asStr, ".xml", 'IgnoreCase', true))
                    Files       = xmlFilename;
                    xmlFilename = "";
                end
            end

            % Normalize Files to string row vector if provided
            if ~isequal(Files,[])
                Files = string(Files);
                Files = Files(:).';
            end

            % CASE A: load existing XML only (no Files)
            if xmlFilename ~= "" && (isempty(Files) || isequal(Files,[]))
                asStr = string(xmlFilename);
                if ~endsWith(asStr, ".xml", 'IgnoreCase', true)
                    error('DataPrefs:InvalidInput', ...
                        'Single input must be an XML file; got "%s".', asStr);
                end
                obj.xmlFile       = asStr;
                obj.DefaultFields = defaultFields;
                obj.Doc           = xmlread(obj.xmlFile);
                return
            end

            % CASE B: Files provided but xmlFilename empty or "" → prompt to save
            if (xmlFilename == "" || isequal(xmlFilename,[])) && ~isempty(Files)
                [f,p] = uiputfile('*.xml','Save XML file as');
                if isequal(f,0) || isequal(p,0)
                    error('DataPrefs:NoFileSelected','User cancelled.');
                end
                newXML = fullfile(p,f);
                obj    = DataPrefs.filenames2xml(Files, string(newXML), defaultFields);
                return
            end

            % CASE C: Files + explicit xmlFilename → write XML there
            if xmlFilename ~= "" && ~isempty(Files)
                asStr = string(xmlFilename);
                if ~endsWith(asStr, ".xml", 'IgnoreCase', true)
                    error('DataPrefs:InvalidInput', ...
                        'XML filename must end with .xml; got "%s".', asStr);
                end
                obj = DataPrefs.filenames2xml(Files, asStr, defaultFields);
                return
            end

            % CASE D: no valid combination → ask user to select existing XML
            if xmlFilename == "" && (isempty(Files) || isequal(Files,[]))
                [f,p] = uigetfile('*.xml','Select XML file');
                if isequal(f,0) || isequal(p,0)
                    error('DataPrefs:NoFileSelected','User cancelled.');
                end
                xmlFile          = fullfile(p,f);
                obj.xmlFile      = string(xmlFile);
                obj.DefaultFields = defaultFields;
                obj.Doc          = xmlread(obj.xmlFile);
                return
            end

            error('DataPrefs:InvalidSyntax','Invalid DataPrefs(...) call.');
        end

        %% Dependent getters
        function names = get.FileNames(obj)
            doc   = obj.Doc;
            root  = doc.getDocumentElement;
            files = root.getElementsByTagName('file');

            n = files.getLength;
            names = strings(1,n);
            for i = 1:n
                fElem = files.item(i-1);
                names(i) = string(char(fElem.getAttribute('name')));
            end
        end

        function entries = get.Entries(obj)
            % Return all filename entries as a struct array.
            entries = obj.getAll();
        end

        function incl = get.Included(obj)
            incl = find([obj.Entries.included]);
        end

        %% Public API
        function reload(obj)
            %RELOAD  Re-read XML from disk.
            arguments
                obj
            end
            obj.Doc = xmlread(obj.xmlFile);
        end

        function entry = lookup(obj, filename)
            arguments
                obj
                filename (1,1) string = ""
            end

            if filename == ""
                obj.showGUI();
                entry = [];
                return
            end

            entry = obj.getFile(filename);
        end

        function entry = getFile(obj, filename)
            arguments
                obj
                filename (1,1) string
            end

            [elem, ~] = obj.findFileElement(filename);

            if isempty(elem)
                q = questdlg( ...
                    sprintf('File \"%s\" not found in XML. Add it?', filename), ...
                    'Add file?', ...
                    'Yes','No','Cancel','Yes');

                if strcmp(q,'Yes')
                    obj.addFile(filename);
                    obj.save();
                    [elem, ~] = obj.findFileElement(filename);
                else
                    entry = [];
                    return
                end
            end

            entry = obj.parseFileElement(elem);
        end

        function addFile(obj, filename, fields)
            %ADDFILE  Add a new file entry to the XML.

            arguments
                obj
                filename (1,1) string
                fields (1,1) struct = struct()
            end

            [elem, ~] = obj.findFileElement(filename);
            if ~isempty(elem)
                warning('FileListXML:Duplicate', ...
                    'File \"%s\" already exists in XML. Skipping.', filename);
                return
            end

            doc  = obj.Doc;
            root = doc.getDocumentElement;

            fileElem = doc.createElement('file');
            fileElem.setAttribute('name', char(filename));

            allFields = obj.DefaultFields;
            fn = fieldnames(fields);
            for k = 1:numel(fn)
                allFields.(fn{k}) = fields.(fn{k});
            end

            if ~isfield(allFields,'included')
                allFields.included = true;
            end

            fn = fieldnames(allFields);
            for k = 1:numel(fn)
                fldName = fn{k};
                val     = allFields.(fldName);

                fldElem = doc.createElement(fldName);
                if islogical(val)
                    txt = ternary(val,'true','false');
                elseif isnumeric(val)
                    txt = num2str(val);
                else
                    txt = char(string(val));
                end
                fldElem.appendChild(doc.createTextNode(txt));
                fileElem.appendChild(fldElem);
            end

            root.appendChild(fileElem);
        end

        function setIncluded(obj, filename, included)
            arguments
                obj
                filename (1,1) string
                included (1,1) logical
            end
            obj.setField(filename, 'included', included);
        end

        function setField(obj, filename, fieldName, value)
            arguments
                obj
                filename (1,1) string
                fieldName (1,1) string
                value
            end

            [elem, ~] = obj.findFileElement(filename);
            if isempty(elem)
                error('FileListXML:NotFound', ...
                    'File \"%s\" not found in XML.', filename);
            end

            doc   = obj.Doc;
            nodes = elem.getElementsByTagName(char(fieldName));

            if nodes.getLength == 0
                fldElem = doc.createElement(char(fieldName));
                elem.appendChild(fldElem);
            else
                fldElem = nodes.item(0);
            end

            if islogical(value)
                txt = string(value);

            elseif isnumeric(value)
                txt = num2str(value);

            elseif isdatetime(value)
                % Handle NaT (missing) cleanly
                if ismissing(value)
                    txt = '';
                else
                    % Use ISO-like text; adjust format if you prefer
                    txt = string(value);
                end

            elseif isstring(value)
                % Handle <missing> string
                if ismissing(value)
                    txt = '';
                else
                    txt = char(value);
                end

            else
                % Fallback for other types (char, etc.)
                txt = string(value);
            end

            txt = char(txt);


            fldElem.setTextContent(txt);
        end

        function entries = getAll(obj)
            %GETALL  Return all filename entries as a struct array.

            doc   = obj.Doc;
            root  = doc.getDocumentElement;
            files = root.getElementsByTagName('file');

            n = files.getLength;

            entries = struct([]);

            for i = 1:n
                fElem = files.item(i-1);
                s = obj.parseFileElement(fElem);

                if i == 1
                    % First struct defines initial layout
                    entries = s;
                else
                    % Ensure consistent fieldnames across all elements
                    fnE = fieldnames(entries);
                    fnS = fieldnames(s);

                    % Fields present in entries but missing in s
                    missingInS = setdiff(fnE, fnS);
                    for m = missingInS.'
                        s.(m{1}) = [];
                    end

                    % Fields present in s but missing in entries
                    missingInE = setdiff(fnS, fnE);
                    for m = missingInE.'
                        [entries.(m{1})] = deal([]);
                    end

                    entries(i) = s;
                end
            end
        end

        function set(obj, fieldName, values)
            %SET  Add or update a per-file field for all entries.
            arguments
                obj
                fieldName (1,1) string
                values
            end

            names = obj.FileNames;
            n     = numel(names);

            % Broadcast scalar values
            if isscalar(values)
                values = repmat(values, 1, n);
            end

            if numel(values) ~= n
                error('DataPrefs:set:SizeMismatch', ...
                    'VALUES must have one element per file (%d).', n);
            end

            % Loop through each file and set field
            for i = 1:n
                if iscell(values)
                    v = values{i};
                else
                    v = values(i);
                end
                obj.setField(names(i), fieldName, v);
            end
        end

        function sort(obj, idx)
            %SORT  Reorder <file> entries in the XML according to IDX.
            %   IDX must be a permutation of 1:numel(FileNames).
            arguments
                obj
                idx (:,1) double
            end

            names = obj.FileNames;
            n     = numel(names);

            if numel(idx) ~= n
                error('DataPrefs:sort:SizeMismatch', ...
                    'IDX must have one element per file (%d).', n);
            end

            if any(idx < 1 | idx > n) || ~isequal(sort(idx(:).'), 1:n)
                error('DataPrefs:sort:InvalidPermutation', ...
                    'IDX must be a permutation of 1:%d.', n);
            end

            doc  = obj.Doc;
            root = doc.getDocumentElement;

            % Collect all existing <file> element nodes in current order
            childNodes = root.getChildNodes();
            nChild     = childNodes.getLength;
            fileNodes  = cell(1,n);
            c = 0;
            for k = 1:nChild
                node = childNodes.item(k-1);
                if node.getNodeType() == node.ELEMENT_NODE && ...
                        strcmp(char(node.getNodeName()), 'file')
                    c = c + 1;
                    fileNodes{c} = node;
                end
            end

            if c ~= n
                error('DataPrefs:sort:InternalMismatch', ...
                    'Number of <file> elements (%d) does not match FileNames (%d).', c, n);
            end

            % Remove ALL children (including whitespace text nodes) to avoid
            % accumulating indentation/blank nodes on repeated sorts
            while root.hasChildNodes
                root.removeChild(root.getFirstChild());
            end

            % Append <file> nodes in the new order
            for k = 1:n
                root.appendChild(fileNodes{idx(k)});
            end
        end

        function save(obj)
            %SAVE  Write current DOM document to disk.
            xmlwrite(obj.xmlFile, obj.Doc);
            obj.xmlLocation;
        end

        function loc = xmlLocation(obj)
            loc = obj.xmlFile;

            fprintf('XML saved to: <a href="matlab:winopen(''%s'')">%s</a>\n',loc, loc);

            if nargout == 0, clear loc; end

        end
    end

    methods (Static)
        function obj = filenames2xml(filenames, xmlFile, defaultFields)
            %FILENAMES2XML  Create XML from list of filenames and return object.

            arguments
                filenames
                xmlFile (1,1) string = ""
                defaultFields (1,1) struct = struct()
            end

            if ischar(filenames)
                filenames = string({filenames});
            elseif iscell(filenames)
                filenames = string(filenames);
            elseif isstring(filenames)
                filenames = filenames(:).';
            else
                error('FileListXML:InvalidInput', ...
                    'Filenames must be char, string, or cellstr.');
            end

            if ~isfield(defaultFields,'included')
                defaultFields.included = true;
            end

            if xmlFile == ""
                [f,p] = uiputfile('*.xml','Save XML file as');
                if isequal(f,0) || isequal(p,0)
                    obj = [];
                    return
                end
                xmlFile = fullfile(p,f);
            end

            docNode = com.mathworks.xml.XMLUtils.createDocument('files');
            root    = docNode.getDocumentElement;

            for i = 1:numel(filenames)
                fpath = filenames(i);
                [folderPath, base, ext] = fileparts(fpath);
                fnameOnly = base + ext;

                fileElem = docNode.createElement('file');
                fileElem.setAttribute('name', char(fnameOnly));

                % folder
                folderElem = docNode.createElement('folder');
                folderElem.appendChild(docNode.createTextNode(char(folderPath)));
                fileElem.appendChild(folderElem);

                % included
                incVal = defaultFields.included;
                includedElem = docNode.createElement('included');
                includedElem.appendChild( ...
                    docNode.createTextNode(ternary(incVal,'true','false')) );
                fileElem.appendChild(includedElem);

                % other default fields (excluding folder/included)
                fn = fieldnames(defaultFields);
                for k = 1:numel(fn)
                    fldName = fn{k};
                    if any(strcmp(fldName, {'folder','included'}))
                        continue
                    end
                    val     = defaultFields.(fldName);
                    fldElem = docNode.createElement(fldName);
                    if islogical(val)
                        txt = ternary(val,'true','false');
                    elseif isnumeric(val)
                        txt = num2str(val);
                    else
                        txt = char(string(val));
                    end
                    fldElem.appendChild(docNode.createTextNode(txt));
                    fileElem.appendChild(fldElem);
                end

                root.appendChild(fileElem);
            end

            xmlwrite(xmlFile, docNode);

            % Construct DataPrefs object pointing at this XML, carrying defaults
            obj = DataPrefs(xmlFile);

            obj.xmlLocation;
        end
    end

    methods (Access = private)
        function [elem, idx] = findFileElement(obj, filename)
            doc   = obj.Doc;
            root  = doc.getDocumentElement;
            files = root.getElementsByTagName('file');

            n    = files.getLength;
            elem = [];
            idx  = [];

            for i = 1:n
                f  = files.item(i-1);
                nm = string(char(f.getAttribute('name')));
                if nm == filename
                    elem = f;
                    idx  = i;
                    return
                end
            end
        end

        function entry = parseFileElement(~, elem)
            nameStr = string(char(elem.getAttribute('name')));

            childNodes = elem.getChildNodes();
            nChild = childNodes.getLength;

            tmp = struct();
            for k = 1:nChild
                node = childNodes.item(k-1);
                if node.getNodeType() ~= node.ELEMENT_NODE
                    continue
                end
                fldName = string(char(node.getNodeName()));
                txt     = strtrim(char(node.getTextContent()));

                if any(strcmpi(txt, {'true','false'}))
                    val = strcmpi(txt,'true');
                else
                    num = str2double(txt);
                    if ~isnan(num) && ~isempty(txt)
                        val = num;
                    else
                        val = string(txt);
                    end
                end

                tmp.(fldName) = val;
            end

            if ~isfield(tmp,'included')
                tmp.included = true;
            end

            entry = tmp;
            entry.name = nameStr;
        end
    end
end
