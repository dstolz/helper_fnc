#target photoshop

// Batch Photomerge with selectable alignment mode
// Operational goals:
// - Recursively processes subfolders of a selected parent folder
// - Prompts once at startup for the alignment mode to use for the full batch
// - Defaults to translation-only alignment (Reposition)
// - Skips folders with fewer than 2 eligible source images
// - Skips folders that already have the exact stitched PSD output
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

var CURRENT_ALIGNMENT = null;

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

function getAlignmentChoices() {
    return [
        { label: "Translation only (Reposition)", key: "translation", shortLabel: "translation (Reposition only)", index: 0 },
        { label: "Auto", key: "Auto", shortLabel: "Auto", index: 1 },
        { label: "Perspective", key: "Prsp", shortLabel: "Perspective", index: 2 },
        { label: "Cylindrical", key: "cylindrical", shortLabel: "Cylindrical", index: 3 },
        { label: "Spherical", key: "spherical", shortLabel: "Spherical", index: 4 },
        { label: "Collage", key: "sceneCollage", shortLabel: "Collage", index: 5 }
    ];
}

function promptAlignmentMode() {
    var choices = getAlignmentChoices();
    var labels = [];
    var i;

    for (i = 0; i < choices.length; i++) {
        labels.push(choices[i].label);
    }

    var w = new Window("dialog", "Photomerge Alignment");
    w.orientation = "column";
    w.alignChildren = "fill";
    w.spacing = 10;
    w.margins = 16;

    var intro = w.add("statictext", undefined, "Choose the alignment mode for this batch run.");
    intro.alignment = "fill";

    var dd = w.add("dropdownlist", undefined, labels);
    dd.selection = 0; // Default: translation only

    var note = w.add(
        "statictext",
        undefined,
        "Translation only keeps the current no-scale, no-skew, no-perspective behavior.\nOther modes allow Photoshop to use broader panorama layout transforms.",
        { multiline: true }
    );
    note.alignment = "fill";

    var buttons = w.add("group");
    buttons.alignment = "right";
    buttons.add("button", undefined, "OK", { name: "ok" });
    buttons.add("button", undefined, "Cancel", { name: "cancel" });

    if (w.show() !== 1) {
        return null;
    }

    return choices[dd.selection.index];
}

function writeInProgressMarker(folder, fileList) {
    if (!CREATE_IN_PROGRESS_MARKER) {
        return;
    }

    var marker = getInProgressMarkerFile(folder);
    var alignmentLabel = CURRENT_ALIGNMENT ? CURRENT_ALIGNMENT.shortLabel : "unknown";

    try {
        if (marker.open("w")) {
            marker.writeln("Photomerge started: " + nowStamp());
            marker.writeln("Folder: " + folder.fullName);
            marker.writeln("Image count: " + fileList.length);
            marker.writeln("Alignment mode: " + alignmentLabel);
            marker.writeln("Alignment key: " + (CURRENT_ALIGNMENT ? CURRENT_ALIGNMENT.key : "unknown"));
            marker.writeln("Blending: enabled");
            marker.writeln("Lens correction: disabled");
            marker.writeln("Vignette removal: disabled");
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
}

function applyAlignmentSettings() {
    if (!CURRENT_ALIGNMENT) {
        throw new Error("No alignment mode has been selected.");
    }

    photomerge.interactiveFlag = false;
    photomerge.alignmentKey = CURRENT_ALIGNMENT.key;

    // Keep blending enabled for seam construction.
    photomerge.advancedBlending = true;

    // Keep these disabled for consistency with the prior resilient script.
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
            liveLogFile.writeln("Alignment mode: " + (CURRENT_ALIGNMENT ? CURRENT_ALIGNMENT.shortLabel : "unknown"));
            liveLogFile.writeln("Alignment key: " + (CURRENT_ALIGNMENT ? CURRENT_ALIGNMENT.key : "unknown"));
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

    logMessage(
        "START: " + folder.fullName +
        " | images=" + fileList.length +
        " | input=" + formatGB(totalInputBytes) + " GB" +
        " | alignment=" + (CURRENT_ALIGNMENT ? CURRENT_ALIGNMENT.shortLabel : "unknown")
    );
    writeInProgressMarker(folder, fileList);

    try {
        applyAlignmentSettings();
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
        "Alignment mode: " + (CURRENT_ALIGNMENT ? CURRENT_ALIGNMENT.shortLabel : "unknown") + "\n" +
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
    loadPhotomergeEngine();

    CURRENT_ALIGNMENT = promptAlignmentMode();
    if (CURRENT_ALIGNMENT === null) {
        alert("Operation canceled.");
        return;
    }

    app.displayDialogs = DialogModes.NO;

    var parentFolder = Folder.selectDialog("Select the parent folder containing subfolders for batch Photomerge");
    if (!parentFolder) {
        alert("No folder selected. Operation canceled.");
        return;
    }

    initializeLiveLog(parentFolder);

    logMessage("Starting batch Photomerge in: " + parentFolder.fullName);
    logMessage("Alignment mode: " + CURRENT_ALIGNMENT.shortLabel);
    logMessage("Alignment key: " + CURRENT_ALIGNMENT.key);
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
