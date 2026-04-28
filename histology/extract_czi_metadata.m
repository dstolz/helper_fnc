function T = extract_czi_metadata(rootPath, options)
%EXTRACT_CZI_METADATA Extract checklist-aligned metadata from .czi files.
%
%   T = extract_czi_metadata(rootPath)
%   T = extract_czi_metadata(rootPath, Verbose=false)
%   T = extract_czi_metadata(rootPath, FileNameRegex="WFA")
%   T = extract_czi_metadata(rootPath, FileNameRegex="^(?!.*DAPI).*WFA.*$")
%   T = extract_czi_metadata(rootPath, FileNameRegex="WFA", UseParallel=true)
%   T = extract_czi_metadata(rootPath, Verbose=false, ...
%       FileNameRegex="^(?!.*DAPI).*WFA.*$", UseParallel=true)
%
%   T = extract_czi_metadata(cziFile)
%   T = extract_czi_metadata(cziFile, Verbose=false)
%
%   T = extract_czi_metadata(rootPath, OutputXlsx="metadata.xlsx")
%   T = extract_czi_metadata(rootPath, FileNameRegex="WFA", ...
%       UseParallel=true, OutputXlsx="wfa_metadata.xlsx")
%
% Notes
%   - rootPath may be a folder (recursive .czi discovery) or the full path to
%     a single .czi file. When a file is given, FileNameRegex is ignored.
%   - One row per CZI file.
%   - Optional inputs are provided as name-value arguments.
%   - Multi-valued fields are stored as cell arrays containing numeric vectors
%     or string arrays, because a single CZI can contain multiple series,
%     channels, detectors, tracks, objectives, or laser lines.
%   - Standard OME/Bio-Formats metadata is used when available.
%   - Zeiss-specific fields are pulled from original CZI metadata by key-pattern
%     matching, which is necessary for many checklist items.
%   - If Verbose is true, progress is printed to the MATLAB command window.
%   - FileNameRegex is an optional case-insensitive regular expression applied
%     to the file name (including extension) when discovering .czi files.
%   - If UseParallel is true, files are processed in parallel with parfor
%     when a parallel pool can be started. Per-file verbose messages are
%     suppressed in parallel mode.
%   - In parallel mode, workers must also have access to Bio-Formats and
%     the input file paths.
%   - If OutputXlsx is provided, a spreadsheet-friendly version of the table
%     is written to that .xlsx file. Multi-valued cells are serialized as text.
%
    arguments
        rootPath (1,1) string {mustBeNonemptyText, mustBeFolderOrCziFile}
        options.Verbose {mustBeLogicalScalarLike} = true
        options.FileNameRegex (1,1) string {mustBeRegexOrEmpty} = ""
        options.UseParallel {mustBeLogicalScalarLike} = false
        options.OutputXlsx (1,1) string {mustBeXlsxPathOrEmpty} = ""
    end

    rootPath = char(rootPath);
    verbose = logical(options.Verbose);
    fileNameRegex = string(options.FileNameRegex);
    useParallel = logical(options.UseParallel);
    outputXlsx = string(options.OutputXlsx);

    initializeBioFormats();

    logmsg(verbose, '=== extract_czi_metadata ===');

    if isfile(rootPath)
        logmsg(verbose, 'Input file: %s', rootPath);
        files = {rootPath};
    else
        logmsg(verbose, 'Root folder: %s', rootPath);
        if strlength(fileNameRegex) > 0
            logmsg(verbose, 'File-name regex filter: %s', char(fileNameRegex));
        end
        logmsg(verbose, 'Searching for CZI files...');
        files = findCziFiles(rootPath, fileNameRegex);
    end

    n = numel(files);

    logmsg(verbose, 'Found %d CZI file(s).', n);

    if n == 0
        warning('extract_czi_metadata:NoFilesFound', 'No .czi files found in: %s', rootPath);
    end

    if useParallel && n <= 1
        logmsg(verbose, ...
            'Parallel mode requested, but only %d file(s) matched; running serially.', n);
    end

    allTimer = tic;

    fileName = strings(n,1);
    fullPath = strings(n,1);
    errMsg   = strings(n,1);

    % Requested originally
    pixelSizeX_um          = cell(n,1);
    pixelSizeY_um          = cell(n,1);
    pixelSizeZ_um          = cell(n,1);
    laserWavelength_nm     = cell(n,1);
    laserPower_mW          = cell(n,1);
    detectorGain           = cell(n,1);

    % Dimensions / frame
    sizeX_px               = cell(n,1);
    sizeY_px               = cell(n,1);
    sizeZ_count            = cell(n,1);
    sizeC_count            = cell(n,1);
    sizeT_count            = cell(n,1);
    frameSize_px           = cell(n,1);

    % Microscope / stand / motorized components
    microscopeName         = cell(n,1);
    microscopeSystem       = cell(n,1);
    microscopeType         = cell(n,1);
    stageName              = cell(n,1);
    shutterDeviceName      = cell(n,1);
    focusDeviceName        = cell(n,1);
    focusMaintenanceDevice = cell(n,1);
    scanUnitName           = cell(n,1);

    % Confocal / acquisition
    scanDirection          = cell(n,1);
    scanMode               = cell(n,1);
    scanSpeed              = cell(n,1);
    frameTime_s            = cell(n,1);
    averagingNumber        = cell(n,1);
    averagingMethod        = cell(n,1);
    pinholeSizeAiry        = cell(n,1);
    pinholeDiameter_um     = cell(n,1);
    trackMultiplexType     = cell(n,1);
    acquisitionMode        = cell(n,1);
    zStackStart_um         = cell(n,1);
    zStackEnd_um           = cell(n,1);
    zStep_um               = cell(n,1);
    timeInterval_s         = cell(n,1);

    % Illumination / wavelength selection
    laserIntensitySetting  = cell(n,1);
    laserTransmission_pct  = cell(n,1);
    tunableLaser           = cell(n,1);
    detectionRange_nm      = cell(n,1);
    emissionWavelength_nm  = cell(n,1);
    dichroicName           = cell(n,1);
    beamSplitterOrFilter   = cell(n,1);

    % Optics
    objectiveName          = cell(n,1);
    objectiveMagnification = cell(n,1);
    objectiveNA            = cell(n,1);
    objectiveImmersion     = cell(n,1);
    objectiveCorrection    = cell(n,1);
    objectiveImmersionRI   = cell(n,1);
    condenserNA            = cell(n,1);
    illuminationType       = cell(n,1);
    contrastMethod         = cell(n,1);

    % Detection
    detectorID             = cell(n,1);
    detectorType           = cell(n,1);
    detectorVoltage        = cell(n,1);
    detectorOffset         = cell(n,1);
    digitalGain            = cell(n,1);
    photonCounting         = cell(n,1);

    % Software
    softwareName           = cell(n,1);
    softwareVersion        = cell(n,1);

    results = cell(n,1);

    runInParallel = useParallel && n > 1;
    if runInParallel
        runInParallel = startParallelPool(verbose);
    end

    if runInParallel
        logmsg(verbose, ...
            'Parallel mode enabled; processing with parfor. Per-file messages are suppressed.');
        parfor k = 1:n
            results{k} = processOneCziFile(files{k}, false);
        end
    else
        for k = 1:n
            logmsg(verbose, '[%d/%d] Processing %s', k, n, files{k});
            results{k} = processOneCziFile(files{k}, verbose);
        end
    end

    for k = 1:n
        R = results{k};

        fileName(k) = R.FileName;
        fullPath(k) = R.FullPath;
        errMsg(k)   = R.Error;

        pixelSizeX_um{k}          = R.PixelSizeX_um;
        pixelSizeY_um{k}          = R.PixelSizeY_um;
        pixelSizeZ_um{k}          = R.PixelSizeZ_um;
        laserWavelength_nm{k}     = R.LaserWavelength_nm;
        laserPower_mW{k}          = R.LaserPower_mW;
        detectorGain{k}           = R.DetectorGain;

        sizeX_px{k}               = R.SizeX_px;
        sizeY_px{k}               = R.SizeY_px;
        sizeZ_count{k}            = R.SizeZ_count;
        sizeC_count{k}            = R.SizeC_count;
        sizeT_count{k}            = R.SizeT_count;
        frameSize_px{k}           = R.FrameSize_px;

        microscopeName{k}         = R.MicroscopeName;
        microscopeSystem{k}       = R.MicroscopeSystem;
        microscopeType{k}         = R.MicroscopeType;
        stageName{k}              = R.StageName;
        shutterDeviceName{k}      = R.ShutterDeviceName;
        focusDeviceName{k}        = R.FocusDeviceName;
        focusMaintenanceDevice{k} = R.FocusMaintenanceDevice;
        scanUnitName{k}           = R.ScanUnitName;

        scanDirection{k}          = R.ScanDirection;
        scanMode{k}               = R.ScanMode;
        scanSpeed{k}              = R.ScanSpeed;
        frameTime_s{k}            = R.FrameTime_s;
        averagingNumber{k}        = R.AveragingNumber;
        averagingMethod{k}        = R.AveragingMethod;
        pinholeSizeAiry{k}        = R.PinholeSizeAiry;
        pinholeDiameter_um{k}     = R.PinholeDiameter_um;
        trackMultiplexType{k}     = R.TrackMultiplexType;
        acquisitionMode{k}        = R.AcquisitionMode;
        zStackStart_um{k}         = R.ZStackStart_um;
        zStackEnd_um{k}           = R.ZStackEnd_um;
        zStep_um{k}               = R.ZStep_um;
        timeInterval_s{k}         = R.TimeInterval_s;

        laserIntensitySetting{k}  = R.LaserIntensitySetting;
        laserTransmission_pct{k}  = R.LaserTransmission_pct;
        tunableLaser{k}           = R.TunableLaser;
        detectionRange_nm{k}      = R.DetectionRange_nm;
        emissionWavelength_nm{k}  = R.EmissionWavelength_nm;
        dichroicName{k}           = R.DichroicName;
        beamSplitterOrFilter{k}   = R.BeamSplitterOrFilter;

        objectiveName{k}          = R.ObjectiveName;
        objectiveMagnification{k} = R.ObjectiveMagnification;
        objectiveNA{k}            = R.ObjectiveNA;
        objectiveImmersion{k}     = R.ObjectiveImmersion;
        objectiveCorrection{k}    = R.ObjectiveCorrection;
        objectiveImmersionRI{k}   = R.ObjectiveImmersionRI;
        condenserNA{k}            = R.CondenserNA;
        illuminationType{k}       = R.IlluminationType;
        contrastMethod{k}         = R.ContrastMethod;

        detectorID{k}             = R.DetectorID;
        detectorType{k}           = R.DetectorType;
        detectorVoltage{k}        = R.DetectorVoltage;
        detectorOffset{k}         = R.DetectorOffset;
        digitalGain{k}            = R.DigitalGain;
        photonCounting{k}         = R.PhotonCounting;

        softwareName{k}           = R.SoftwareName;
        softwareVersion{k}        = R.SoftwareVersion;
    end

    if verbose
        nErr = nnz(strlength(errMsg) > 0);
        fprintf('\nCompleted %d file(s) in %.2f s. Errors: %d.\n', ...
            n, toc(allTimer), nErr);
        drawnow;
    end

    T = table( ...
        fileName, ...
        fullPath, ...
        pixelSizeX_um, ...
        pixelSizeY_um, ...
        pixelSizeZ_um, ...
        sizeX_px, ...
        sizeY_px, ...
        sizeZ_count, ...
        sizeC_count, ...
        sizeT_count, ...
        frameSize_px, ...
        microscopeName, ...
        microscopeSystem, ...
        microscopeType, ...
        stageName, ...
        shutterDeviceName, ...
        focusDeviceName, ...
        focusMaintenanceDevice, ...
        scanUnitName, ...
        scanDirection, ...
        scanMode, ...
        scanSpeed, ...
        frameTime_s, ...
        averagingNumber, ...
        averagingMethod, ...
        pinholeSizeAiry, ...
        pinholeDiameter_um, ...
        laserWavelength_nm, ...
        laserPower_mW, ...
        laserIntensitySetting, ...
        laserTransmission_pct, ...
        tunableLaser, ...
        detectionRange_nm, ...
        emissionWavelength_nm, ...
        dichroicName, ...
        beamSplitterOrFilter, ...
        objectiveName, ...
        objectiveMagnification, ...
        objectiveNA, ...
        objectiveImmersion, ...
        objectiveCorrection, ...
        objectiveImmersionRI, ...
        condenserNA, ...
        illuminationType, ...
        contrastMethod, ...
        detectorID, ...
        detectorType, ...
        detectorVoltage, ...
        detectorOffset, ...
        detectorGain, ...
        digitalGain, ...
        photonCounting, ...
        softwareName, ...
        softwareVersion, ...
        trackMultiplexType, ...
        acquisitionMode, ...
        zStackStart_um, ...
        zStackEnd_um, ...
        zStep_um, ...
        timeInterval_s, ...
        errMsg, ...
        'VariableNames', { ...
            'FileName', ...
            'FullPath', ...
            'PixelSizeX_um', ...
            'PixelSizeY_um', ...
            'PixelSizeZ_um', ...
            'SizeX_px', ...
            'SizeY_px', ...
            'SizeZ_count', ...
            'SizeC_count', ...
            'SizeT_count', ...
            'FrameSize_px', ...
            'MicroscopeName', ...
            'MicroscopeSystem', ...
            'MicroscopeType', ...
            'StageName', ...
            'ShutterDeviceName', ...
            'FocusDeviceName', ...
            'FocusMaintenanceDevice', ...
            'ScanUnitName', ...
            'ScanDirection', ...
            'ScanMode', ...
            'ScanSpeed', ...
            'FrameTime_s', ...
            'AveragingNumber', ...
            'AveragingMethod', ...
            'PinholeSizeAiry', ...
            'PinholeDiameter_um', ...
            'LaserWavelength_nm', ...
            'LaserPower_mW', ...
            'LaserIntensitySetting', ...
            'LaserTransmission_pct', ...
            'TunableLaser', ...
            'DetectionRange_nm', ...
            'EmissionWavelength_nm', ...
            'DichroicName', ...
            'BeamSplitterOrFilter', ...
            'ObjectiveName', ...
            'ObjectiveMagnification', ...
            'ObjectiveNA', ...
            'ObjectiveImmersion', ...
            'ObjectiveCorrection', ...
            'ObjectiveImmersionRI', ...
            'CondenserNA', ...
            'IlluminationType', ...
            'ContrastMethod', ...
            'DetectorID', ...
            'DetectorType', ...
            'DetectorVoltage', ...
            'DetectorOffset', ...
            'DetectorGain', ...
            'DigitalGain', ...
            'PhotonCounting', ...
            'SoftwareName', ...
            'SoftwareVersion', ...
            'TrackMultiplexType', ...
            'AcquisitionMode', ...
            'ZStackStart_um', ...
            'ZStackEnd_um', ...
            'ZStep_um', ...
            'TimeInterval_s', ...
            'Error' ...
        });

    if strlength(outputXlsx) > 0
        if verbose
            xlsxPath = char(outputXlsx);
            fprintf('[%s] Writing xlsx file: <a href="matlab:winopen(''%s'')">%s</a>\n', ...
                char(datetime('now', 'Format', 'HH:mm:ss')), xlsxPath, xlsxPath);
            drawnow;
        end
        TforXlsx = makeExcelWritableTable(T);
        writetable(TforXlsx, char(outputXlsx), 'FileType', 'spreadsheet');
    end
