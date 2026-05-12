// Batch-processing Fiji/ImageJ macro for ROI-based crop + rotate export
//
// For each recursively discovered ROI file matching the glob pattern, this macro:
//   1. Finds the paired TIFF in the same directory by removing the ROI suffix.
//   2. Opens the TIFF and loads the ROI.
//   3. Uses the line ROI stroke width to straighten/crop the source image.
//   4. Rotates the straightened crop so the line start point is at the top
//      and the long axis is vertical.
//   5. Saves output as <source_name><output_suffix>.tif in the same directory.

// Entry point
lastDirPrefKey = "helper_fnc.cropRotateFromLineROI.lastParentDir";
fallbackParentDir = "C:/Users/dstolz/My Drive/PROJECTS/";
defaultParentDir = call("ij.Prefs.get", lastDirPrefKey, fallbackParentDir);
File.setDefaultDirectory(defaultParentDir);
parentDir = getDirectory("Select parent directory to process:");

if (parentDir == "")
    exit("No parent directory selected.");

call("ij.Prefs.set", lastDirPrefKey, parentDir);
roiPattern = getString("Search for ROI files ending with:", "*_roi.roi");
roiSuffix = getString("ROI filename suffix (without extension):", "_roi");
outputSuffix = getString("Output TIFF suffix (without extension):", "_cropped");
fallbackLineWidth = getNumber("Fallback line width (pixels) if ROI width is missing:", 600);
overwriteExisting = getBoolean("Overwrite existing output TIFF files?");

regex = globsToRegex(toLowerCase(roiPattern));
roiList = listFilesRecursivePattern(parentDir, regex);

call("ij.IJ.log", "");
print("=== Batch Crop + Rotate from Line ROI ===");
print("Parent directory: " + parentDir);
print("ROI glob: " + roiPattern);
print("ROI suffix: " + roiSuffix + ".roi");
print("Output suffix: " + outputSuffix + ".tif");
print("Fallback line width: " + fallbackLineWidth + " px");
print("Overwrite existing outputs: " + overwriteExisting);
print("# ROI files found: " + roiList.length);
print("---------------------------------------------");

run("ROI Manager...");
roiManager("reset");

processed = 0;
skipped = 0;
failed = 0;

for (i = 0; i < roiList.length; i++) {
    print("[" + (i + 1) + "/" + roiList.length + "] " + roiList[i]);
    status = processRoiFile(roiList[i], roiSuffix, outputSuffix, fallbackLineWidth, overwriteExisting);

    if (status == "processed")
        processed++;
    else if (status == "skipped")
        skipped++;
    else
        failed++;
}

roiManager("reset");
print("---------------------------------------------");
print("Processed: " + processed);
print("Skipped:   " + skipped);
print("Failed:    " + failed);
print("=== Batch crop + rotate complete ===");
showMessage("Batch crop + rotate complete.");


function processRoiFile(roiPath, roiSuffix, outputSuffix, fallbackLineWidth, overwriteExisting) {
    dir = File.getDirectory(roiPath);
    roiBase = File.getNameWithoutExtension(roiPath);
    sourceBase = inferSourceBase(roiBase, roiSuffix);

    if (sourceBase == "") {
        print("> Could not infer source base from ROI name: " + roiPath);
        return "failed";
    }

    tifPath = dir + sourceBase + ".tif";
    outPath = dir + sourceBase + outputSuffix + ".tif";

    if (!File.exists(tifPath)) {
        print("> Source TIFF not found; skipping: " + tifPath);
        return "skipped";
    }

    if (!overwriteExisting && File.exists(outPath)) {
        print("> Output exists; skipping: " + outPath);
        return "skipped";
    }

    if (overwriteExisting && File.exists(outPath))
        File.delete(outPath);

    open(tifPath);
    sourceId = getImageID();

    roiManager("reset");
    roiManager("Open", roiPath);

    if (roiManager("count") < 1) {
        print("> ROI file could not be loaded: " + roiPath);
        close("*");
        roiManager("reset");
        return "failed";
    }

    roiManager("Select", 0);
    roiType = selectionType();
    if (roiType < 5 || roiType > 7) {
        print("> ROI is not a line type; skipping: " + roiPath);
        close("*");
        roiManager("reset");
        return "skipped";
    }

    getLine(x1, y1, x2, y2, lineWidth);
    if (x1 == -1) {
        print("> Could not read line geometry; skipping: " + roiPath);
        close("*");
        roiManager("reset");
        return "failed";
    }

    // Prefer width stored with the ROI, fall back if it is missing.
    lineWidth = getValue("selection.width");
    if (lineWidth != lineWidth || lineWidth <= 0)
        lineWidth = fallbackLineWidth;

    selectImage(sourceId);
    roiManager("Select", 0);
    // Use 'process' so Straighten is applied to the full stack/hyperstack,
    // preserving all channels in the cropped output.
    run("Straighten...", "line=" + lineWidth + " process");

    croppedId = getImageID();
    if (croppedId == sourceId) {
        print("> Straighten did not create output; failed: " + roiPath);
        close("*");
        roiManager("reset");
        return "failed";
    }

    // Straighten returns long axis horizontal (start->end, left->right).
    // Rotate right so start point moves to top and long axis becomes vertical.
    selectImage(croppedId);
    run("Rotate 90 Degrees Right");

    rename(sourceBase + outputSuffix);
    saveAs("Tiff", outPath);
    print("> Saved: " + outPath);

    close("*");
    roiManager("reset");
    return "processed";
}


function inferSourceBase(roiBase, roiSuffix) {
    roiBaseLower = toLowerCase(roiBase);
    suffixLower = toLowerCase(roiSuffix);

    if (!endsWith(roiBaseLower, suffixLower))
        return "";

    return substring(roiBase, 0, lengthOf(roiBase) - lengthOf(roiSuffix));
}


function listFilesRecursivePattern(dir, regex) {
    list = getFileList(dir);
    hits = newArray(0);

    for (j = 0; j < list.length; j++) {
        path = dir + list[j];

        if (File.isDirectory(path)) {
            hits = Array.concat(hits, listFilesRecursivePattern(path, regex));
        } else {
            if (matches(toLowerCase(list[j]), regex))
                hits = Array.concat(hits, newArray(path));
        }
    }

    return hits;
}


function globsToRegex(glob) {
    regex = "^";
    specials = ".\\+()^$|{}[]";

    for (k = 0; k < lengthOf(glob); k++) {
        ch = substring(glob, k, k + 1);

        if (ch == "*")
            regex = regex + ".*";
        else if (ch == "?")
            regex = regex + ".";
        else if (indexOf(specials, ch) >= 0)
            regex = regex + "\\" + ch;
        else
            regex = regex + ch;
    }

    regex = regex + "$";
    return regex;
}