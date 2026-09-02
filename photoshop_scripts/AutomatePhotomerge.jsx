#target photoshop

// Batch Photomerge with translation-only alignment (Reposition)
// Operational goals:
// - Recursively processes subfolders of a selected parent folder
// - Skips folders with fewer than 2 eligible source images
// - Skips folders that already have the exact stitched PSD output
// - Constrains geometric manipulation to translation only
// - Leaves blending enabled for seam construction
// - Writes a live log entry before each folder starts, so hangs are traceable
// - Optionally purges Photoshop caches between folders to reduce long-run slowdowns
// - Restores Photoshop dialog state when finished

var ORIGINAL_DIALOG_MODE = app.displayDialogs;
var runphotomergeFromScript = true; // Must exist before Photomerge.jsx is loaded

// Configuration
var PROCESS_SELECTED_PARENT_FOLDER = false; // Preserve prior behavior: process subfolders only
var SAVE_PNG_COPY = true;
var OVERWRITE_EXISTING_OUTPUT = false;
var LOG_FILENAME = "Photomerge_Batch_Log.txt";
var IN_PROGRESS_MARKER_NAME = "_PHOTOMERGE_IN_PROGRESS.txt";

// Safety / operational controls
var ENABLE_LIVE_LOGGING = true;          // Write each log line immediately to disk
var CREATE_IN_PROGRESS_MARKER = true;    // Leaves a breadcrumb if Photoshop stalls or is canceled
var PURGE_CACHES_BETWEEN_FOLDERS = true; // Helps long runs avoid cache buildup
var RUN_GARBAGE_COLLECTION = true;       // ExtendScript GC hint between folders

// Optional guards. Set to 0 to disable.
var MAX_IMAGES_PER_FOLDER = 0;           // Example: 20
var MAX_TOTAL_INPUT_GB = 0;              // Example: 4.0

var stats = {
    processed: 0,
    stitched: 0,
    skippedExisting: 0,
    skippedTooFewImages: 0,
    skippedTooManyImages: 0,
    skippedTooLarge: 0,
    errors: 0
};

var logMessages = [];
var liveLogFile = null;

function nowStamp() {
    var d = new Date();

    function pad(n) {
        return (n < 10 ? "0" : "") + n;
    }

    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) +
        " " + pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds());
}

function appendLiveLog(message) {
    if (!ENABLE_LIVE_LOGGING || liveLogFile === null) {
        return;
    }

    try {
        if (liveLogFile.open("a")) {
            liveLogFile.writeln(nowStamp() + " | " + message);
            liveLogFile.close();
        }
    } catch (ignore) {
    }
}

function logMessage(message) {
    logMessages.push(message);
    appendLiveLog(message);
    try {
        $.writeln(message);
    } catch (ignore) {
    }
}

function sortByName(a, b) {
    var aName = a.name.toLowerCase();
    var bName = b.name.toLowerCase();

    if (aName < bName) {
        return -1;
    }
    if (aName > bName) {
        return 1;
    }
    return 0;
}

function getEligibleImageFiles(folder) {
    var files = folder.getFiles(/\.(jpg|jpeg|tif|tiff|bmp)$/i);
    files.sort(sortByName);
    return files;
}

function getSubfolders(folder) {
    var folders = folder.getFiles(function(file) {
        return file instanceof Folder;
    });
    folders.sort(sortByName);
    return folders;
}

function getOutputBaseName(folder) {
    return folder.name + "_STITCHED";
}

function getOutputFiles(folder) {
    var baseName = getOutputBaseName(folder);
    return {
        psd: new File(folder.fsName + "/" + baseName + ".psd"),
        png: new File(folder.fsName + "/" + baseName + ".png")
    };
}

function hasExistingStitchedOutput(folder) {
    return getOutputFiles(folder).psd.exists;
}

function getInProgressMarkerFile(folder) {
    return new File(folder.fsName + "/" + IN_PROGRESS_MARKER_NAME);
}