end

function mustBeNonemptyText(x)
    if strlength(strip(x)) == 0
        error('extract_czi_metadata:EmptyText', ...
            'Text inputs must be non-empty.');
    end
end

function mustBeFolderOrCziFile(x)
    xc = char(x);
    if isfolder(xc)
        return;
    end
    if isfile(xc) && endsWith(xc, '.czi', 'IgnoreCase', true)
        return;
    end
    error('extract_czi_metadata:BadPath', ...
        'Input must be an existing folder or a .czi file path: %s', xc);
end

function mustBeRegexOrEmpty(x)
    if strlength(x) == 0
        return;
    end

    try
        regexpi('test.czi', char(x), 'once');
    catch ME
        error('extract_czi_metadata:BadRegex', ...
            'Invalid file-name regular expression: %s', ME.message);
    end
end

function mustBeLogicalScalarLike(x)
    isValid = isscalar(x) && ...
        (islogical(x) || (isnumeric(x) && isfinite(x) && ismember(double(x), [0 1])));

    if ~isValid
        error('extract_czi_metadata:BadLogicalScalar', ...
            'Value must be a logical scalar or a numeric scalar equal to 0 or 1.');
    end
end

function mustBeXlsxPathOrEmpty(x)
    if strlength(x) == 0
        return;
    end

    [folderPart, baseName, ext] = fileparts(char(x));

    if strlength(string(baseName)) == 0
        error('extract_czi_metadata:BadXlsxPath', ...
            'OutputXlsx must include a file name ending in .xlsx.');
    end

    if ~strcmpi(ext, '.xlsx')
        error('extract_czi_metadata:BadXlsxPath', ...
            'OutputXlsx must end with .xlsx.');
    end

    if ~isempty(folderPart) && ~isfolder(folderPart)
        error('extract_czi_metadata:BadXlsxPath', ...
            'OutputXlsx folder does not exist: %s', folderPart);
    end
