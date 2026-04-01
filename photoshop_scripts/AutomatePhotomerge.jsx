#target photoshop

// Batch Photomerge with translation-only alignment (Reposition)
// - Recursively processes subfolders of a selected parent folder
// - Skips folders with fewer than 2 eligible source images
// - Skips folders that already have the exact stitched PSD output
// - Loads Photomerge.jsx once and configures it for translation-only alignment
// - Restores Photoshop dialog state when finished
// - Writes a simple run log into the selected parent folder

var ORIGINAL_DIALOG_MODE = app.displayDialogs;
var runphotomergeFromScript = true; // Must exist before Photomerge.jsx is loaded

// Configuration
var PROCESS_SELECTED_PARENT_FOLDER = false; // Preserve original behavior: process subfolders only
var SAVE_PNG_COPY = true;
var OVERWRITE_EXISTING_OUTPUT = false;
var LOG_FILENAME = "Photomerge_Batch_Log.txt";

var stats = {
    processed: 0,
    stitched: 0,
    skippedExisting: 0,
    skippedTooFewImages: 0,
    errors: 0
};

var logMessages = [];

function logMessage(message) {
    logMessages.push(message);
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

    // Allow only the blending needed to create the montage.
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

    // Save PSD first so the layered master is preserved before any flattened copy is written.
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

function performPhotomerge(folder) {
    stats.processed++;

    var fileList = getEligibleImageFiles(folder);
    var outputs = getOutputFiles(folder);

    if (fileList.length < 2) {
        stats.skippedTooFewImages++;
        logMessage("SKIP (not enough images): " + folder.fullName);
        return;
    }

    if (!OVERWRITE_EXISTING_OUTPUT && hasExistingStitchedOutput(folder)) {
        stats.skippedExisting++;
        logMessage("SKIP (stitched PSD already exists): " + outputs.psd.fsName);
        return;
    }

    var startDocumentCount = app.documents.length;

    try {
        photomerge.createPanorama(fileList, false);

        if (app.documents.length <= startDocumentCount) {
            throw new Error("Photomerge did not produce a new document.");
        }

        saveOutputs(folder);
        app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);

        stats.stitched++;
        logMessage("OK: " + folder.fullName + " -> " + outputs.psd.name + (SAVE_PNG_COPY ? ", " + outputs.png.name : ""));
    } catch (e) {
        stats.errors++;
        logMessage("ERROR: " + folder.fullName + " | " + e.message);
        closeDocumentsOpenedDuringOperation(startDocumentCount);
    }
}

function processAllSubfolders(parentFolder) {
    var folders = getSubfolders(parentFolder);

    for (var i = 0; i < folders.length; i++) {
        performPhotomerge(folders[i]);
        processAllSubfolders(folders[i]);
    }
}

function writeLogFile(parentFolder) {
    var logFile = new File(parentFolder.fsName + "/" + LOG_FILENAME);

    if (logFile.open("w")) {
        logFile.writeln("Batch Photomerge log");
        logFile.writeln("Parent folder: " + parentFolder.fullName);
        logFile.writeln("");
        logFile.writeln("Processed folders: " + stats.processed);
        logFile.writeln("Stitched: " + stats.stitched);
        logFile.writeln("Skipped (existing output): " + stats.skippedExisting);
        logFile.writeln("Skipped (too few images): " + stats.skippedTooFewImages);
        logFile.writeln("Errors: " + stats.errors);
        logFile.writeln("");
        logFile.writeln("Details:");

        for (var i = 0; i < logMessages.length; i++) {
            logFile.writeln(logMessages[i]);
        }

        logFile.close();
        return logFile;
    }

    return null;
}

function buildSummary(parentFolder, logFile) {
    var summary = "Batch Photomerge completed.\n\n" +
        "Parent folder: " + parentFolder.fullName + "\n" +
        "Processed folders: " + stats.processed + "\n" +
        "Stitched: " + stats.stitched + "\n" +
        "Skipped (existing output): " + stats.skippedExisting + "\n" +
        "Skipped (too few images): " + stats.skippedTooFewImages + "\n" +
        "Errors: " + stats.errors;

    if (logFile !== null) {
        summary += "\n\nLog file: " + logFile.fsName;
    }

    return summary;
}

function main() {
    app.displayDialogs = DialogModes.NO;

    loadPhotomergeEngine();

    var parentFolder = Folder.selectDialog("Select the parent folder containing subfolders for translation-only Photomerge");
    if (!parentFolder) {
        alert("No folder selected. Operation cancelled.");
        return;
    }

    logMessage("Starting batch Photomerge in: " + parentFolder.fullName);
    logMessage("Alignment mode: translation (Reposition only)");
    logMessage("Advanced blending: enabled");
    logMessage("Lens correction: disabled");
    logMessage("Vignette removal: disabled");

    if (PROCESS_SELECTED_PARENT_FOLDER) {
        performPhotomerge(parentFolder);
    }

    processAllSubfolders(parentFolder);

    var logFile = writeLogFile(parentFolder);
    alert(buildSummary(parentFolder, logFile));
}

try {
    main();
} catch (fatalError) {
    alert("Batch Photomerge failed to start.\nError: " + fatalError.message);
} finally {
    app.displayDialogs = ORIGINAL_DIALOG_MODE;
}