function writeInProgressMarker(folder, fileList) {
    if (!CREATE_IN_PROGRESS_MARKER) {
        return;
    }

    var marker = getInProgressMarkerFile(folder);

    try {
        if (marker.open("w")) {
            marker.writeln("Photomerge started: " + nowStamp());
            marker.writeln("Folder: " + folder.fullName);
            marker.writeln("Image count: " + fileList.length);
            marker.writeln("Mode: translation only (Reposition)");
            marker.writeln("Blending: enabled");
            marker.writeln("");
            marker.writeln("Inputs:");

            var i;
            for (i = 0; i < fileList.length; i++) {
                marker.writeln(fileList[i].fsName);
            }

            marker.close();
        }
    } catch (ignore) {
    }
}

function removeInProgressMarker(folder) {
    if (!CREATE_IN_PROGRESS_MARKER) {
        return;
    }

    var marker = getInProgressMarkerFile(folder);
    try {
        if (marker.exists) {
            marker.remove();
        }
    } catch (ignore) {
    }
}

function getTotalInputBytes(fileList) {
    var total = 0;
    var i;

    for (i = 0; i < fileList.length; i++) {
        try {
            total += Number(fileList[i].length);
        } catch (ignore) {
        }
    }

    return total;
}

function formatGB(bytes) {
    return (bytes / (1024 * 1024 * 1024)).toFixed(2);
}

function loadPhotomergeEngine() {
    var photomergeScript = new File(app.path + "/Presets/Scripts/Photomerge.jsx");

    if (!photomergeScript.exists) {
        throw new Error("Photomerge.jsx not found at: " + photomergeScript.fsName);
    }

    $.evalFile(photomergeScript);

    // Constrain geometric manipulation to translation only.
    // This is the Photomerge "Reposition" mode: no scale, no skew, no perspective.
    photomerge.interactiveFlag = false;
    photomerge.alignmentKey = "translation";

    // Allow only seam blending needed to create the montage.
    photomerge.advancedBlending = true;

    // Disable other image-altering corrections.
    photomerge.lensCorrection = false;
    photomerge.removeVignette = false;
}

function saveOutputs(folder) {
    var outputs = getOutputFiles(folder);

    var psdSaveOptions = new PhotoshopSaveOptions();
    psdSaveOptions.layers = true;
    psdSaveOptions.embedColorProfile = true;
    psdSaveOptions.maximizeCompatibility = true;

    // Save layered master first.
    app.activeDocument.saveAs(outputs.psd, psdSaveOptions, true, Extension.LOWERCASE);

    if (SAVE_PNG_COPY) {
        var pngSaveOptions = new PNGSaveOptions();
        app.activeDocument.saveAs(outputs.png, pngSaveOptions, true, Extension.LOWERCASE);
    }
}

function closeDocumentsOpenedDuringOperation(startDocumentCount) {
    while (app.documents.length > startDocumentCount) {
        try {
            app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);
        } catch (closeError) {
            break;
        }
    }
}

function purgeCaches() {
    if (!PURGE_CACHES_BETWEEN_FOLDERS) {
        return;
    }

    try {
        app.purge(PurgeTarget.ALLCACHES);
    } catch (ignore) {
    }
}

function runGarbageCollection() {
    if (!RUN_GARBAGE_COLLECTION) {
        return;
    }

    try {
        $.gc();
    } catch (ignore) {
    }
}

function initializeLiveLog(parentFolder) {
    liveLogFile = new File(parentFolder.fsName + "/" + LOG_FILENAME);

    if (!ENABLE_LIVE_LOGGING) {
        return;
    }

    try {
        if (liveLogFile.open("w")) {
            liveLogFile.writeln("Batch Photomerge log");
            liveLogFile.writeln("Parent folder: " + parentFolder.fullName);
            liveLogFile.writeln("Started: " + nowStamp());
            liveLogFile.writeln("");
            liveLogFile.close();
        }
    } catch (ignore) {
        liveLogFile = null;
    }
}