end

function TforXlsx = makeExcelWritableTable(T)
    TforXlsx = T;
    varNames = T.Properties.VariableNames;

    for i = 1:numel(varNames)
        thisVar = T.(varNames{i});

        if iscell(thisVar)
            out = strings(size(thisVar));
            for j = 1:numel(thisVar)
                out(j) = formatForSpreadsheet(thisVar{j});
            end
            TforXlsx.(varNames{i}) = out;
        elseif isstring(thisVar)
            % Leave string variables unchanged.
        elseif isnumeric(thisVar) || islogical(thisVar) || isdatetime(thisVar) || ...
                isduration(thisVar) || iscategorical(thisVar)
            % Leave scalar spreadsheet-friendly variables unchanged.
        else
            out = strings(size(thisVar));
            for j = 1:numel(thisVar)
                out(j) = formatForSpreadsheet(thisVar(j));
            end
            TforXlsx.(varNames{i}) = out;
        end
    end
end

function s = formatForSpreadsheet(v)
    if isempty(v)
        s = "";
        return;
    end

    if isstring(v)
        if isscalar(v)
            s = v;
        else
            s = "[" + strjoin(v(:).', "; ") + "]";
        end
        return;
    end

    if ischar(v)
        s = string(v);
        return;
    end

    if isnumeric(v) || islogical(v)
        s = numericArrayToString(v);
        return;
    end

    if iscell(v)
        parts = strings(numel(v), 1);
        for k = 1:numel(v)
            parts(k) = formatForSpreadsheet(v{k});
        end
        s = strjoin(parts, "; ");
        return;
    end

    try
        temp = string(v);
        if isscalar(temp)
            s = temp;
        else
            s = "[" + strjoin(temp(:).', "; ") + "]";
        end
    catch
        s = "";
    end
end

function s = numericArrayToString(v)
    if isempty(v)
        s = "";
        return;
    end

    if isscalar(v)
        s = compose("%.12g", double(v));
        return;
    end

    parts = compose("%.12g", double(v(:).'));
    s = "[" + strjoin(parts, ", ") + "]";
end

function tf = startParallelPool(verbose)
    tf = true;

    try
        pool = gcp('nocreate');
        if isempty(pool)
            logmsg(verbose, 'Starting parallel pool...');
            try
                pool = parpool('Processes');
            catch
                pool = parpool('local');
            end
        end
        logmsg(verbose, 'Using parallel pool with %d worker(s).', pool.NumWorkers);
    catch ME
        warning('extract_czi_metadata:ParallelUnavailable', ...
            ['Parallel execution was requested, but a pool could not be started. ' ...
             'Falling back to serial mode.\n%s'], ME.message);
        tf = false;
    end
end

function initializeBioFormats()
    persistent isInitialized

    if isempty(isInitialized) || ~isInitialized
        bfCheckJavaPath();
        loci.common.DebugTools.setRootLevel('WARN');
        isInitialized = true;
    end
end

function R = processOneCziFile(filePath, verbose)
    fileTimer = tic;
    R = makeEmptyResult();

    [~, nameOnly, ext] = fileparts(filePath);
    R.FileName = string([nameOnly ext]);
    R.FullPath = string(filePath);
    R.Error = "";

    reader = [];
    try
        initializeBioFormats();

        um = ome.units.UNITS.MICROMETER;
        nm = ome.units.UNITS.NANOMETER;
        mW = ome.units.UNITS.MILLIWATT;

        logmsg(verbose, '    Opening Bio-Formats reader');
        reader = bfGetReader(filePath);
        cleanupObj = onCleanup(@() closeReader(reader)); %#ok<NASGU>

        logmsg(verbose, '    Reading OME metadata');
        omeMeta = reader.getMetadataStore();

        logmsg(verbose, '    Reading original CZI metadata');
        rawMeta = collectOriginalMetadata(reader);

        logmsg(verbose, '    Extracting fields');

        %-----------------------------
        % Core sizes from reader
        %-----------------------------
        sx = [];
        sy = [];
        sz = [];
        sc = [];
        st = [];

        currentSeries = countOrZero(safeGet(@() reader.getSeries()));
        seriesCount   = countOrZero(safeGet(@() reader.getSeriesCount()));

        for s = 0:seriesCount-1
            reader.setSeries(s);
            sx = addNumber(sx, safeGet(@() reader.getSizeX()));
            sy = addNumber(sy, safeGet(@() reader.getSizeY()));
            sz = addNumber(sz, safeGet(@() reader.getSizeZ()));
            sc = addNumber(sc, safeGet(@() reader.getSizeC()));
            st = addNumber(st, safeGet(@() reader.getSizeT()));
        end
        reader.setSeries(currentSeries);

        %-----------------------------
        % OME metadata
        %-----------------------------
        pxX = [];
        pxY = [];
        pxZ = [];

        laserW = [];
        laserP = [];
        detGain = [];
        detVolt = [];
        detOff  = [];
        emW     = [];
        pinholeDia = [];

        objNames = string.empty(0,1);
        objMag   = [];
        objNAvals = [];
        objImm   = string.empty(0,1);
        objCorr  = string.empty(0,1);
        objImmRIvals = [];

        detIDs   = string.empty(0,1);
        detTypes = string.empty(0,1);

        tunableVals = string.empty(0,1);
        dichroicVals = string.empty(0,1);

        imageCount = countOrZero(safeGet(@() omeMeta.getImageCount()));
        for img = 0:imageCount-1
            pxX = addQuantity(pxX, safeGet(@() omeMeta.getPixelsPhysicalSizeX(img)), um);
            pxY = addQuantity(pxY, safeGet(@() omeMeta.getPixelsPhysicalSizeY(img)), um);
            pxZ = addQuantity(pxZ, safeGet(@() omeMeta.getPixelsPhysicalSizeZ(img)), um);

            chCount = countOrZero(safeGet(@() omeMeta.getChannelCount(img)));
            for ch = 0:chCount-1
                q = safeGet(@() omeMeta.getChannelLightSourceSettingsWavelength(img, ch));
                if isempty(q)
                    q = safeGet(@() omeMeta.getChannelExcitationWavelength(img, ch));
                end
                laserW = addQuantity(laserW, q, nm);
                emW    = addQuantity(emW, safeGet(@() omeMeta.getChannelEmissionWavelength(img, ch)), nm);
                pinholeDia = addQuantity(pinholeDia, safeGet(@() omeMeta.getChannelPinholeSize(img, ch)), um);

                detGain = addNumber(detGain, safeGet(@() omeMeta.getDetectorSettingsGain(img, ch)));
                detVolt = addNumber(detVolt, safeGet(@() omeMeta.getDetectorSettingsVoltage(img, ch)));
                detOff  = addNumber(detOff,  safeGet(@() omeMeta.getDetectorSettingsOffset(img, ch)));
            end
        end

        instCount = countOrZero(safeGet(@() omeMeta.getInstrumentCount()));
        for inst = 0:instCount-1
            lightCount = countOrZero(safeGet(@() omeMeta.getLightSourceCount(inst)));
            for ls = 0:lightCount-1
                laserP = addQuantity(laserP, safeGet(@() omeMeta.getLaserPower(inst, ls)), mW);
                tunableVals = addText(tunableVals, safeGet(@() omeMeta.getLaserTuneable(inst, ls)));
            end

            detCount = countOrZero(safeGet(@() omeMeta.getDetectorCount(inst)));
            for det = 0:detCount-1
                detIDs   = addText(detIDs, safeGet(@() omeMeta.getDetectorID(inst, det)));
                detTypes = addText(detTypes, safeGet(@() omeMeta.getDetectorType(inst, det)));
                detTypes = addText(detTypes, safeGet(@() omeMeta.getDetectorModel(inst, det)));

                detGain = addNumber(detGain, safeGet(@() omeMeta.getDetectorGain(inst, det)));
                detVolt = addNumber(detVolt, safeGet(@() omeMeta.getDetectorVoltage(inst, det)));
                detOff  = addNumber(detOff,  safeGet(@() omeMeta.getDetectorOffset(inst, det)));
            end

            objCount = countOrZero(safeGet(@() omeMeta.getObjectiveCount(inst)));
            for obj = 0:objCount-1
                objNames = addText(objNames, safeGet(@() omeMeta.getObjectiveModel(inst, obj)));
                objMag   = addNumber(objMag, safeGet(@() omeMeta.getObjectiveNominalMagnification(inst, obj)));
                objNAvals = addNumber(objNAvals, safeGet(@() omeMeta.getObjectiveLensNA(inst, obj)));
                objImm   = addText(objImm, safeGet(@() omeMeta.getObjectiveImmersion(inst, obj)));
                objCorr  = addText(objCorr, safeGet(@() omeMeta.getObjectiveCorrection(inst, obj)));
                objImmRIvals = addNumber(objImmRIvals, ...
                    safeGet(@() omeMeta.getObjectiveImmersionRefractiveIndex(inst, obj)));
            end

            dCount = countOrZero(safeGet(@() omeMeta.getDichroicCount(inst)));
            for d = 0:dCount-1
                dichroicVals = addText(dichroicVals, safeGet(@() omeMeta.getDichroicModel(inst, d)));
                dichroicVals = addText(dichroicVals, safeGet(@() omeMeta.getDichroicID(inst, d)));
            end
        end

        %-----------------------------
        % Original Zeiss metadata
        %-----------------------------
        laserW = mergeNumeric(laserW, getRawNumbers(rawMeta, { ...
            '\|Channel\|ExcitationWavelength(?:\s*#\d+)?$', ...
            '\|Channel\|Wavelength(?:\s*#\d+)?$'}));

        laserP = mergeNumeric(laserP, getRawNumbers(rawMeta, { ...
            '\|Instrument\|LightSource\|Power(?:\s*#\d+)?$'}));

        detGain = mergeNumeric(detGain, getRawNumbers(rawMeta, { ...
            '\|ParameterCollection\|DetectorGain(?:\s*#\d+)?$'}));

        detVolt = mergeNumeric(detVolt, getRawNumbers(rawMeta, { ...
            '\|Channel\|Voltage(?:\s*#\d+)?$', ...
            '\|Detector\|Voltage(?:\s*#\d+)?$'}));

        detOff = mergeNumeric(detOff, getRawNumbers(rawMeta, { ...
            '\|Instrument\|Detector\|Offset(?:\s*#\d+)?$', ...
            '\|Channel\|Offset(?:\s*#\d+)?$', ...
            'DigitalOffset(?:\s*#\d+)?$'}));

        emW = mergeNumeric(emW, getRawNumbers(rawMeta, { ...
            '\|Channel\|EmissionWavelength(?:\s*#\d+)?$'}));

        tunableVals = mergeText(tunableVals, getRawText(rawMeta, { ...
            'LightSourceType\|Laser\|Tuneable(?:\s*#\d+)?$', ...
            'LightSourceType\|Laser\|Tunable(?:\s*#\d+)?$'}));

        microscopeNameVals = getRawText(rawMeta, { ...
            '\|Instrument\|Microscope\|Name(?:\s*#\d+)?$'});
        microscopeSystemVals = getRawText(rawMeta, { ...
            '\|Instrument\|Microscope\|System(?:\s*#\d+)?$'});
        microscopeTypeVals = getRawText(rawMeta, { ...
            '\|Instrument\|Microscope\|Type(?:\s*#\d+)?$'});

        softwareNameVals = getRawText(rawMeta, { ...
            '\|Application\|Name(?:\s*#\d+)?$'});
        softwareVersionVals = getRawText(rawMeta, { ...
            '\|Application\|Version(?:\s*#\d+)?$'});

        stageNameVals = getDeviceNames(rawMeta, {'Motorized Stage|Stage\.'}, false);
        shutterDeviceVals = getDeviceNames(rawMeta, {'Shutter'}, false);
        focusDeviceVals = getDeviceNames(rawMeta, {'Piezo|Focus|Autofocus'}, true);
        focusMaintVals = getDeviceNames(rawMeta, {'FocusStabilizer|DefiniteFocus'}, true);
        scanUnitVals = getDeviceNames(rawMeta, {'Scanner|Scanhead'}, false);

        scanDirectionVals = getRawText(rawMeta, { ...
            'LaserScanInfo\|ScanDirection(?:\s*#\d+)?$', ...
            '\|ParameterCollection\|ScanDirection$'});

        scanModeVals = getRawText(rawMeta, { ...
            'LaserScanInfo\|ScanningMode(?:\s*#\d+)?$'});

        scanSpeedVals = getRawNumbers(rawMeta, { ...
            'LaserScanInfo\|ScanSpeed(?:\s*#\d+)?$', ...
            '\|AcquisitionModeSetup\|Detector\|ScanSpeed(?:\s*#\d+)?$', ...
            '\|ParameterCollection\|ScanSpeed$'});

        frameTimeVals = getRawNumbers(rawMeta, { ...
            'LaserScanInfo\|FrameTime(?:\s*#\d+)?$', ...
            '\|ParameterCollection\|FrameTime$'});

        averagingNumberVals = getRawNumbers(rawMeta, { ...
            'LaserScanInfo\|Averaging(?:\s*#\d+)?$', ...
            '\|AveragingNumber(?:\s*#\d+)?$'});

        averagingMethodVals = getRawText(rawMeta, { ...
            '\|AveragingMethod(?:\s*#\d+)?$'});

        frameSizeVals = getRawText(rawMeta, { ...
            '\|FrameSize(?:\s*#\d+)?$', ...
            '\|Frame(?:\s*#\d+)?$'});

        pinholeAiryVals = getRawNumbers(rawMeta, { ...
            'PinholeSizeAiry(?:\s*#\d+)?$', ...
            'AiryUnits\|AiryUnits(?:\s*#\d+)?$'});

        laserIntensityVals = getRawNumbers(rawMeta, { ...
            'DetectionModeSetup\|.*\|ParameterCollection\|Intensity(?:\s*#\d+)?$', ...
            '\|ParameterCollection\|Intensity(?:\s*#\d+)?$'});

        transmissionVals = getRawNumbers(rawMeta, { ...
            '\|Channel\|Transmission(?:\s*#\d+)?$'});
        transmissionVals(abs(transmissionVals) <= 1) = ...
            100 * transmissionVals(abs(transmissionVals) <= 1);

        detectionRangeVals = getRawText(rawMeta, { ...
            'DetectionWavelength\|Ranges(?:\s*#\d+)?$'});
        if isempty(detectionRangeVals)
            drStart = getRawNumbers(rawMeta, { ...
                'DetectionRangeStart(?:\s*#\d+)?$'});
            drEnd = getRawNumbers(rawMeta, { ...
                'DetectionRangeEnd(?:\s*#\d+)?$'});
            detectionRangeVals = formatRanges(drStart, drEnd);
        end

        dichroicVals = mergeText(dichroicVals, getRawText(rawMeta, { ...
            '\|Instrument\|Dichroic\|Name(?:\s*#\d+)?$'}));

        beamSplitterVals = getRawText(rawMeta, { ...
            'LaserScanInfo\|MainBeamSplitterVis(?:\s*#\d+)?$', ...
            'LaserScanInfo\|SecondaryBeamSplitter(?:\s*#\d+)?$', ...
            '\|Channel\|Reflector(?:\s*#\d+)?$'});

        objActiveName = getRawText(rawMeta, { ...
            '\|AutoScaling\|ObjectiveName(?:\s*#\d+)?$'});
        if isempty(objActiveName)
            objActiveName = finalizeText(cellstr(objNames));
        end

        [objMagFromName, objNAFromName] = parseObjectiveMagNA(objActiveName);

        objMagFinal = mergeNumeric(objMag, ...
            getRawNumbers(rawMeta, {'\|Instrument\|Objective\|NominalMagnification(?:\s*#\d+)?$'}), ...
            objMagFromName);

        objNAFinal = mergeNumeric(objNAvals, objNAFromName);

        objImmFinal = mergeText(objImm, getRawText(rawMeta, { ...
            '\|Instrument\|Objective\|Immersion(?:\s*#\d+)?$'}));

        objCorrFinal = mergeText(objCorr, parseObjectiveCorrection(objActiveName));

        objImmRIFinal = mergeNumeric(objImmRIvals, getRawNumbers(rawMeta, { ...
            '\|Instrument\|Objective\|ImmersionRefractiveIndex(?:\s*#\d+)?$'}));

        condenserNAVals = getRawNumbers(rawMeta, { ...
            '\|Channel\|NACondenser(?:\s*#\d+)?$'});

        illuminationTypeVals = getRawText(rawMeta, { ...
            '\|Channel\|IlluminationType(?:\s*#\d+)?$', ...
            'ContrastMethod\|IlluminationType(?:\s*#\d+)?$'});

        contrastMethodVals = getRawText(rawMeta, { ...
            '\|Channel\|ContrastMethod(?:\s*#\d+)?$'});

        detectorIDVals = mergeText(detIDs, getRawText(rawMeta, { ...
            'LsmAcquisitionSetup\|DetectorId(?:\s*#\d+)?$'}));

        detectorTypeVals = mergeText(detTypes, ...
            getRawText(rawMeta, {'\|Instrument\|Detector\|Id(?:\s*#\d+)?$'}), ...
            getDeviceNames(rawMeta, {'Pmt|Detector|Airyscan'}, false));

        digitalGainVals = getRawNumbers(rawMeta, { ...
            '\|Channel\|DigitalGain(?:\s*#\d+)?$', ...
            'DigiGainFactorChannel(?:\s*#\d+)?$'});

        photonCountingVals = getRawText(rawMeta, { ...
            'IsPhotonCounting(?:\s*#\d+)?$'});

        trackMultiplexVals = getRawText(rawMeta, { ...
            'TrackMultiplexType(?:\s*#\d+)?$'});

        acquisitionModeVals = getRawText(rawMeta, { ...
            '\|Channel\|AcquisitionMode(?:\s*#\d+)?$'});

        timeSeriesActiveVals = getRawText(rawMeta, { ...
            'TimeSeriesSetup\|IsActivated(?:\s*#\d+)?$'});

        zStartVals = convertRawDistanceToUm(getRawNumbers(rawMeta, { ...
            'ZStackSetup\|First\|Distance\|Value(?:\s*#\d+)?$'}));

        zEndVals = convertRawDistanceToUm(getRawNumbers(rawMeta, { ...
            'ZStackSetup\|Last\|Distance\|Value(?:\s*#\d+)?$'}));

        zStepVals = convertRawDistanceToUm(getRawNumbers(rawMeta, { ...
            'ZStackSetup\|Interval\|Distance\|Value(?:\s*#\d+)?$'}));

        if isempty(zStepVals)
            szFinalTmp = finalizeNumeric(sz);
            if numel(zStartVals) == 1 && numel(zEndVals) == 1 && ...
                    numel(szFinalTmp) == 1 && szFinalTmp(1) > 1
                zStepVals = finalizeNumeric((zEndVals(1) - zStartVals(1)) / (szFinalTmp(1) - 1));
            end
        end

        timeIntervalVals = getRawNumbers(rawMeta, { ...
            'TimeSeriesSetup\|Interval\|TimeSpan\|Value(?:\s*#\d+)?$', ...
            'TimeSeriesSetup\|StartNextTimeSliceMode\|Manual\|TimeSpan\|Value(?:\s*#\d+)?$', ...
            'TimeSeriesSetup\|StartNextTimeSliceMode\|Manual\|Interval(?:\s*#\d+)?$', ...
            'TimeSeriesSetup\|StopMode\|Manual\|Interval(?:\s*#\d+)?$'});

        stFinalTmp = finalizeNumeric(st);
        hasTimeSeries = any(strcmpi(timeSeriesActiveVals, "true")) || ...
            (numel(stFinalTmp) == 1 && stFinalTmp(1) > 1);

        if ~hasTimeSeries
            timeIntervalVals = [];
        else
            timeIntervalVals = timeIntervalVals(timeIntervalVals ~= 0);
        end

        %-----------------------------
        % Finalize and store
        %-----------------------------
        R.PixelSizeX_um          = finalizeNumeric(pxX);
        R.PixelSizeY_um          = finalizeNumeric(pxY);
        R.PixelSizeZ_um          = finalizeNumeric(pxZ);
        R.LaserWavelength_nm     = finalizeNumeric(laserW);
        R.LaserPower_mW          = finalizeNumeric(laserP);
        R.DetectorGain           = finalizeNumeric(detGain);

        R.SizeX_px               = finalizeNumeric(sx);
        R.SizeY_px               = finalizeNumeric(sy);
        R.SizeZ_count            = finalizeNumeric(sz);
        R.SizeC_count            = finalizeNumeric(sc);
        R.SizeT_count            = finalizeNumeric(st);
        R.FrameSize_px           = frameSizeVals;

        R.MicroscopeName         = microscopeNameVals;
        R.MicroscopeSystem       = microscopeSystemVals;
        R.MicroscopeType         = microscopeTypeVals;
        R.StageName              = stageNameVals;
        R.ShutterDeviceName      = shutterDeviceVals;
        R.FocusDeviceName        = focusDeviceVals;
        R.FocusMaintenanceDevice = focusMaintVals;
        R.ScanUnitName           = scanUnitVals;

        R.ScanDirection          = scanDirectionVals;
        R.ScanMode               = scanModeVals;
        R.ScanSpeed              = finalizeNumeric(scanSpeedVals);
        R.FrameTime_s            = finalizeNumeric(frameTimeVals);
        R.AveragingNumber        = finalizeNumeric(averagingNumberVals);
        R.AveragingMethod        = averagingMethodVals;
        R.PinholeSizeAiry        = finalizeNumeric(pinholeAiryVals);
        R.PinholeDiameter_um     = finalizeNumeric(pinholeDia);
        R.TrackMultiplexType     = trackMultiplexVals;
        R.AcquisitionMode        = acquisitionModeVals;
        R.ZStackStart_um         = finalizeNumeric(zStartVals);
        R.ZStackEnd_um           = finalizeNumeric(zEndVals);
        R.ZStep_um               = finalizeNumeric(zStepVals);
        R.TimeInterval_s         = finalizeNumeric(timeIntervalVals);

        R.LaserIntensitySetting  = finalizeNumeric(laserIntensityVals);
        R.LaserTransmission_pct  = finalizeNumeric(transmissionVals);
        R.TunableLaser           = tunableVals;
        R.DetectionRange_nm      = detectionRangeVals;
        R.EmissionWavelength_nm  = finalizeNumeric(emW);
        R.DichroicName           = dichroicVals;
        R.BeamSplitterOrFilter   = beamSplitterVals;

        R.ObjectiveName          = objActiveName;
        R.ObjectiveMagnification = finalizeNumeric(objMagFinal);
        R.ObjectiveNA            = finalizeNumeric(objNAFinal);
        R.ObjectiveImmersion     = objImmFinal;
        R.ObjectiveCorrection    = objCorrFinal;
        R.ObjectiveImmersionRI   = finalizeNumeric(objImmRIFinal);
        R.CondenserNA            = finalizeNumeric(condenserNAVals);
        R.IlluminationType       = illuminationTypeVals;
        R.ContrastMethod         = contrastMethodVals;

        R.DetectorID             = detectorIDVals;
        R.DetectorType           = detectorTypeVals;
        R.DetectorVoltage        = finalizeNumeric(detVolt);
        R.DetectorOffset         = finalizeNumeric(detOff);
        R.DigitalGain            = finalizeNumeric(digitalGainVals);
        R.PhotonCounting         = photonCountingVals;

        R.SoftwareName           = softwareNameVals;
        R.SoftwareVersion        = softwareVersionVals;

        logmsg(verbose, '    Done in %.2f s', toc(fileTimer));

    catch ME
        R.Error = string(ME.message);
        if verbose
            fprintf(2, '[%s]     ERROR: %s\n', char(datetime('now', 'Format', 'HH:mm:ss')), ME.message);
            drawnow;
        end
    end
end

function R = makeEmptyResult()
    emptyText = string.empty(0,1);

    R = struct( ...
        'FileName', "", ...
        'FullPath', "", ...
        'PixelSizeX_um', [], ...
        'PixelSizeY_um', [], ...
        'PixelSizeZ_um', [], ...
        'SizeX_px', [], ...
        'SizeY_px', [], ...
        'SizeZ_count', [], ...
        'SizeC_count', [], ...
        'SizeT_count', [], ...
        'FrameSize_px', emptyText, ...
        'MicroscopeName', emptyText, ...
        'MicroscopeSystem', emptyText, ...
        'MicroscopeType', emptyText, ...
        'StageName', emptyText, ...
        'ShutterDeviceName', emptyText, ...
        'FocusDeviceName', emptyText, ...
        'FocusMaintenanceDevice', emptyText, ...
        'ScanUnitName', emptyText, ...
        'ScanDirection', emptyText, ...
        'ScanMode', emptyText, ...
        'ScanSpeed', [], ...
        'FrameTime_s', [], ...
        'AveragingNumber', [], ...
        'AveragingMethod', emptyText, ...
        'PinholeSizeAiry', [], ...
        'PinholeDiameter_um', [], ...
        'LaserWavelength_nm', [], ...
        'LaserPower_mW', [], ...
        'LaserIntensitySetting', [], ...
        'LaserTransmission_pct', [], ...
        'TunableLaser', emptyText, ...
        'DetectionRange_nm', emptyText, ...
        'EmissionWavelength_nm', [], ...
        'DichroicName', emptyText, ...
        'BeamSplitterOrFilter', emptyText, ...
        'ObjectiveName', emptyText, ...
        'ObjectiveMagnification', [], ...
        'ObjectiveNA', [], ...
        'ObjectiveImmersion', emptyText, ...
        'ObjectiveCorrection', emptyText, ...
        'ObjectiveImmersionRI', [], ...
        'CondenserNA', [], ...
        'IlluminationType', emptyText, ...
        'ContrastMethod', emptyText, ...
        'DetectorID', emptyText, ...
        'DetectorType', emptyText, ...
        'DetectorVoltage', [], ...
        'DetectorOffset', [], ...
        'DetectorGain', [], ...
        'DigitalGain', [], ...
        'PhotonCounting', emptyText, ...
        'SoftwareName', emptyText, ...
        'SoftwareVersion', emptyText, ...
        'TrackMultiplexType', emptyText, ...
        'AcquisitionMode', emptyText, ...
        'ZStackStart_um', [], ...
        'ZStackEnd_um', [], ...
        'ZStep_um', [], ...
        'TimeInterval_s', [], ...
        'Error', "" );
end

function files = findCziFiles(rootDir, fileNameRegex)
    if nargin < 2 || isempty(fileNameRegex)
        fileNameRegex = "";
    else
        fileNameRegex = string(fileNameRegex);
    end

    entries = dir(rootDir);
    entries = entries(~ismember({entries.name}, {'.', '..'}));

    files = {};
    for i = 1:numel(entries)
        thisPath = fullfile(entries(i).folder, entries(i).name);
        if entries(i).isdir
            subFiles = findCziFiles(thisPath, fileNameRegex);
            if ~isempty(subFiles)
                files = [files; subFiles]; %#ok<AGROW>
            end
        else
            if endsWith(entries(i).name, '.czi', 'IgnoreCase', true)
                if strlength(fileNameRegex) == 0 || ...
                        ~isempty(regexpi(entries(i).name, char(fileNameRegex), 'once'))
                    files{end+1,1} = thisPath; %#ok<AGROW>
                end
            end
        end
    end
end

function meta = collectOriginalMetadata(reader)
    keys = {};
    vals = {};

    [k, v] = javaMapToPairs(safeGet(@() reader.getGlobalMetadata()));
    [keys, vals] = appendPairs(keys, vals, k, v);

    currentSeries = countOrZero(safeGet(@() reader.getSeries()));
    seriesCount   = countOrZero(safeGet(@() reader.getSeriesCount()));

    for s = 0:seriesCount-1
        reader.setSeries(s);
        [k, v] = javaMapToPairs(safeGet(@() reader.getSeriesMetadata()));
        [keys, vals] = appendPairs(keys, vals, k, v);
    end
    reader.setSeries(currentSeries);

    meta.keys = keys;
    meta.values = vals;
end

function [keys, vals] = javaMapToPairs(jMap)
    keys = {};
    vals = {};

    if isempty(jMap)
        return;
    end

    try
        it = jMap.keySet().iterator();
        while it.hasNext()
            k = it.next();
            keys{end+1,1} = safeText(k); %#ok<AGROW>
            vals{end+1,1} = safeText(jMap.get(k)); %#ok<AGROW>
        end
    catch
        try
            en = jMap.keys();
            while en.hasMoreElements()
                k = en.nextElement();
                keys{end+1,1} = safeText(k); %#ok<AGROW>
                vals{end+1,1} = safeText(jMap.get(k)); %#ok<AGROW>
            end
        catch
        end
    end
end

function [keysOut, valsOut] = appendPairs(keysIn, valsIn, k, v)
    keysOut = keysIn;
    valsOut = valsIn;
    if isempty(k)
        return;
    end
    keysOut = [keysOut; k];
    valsOut = [valsOut; v];
end

function out = getRawText(meta, keyPatterns, valuePatterns)
    if nargin < 3
        valuePatterns = {};
    end
    vals = findRawValues(meta, keyPatterns, valuePatterns);
    out = finalizeText(vals);
end

function out = getRawNumbers(meta, keyPatterns, valuePatterns)
    if nargin < 3
        valuePatterns = {};
    end
    vals = findRawValues(meta, keyPatterns, valuePatterns);
    num = [];
    for i = 1:numel(vals)
        num = [num, parseNumericTokens(vals{i})]; %#ok<AGROW>
    end
    out = finalizeNumeric(num);
end

function out = getDeviceNames(meta, valuePatterns, includeRefs)
    if nargin < 3
        includeRefs = false;
    end

    out = getRawText(meta, { ...
        '\|Configuration\|Device\|(Name|UniqueName)(?:\s*#\d+)?$'}, valuePatterns);

    if includeRefs
        out = mergeText(out, getRawText(meta, { ...
            '\|Configuration\|Device\|DeviceRef\|Id(?:\s*#\d+)?$'}, valuePatterns));
    end
end

function vals = findRawValues(meta, keyPatterns, valuePatterns)
    vals = {};
    if ~isfield(meta, 'keys') || isempty(meta.keys)
        return;
    end

    for i = 1:numel(meta.keys)
        k = meta.keys{i};
        v = meta.values{i};

        if matchesAny(k, keyPatterns)
            if isempty(valuePatterns) || matchesAny(v, valuePatterns)
                v = strtrim(v);
                if ~isempty(v)
                    vals{end+1,1} = v; %#ok<AGROW>
                end
            end
        end
    end
end

function tf = matchesAny(txt, patterns)
    if isempty(patterns)
        tf = true;
        return;
    end

    tf = false;
    for i = 1:numel(patterns)
        if ~isempty(regexpi(txt, patterns{i}, 'once'))
            tf = true;
            return;
        end
    end
end

function nums = parseNumericTokens(txt)
    tokens = regexp(txt, '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match');
    if isempty(tokens)
        nums = [];
        return;
    end

    nums = str2double(tokens);
    nums = nums(isfinite(nums));
end

function out = formatRanges(starts, ends)
    n = min(numel(starts), numel(ends));
    if n == 0
        out = string.empty(0,1);
        return;
    end

    vals = cell(n,1);
    for i = 1:n
        vals{i} = sprintf('%.12g-%.12g', starts(i), ends(i));
    end
    out = finalizeText(vals);
end

function [mag, na] = parseObjectiveMagNA(names)
    mag = [];
    na = [];

    if isempty(names)
        return;
    end

    if iscell(names)
        names = finalizeText(names);
    end

    for i = 1:numel(names)
        s = char(names(i));
        tok = regexp(s, '(\d+(?:\.\d+)?)x/(\d+(?:\.\d+)?)', 'tokens', 'once');
        if ~isempty(tok)
            mag = [mag, str2double(tok{1})]; %#ok<AGROW>
            na  = [na,  str2double(tok{2})]; %#ok<AGROW>
        end
    end

    mag = finalizeNumeric(mag);
    na  = finalizeNumeric(na);
end

function out = parseObjectiveCorrection(names)
    vals = {};
    if isempty(names)
        out = string.empty(0,1);
        return;
    end

    if iscell(names)
        names = finalizeText(names);
    end

    for i = 1:numel(names)
        s = char(names(i));
        tok = regexp(s, '^\s*([A-Za-z0-9\-\s]+?)\s+\d+(?:\.\d+)?x/', 'tokens', 'once');
        if ~isempty(tok)
            vals{end+1,1} = strtrim(tok{1}); %#ok<AGROW>
        end
    end

    out = finalizeText(vals);
end

function out = convertRawDistanceToUm(vec)
    vec = finalizeNumeric(vec);
    if isempty(vec)
        out = [];
        return;
    end

    % Many Zeiss original distance values are stored in meters.
    idx = abs(vec) < 1;
    vec(idx) = vec(idx) * 1e6;

    out = finalizeNumeric(vec);
end

function out = mergeNumeric(varargin)
    vals = [];
    for i = 1:nargin
        x = varargin{i};
        if isempty(x)
            continue;
        end
        vals = [vals, double(x(:)')]; %#ok<AGROW>
    end
    out = finalizeNumeric(vals);
end

function out = mergeText(varargin)
    vals = {};
    for i = 1:nargin
        x = varargin{i};
        if isempty(x)
            continue;
        end
        if isstring(x)
            vals = [vals; cellstr(x(:))]; %#ok<AGROW>
        elseif iscell(x)
            vals = [vals; x(:)]; %#ok<AGROW>
        else
            vals = [vals; {safeText(x)}]; %#ok<AGROW>
        end
    end
    out = finalizeText(vals);
end

function vec = addQuantity(vec, q, targetUnit)
    if isempty(q)
        return;
    end

    try
        numObj = q.value(targetUnit);
        if ~isempty(numObj)
            vec(end+1) = double(numObj.doubleValue()); %#ok<AGROW>
            return;
        end
    catch
    end

    try
        numObj = q.value();
        if ~isempty(numObj)
            vec(end+1) = double(numObj.doubleValue()); %#ok<AGROW>
        end
    catch
    end
end

function vec = addNumber(vec, v)
    d = toDoubleScalar(v);
    if ~isempty(d) && isfinite(d)
        vec(end+1) = d; %#ok<AGROW>
    end
end

function vec = addText(vec, v)
    s = strtrim(safeText(v));
    if ~isempty(s)
        vec(end+1,1) = string(s); %#ok<AGROW>
    end
end

function out = finalizeNumeric(vec)
    if isempty(vec)
        out = [];
        return;
    end

    vec = vec(isfinite(vec));
    if isempty(vec)
        out = [];
        return;
    end

    vec = round(vec * 1e12) / 1e12;
    out = unique(vec, 'stable');
end

function out = finalizeText(vals)
    if isempty(vals)
        out = string.empty(0,1);
        return;
    end

    s = strings(0,1);
    for i = 1:numel(vals)
        thisVal = vals{i};
        if isstring(thisVal)
            thisVal = char(thisVal);
        end
        thisVal = strtrim(thisVal);
        if ~isempty(thisVal)
            s(end+1,1) = string(thisVal); %#ok<AGROW>
        end
    end

    if isempty(s)
        out = string.empty(0,1);
        return;
    end

    out = unique(s, 'stable');
end

function out = safeGet(fh)
    try
        out = fh();
    catch
        out = [];
    end
end

function txt = safeText(obj)
    txt = '';
    if isempty(obj)
        return;
    end

    try
        if ischar(obj)
            txt = obj;
            return;
        end
    catch
    end

    try
        if isstring(obj)
            txt = char(obj);
            return;
        end
    catch
    end

    try
        txt = char(obj.toString());
        return;
    catch
    end

    try
        txt = char(string(obj));
    catch
        txt = '';
    end
end

function d = toDoubleScalar(v)
    d = [];
    if isempty(v)
        return;
    end

    try
        if isnumeric(v)
            d = double(v(1));
            return;
        end
    catch
    end

    try
        d = double(v.doubleValue());
        return;
    catch
    end

    try
        d = double(v.getValue());
        return;
    catch
    end

    try
        d = str2double(char(v.toString()));
        if ~isnan(d)
            return;
        end
    catch
    end

    try
        d = str2double(char(string(v)));
        if ~isnan(d)
            return;
        end
    catch
    end

    d = [];
end

function n = countOrZero(v)
    d = toDoubleScalar(v);
    if isempty(d) || ~isfinite(d)
        n = 0;
    else
        n = double(d);
    end
end

function closeReader(reader)
    if isempty(reader)
        return;
    end
    try
        reader.close();
    catch
    end
end

function logmsg(verbose, fmt, varargin)
    if ~verbose
        return;
    end
    fprintf('[%s] %s\n', char(datetime('now', 'Format', 'HH:mm:ss')), sprintf(fmt, varargin{:}));
    drawnow;
end
