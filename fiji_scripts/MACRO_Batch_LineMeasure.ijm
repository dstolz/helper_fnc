// Batch-processing Fiji/ImageJ macro for channel-1 line-profile extraction
//
// For each recursively discovered TIFF matching the glob pattern, this macro:
//   - Optionally skips files whose <original_name><values_suffix>.csv already exists.
//   1. Opens the source TIFF.
//   2. Duplicates channel 1 into its own image without altering pixel values.
//   3. Activates the straight line tool with a 600-pixel line width by default.
//   4. Prompts to draw a line ROI or skip the current file.
//   5. Adds the line ROI to ROI Manager, selects it, and runs ROI Manager Multi Plot.
//   6. Saves the plotted profile values as <original_name>_values.csv.
//   7. Saves the line ROI as <original_name>_roi.roi.
//   8. Closes all image/plot windows and proceeds to the next TIFF.

// Entry point
lastDirPrefKey = "helper_fnc.lineMeasure.lastParentDir";
fallbackParentDir = getInfo("user.home") + "/My Drive/PROJECTS/";
if (!File.isDirectory(fallbackParentDir))
    fallbackParentDir = getInfo("user.home") + "/";
defaultParentDir = call("ij.Prefs.get", lastDirPrefKey, fallbackParentDir);
File.setDefaultDirectory(defaultParentDir);
parentDir = getDirectory("Select parent directory to process:");

if (parentDir == "")
    exit("No parent directory selected.");

call("ij.Prefs.set", lastDirPrefKey, parentDir);
pattern = getString("Search for files ending with:", "*_proj.tif");
lineWidth = getNumber("Line tool/profile width in pixels:", 600);
valuesSuffix = getString("Values file suffix:", "_values");
skipIfValuesExists = getBoolean("Skip files when the values CSV already exists?\n\n"
    + "Click Yes to skip files with existing values CSV output.\n"
    + "Click No to process all files.");

regex = globsToRegex(toLowerCase(pattern));
fileList = listFilesRecursivePattern(parentDir, regex);

call("ij.IJ.log", "");
print("=== Batch Channel-1 Line Profile Extraction ===");
print("Parent directory: " + parentDir);
print("Search glob: " + pattern);
print("Line width: " + lineWidth + " pixels");
print("Values suffix: " + valuesSuffix + ".csv");
print("Skip existing values CSV: " + skipIfValuesExists);
print("ROI suffix: _roi.roi");
print("# files found: " + fileList.length);
print("---------------------------------------------");

run("ROI Manager...");
roiManager("reset");

for (i = 0; i < fileList.length; i++) {
    print("[" + (i + 1) + "/" + fileList.length + "] " + fileList[i]);
    processFile(fileList[i], lineWidth, valuesSuffix, skipIfValuesExists);
}

roiManager("reset");
print("---------------------------------------------");
print("=== Batch line-profile extraction complete ===");
showMessage("Batch line-profile extraction complete.");


function processFile(path, lineWidth, valuesSuffix, skipIfValuesExists) {
    dir = File.getDirectory(path);
    base = File.getNameWithoutExtension(path);
    valuesOut = dir + base + valuesSuffix + ".csv";
    roiOut = dir + base + "_roi.roi";

    if (skipIfValuesExists && File.exists(valuesOut)) {
        print("> Values CSV already exists; skipping: " + valuesOut);
        return;
    }

    open(path);
    sourceTitle = getTitle();

    Stack.getDimensions(imgWidthPx, imgHeightPx, channelCount, sliceCount, frameCount);
    if (channelCount > 1)
        Stack.setChannel(1);

    dupTitle = base + "_C1_for_line_profile";
    duplicateChannelOne(dupTitle, channelCount, sliceCount, frameCount);
    selectWindow(dupTitle);

    roiManager("reset");

    // Set the line tool and line width before drawing.
    // The Line Width command is used because it controls the width used for line-profile averaging.
    setLineWidth(lineWidth);
    run("Line Width...", "line=" + lineWidth);
    setTool("line");

    processThisFile = getBoolean("Process this file?\n\n"
        + "File: " + File.getName(path) + "\n\n"
        + "Click Yes to draw a straight line ROI.\n"
        + "Click No to skip this file and continue.");
    if (!processThisFile) {
        print("> Skipped by user: " + path);
        close("*");
        roiManager("reset");
        return;
    }

    waitForUser("Draw a straight line ROI on the duplicated channel-1 image.\n"
        + "Line width is set to " + lineWidth + " pixels.\n"
        + "Click OK when the line is finished.");

    if (selectionType() == -1) {
        print("> No ROI was drawn; skipping: " + path);
        close("*");
        roiManager("reset");
        return;
    }

    // Re-apply the width to the active line ROI before adding it to ROI Manager.
    setLineWidth(lineWidth);
    run("Line Width...", "line=" + lineWidth);

    roiType = selectionType();
    if (roiType < 5 || roiType > 7)
        print("> Warning: selected ROI is not a line ROI. selectionType() = " + roiType);



    roiManager("Add");
    roiManager("Select", 0);
    roiManager("Rename", base + "_roi");
    roiManager("Select", 0);

    // Plot from ROI Manager as requested.
    roiManager("multi plot");

    // Save the x/y values from the active Multi Plot window.
    // For uncalibrated images, the x-axis is the pixel distance/profile index.
    Plot.getValues(xValues, yValues);
    deleteIfExists(valuesOut, "values CSV");
    saveXYCSV(valuesOut, xValues, yValues);
    print("> Saved values CSV: " + valuesOut);

    // Save the selected ROI as a single .roi file.
    roiManager("Select", 0);
    deleteIfExists(roiOut, "ROI file");
    roiManager("Save", roiOut);
    print("> Saved ROI: " + roiOut);

    // Close the source image, duplicated channel image, and plot window before continuing.
    close("*");
    roiManager("reset");
}


function duplicateChannelOne(dupTitle, channelCount, sliceCount, frameCount) {
    opts = "title=[" + dupTitle + "]";

    if (channelCount > 1 || sliceCount > 1 || frameCount > 1) {
        opts = opts + " duplicate";
        if (channelCount > 1)
            opts = opts + " channels=1";
        if (sliceCount > 1)
            opts = opts + " slices=1-" + sliceCount;
        if (frameCount > 1)
            opts = opts + " frames=1-" + frameCount;
    }

    run("Duplicate...", opts);
}


function saveXYCSV(path, xArray, yArray) {
    f = File.open(path);
    print(f, "distance_pixel_index,intensity");

    n = minOf(xArray.length, yArray.length);
    for (row = 0; row < n; row++)
        print(f, xArray[row] + "," + yArray[row]);

    File.close(f);
}


function deleteIfExists(path, label) {
    if (File.exists(path)) {
        File.delete(path);
        print("> Overwriting existing " + label + ": " + path);
    }
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