function performPhotomerge(folder) {
    stats.processed++;

    var fileList = getEligibleImageFiles(folder);
    var outputs = getOutputFiles(folder);
    var totalInputBytes = getTotalInputBytes(fileList);
    var startDocumentCount = app.documents.length;

    if (fileList.length < 2) {
        stats.skippedTooFewImages++;
        logMessage("SKIP (not enough images): " + folder.fullName);
        return;
    }

    if (MAX_IMAGES_PER_FOLDER > 0 && fileList.length > MAX_IMAGES_PER_FOLDER) {
        stats.skippedTooManyImages++;
        logMessage("SKIP (too many images: " + fileList.length + "): " + folder.fullName);
        return;
    }

    if (MAX_TOTAL_INPUT_GB > 0 && (totalInputBytes / (1024 * 1024 * 1024)) > MAX_TOTAL_INPUT_GB) {
        stats.skippedTooLarge++;
        logMessage("SKIP (input set too large: " + formatGB(totalInputBytes) + " GB): " + folder.fullName);
        return;
    }

    if (!OVERWRITE_EXISTING_OUTPUT && hasExistingStitchedOutput(folder)) {
        stats.skippedExisting++;
        logMessage("SKIP (stitched PSD already exists): " + outputs.psd.fsName);
        return;
    }

    if (CREATE_IN_PROGRESS_MARKER && getInProgressMarkerFile(folder).exists) {
        logMessage("NOTICE (previous run may have stopped here): " + folder.fullName);
    }

    logMessage("START: " + folder.fullName + " | images=" + fileList.length + " | input=" + formatGB(totalInputBytes) + " GB");
    writeInProgressMarker(folder, fileList);

    try {
        photomerge.createPanorama(fileList, false);

        if (app.documents.length <= startDocumentCount) {
            throw new Error("Photomerge did not produce a new document.");
        }

        logMessage("MERGE RETURNED: " + folder.fullName);

        saveOutputs(folder);
        app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);
        removeInProgressMarker(folder);

        stats.stitched++;
        logMessage("OK: " + folder.fullName + " -> " + outputs.psd.name + (SAVE_PNG_COPY ? ", " + outputs.png.name : ""));
    } catch (e) {
        stats.errors++;
        logMessage("ERROR: " + folder.fullName + " | " + e.message);
        closeDocumentsOpenedDuringOperation(startDocumentCount);
        removeInProgressMarker(folder);
    } finally {
        purgeCaches();
        runGarbageCollection();
    }
}

function processAllSubfolders(parentFolder) {
    var folders = getSubfolders(parentFolder);
    var i;

    for (i = 0; i < folders.length; i++) {
        performPhotomerge(folders[i]);
        processAllSubfolders(folders[i]);
    }
}

function buildSummary(parentFolder) {
    var summary = "Batch Photomerge completed.\n\n" +
        "Parent folder: " + parentFolder.fullName + "\n" +
        "Processed folders: " + stats.processed + "\n" +
        "Stitched: " + stats.stitched + "\n" +
        "Skipped (existing output): " + stats.skippedExisting + "\n" +
        "Skipped (too few images): " + stats.skippedTooFewImages + "\n" +
        "Skipped (too many images): " + stats.skippedTooManyImages + "\n" +
        "Skipped (too large): " + stats.skippedTooLarge + "\n" +
        "Errors: " + stats.errors;

    if (liveLogFile !== null) {
        summary += "\n\nLog file: " + liveLogFile.fsName;
    }

    return summary;
}

function main() {
    app.displayDialogs = DialogModes.NO;

    loadPhotomergeEngine();

    var parentFolder = Folder.selectDialog("Select the parent folder containing subfolders for translation-only Photomerge");
    if (!parentFolder) {
        alert("No folder selected. Operation canceled.");
        return;
    }

    initializeLiveLog(parentFolder);

    logMessage("Starting batch Photomerge in: " + parentFolder.fullName);
    logMessage("Alignment mode: translation (Reposition only)");
    logMessage("Advanced blending: enabled");
    logMessage("Lens correction: disabled");
    logMessage("Vignette removal: disabled");
    logMessage("Cache purge between folders: " + (PURGE_CACHES_BETWEEN_FOLDERS ? "enabled" : "disabled"));
    logMessage("Garbage collection between folders: " + (RUN_GARBAGE_COLLECTION ? "enabled" : "disabled"));

    if (PROCESS_SELECTED_PARENT_FOLDER) {
        performPhotomerge(parentFolder);
    }

    processAllSubfolders(parentFolder);

    logMessage("Completed: " + nowStamp());
    alert(buildSummary(parentFolder));
}

try {
    main();
} catch (fatalError) {
    try {
        logMessage("FATAL: " + fatalError.message);
    } catch (ignore) {
    }
    alert("Batch Photomerge failed to start.\nError: " + fatalError.message);
} finally {
    app.displayDialogs = ORIGINAL_DIALOG_MODE;
}
