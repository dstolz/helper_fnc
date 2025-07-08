// Batch-processing Fiji/ImageJ macro with progress logging

// Entry point
macro "Batch Process TIFFs" {
    parentDir    = getDirectory("Select parent directory to process:");
    searchString = getString("Search for files ending with:", "_proj.tif");
    suffix       = getString("Suffix for saved files (without extension):", "_ROI");
    
    // Clear the Log and announce start
    call("ij.IJ.log", ""); 
    print("=== Batch processing started at " + Date.getDate() + " ===");
    print("Parent directory: " + parentDir);
    print("Searching for files ending with: " + searchString);
    print("Output suffix: " + suffix);
    print("---------------------------------------------");
    
    processDirectory(parentDir, searchString, suffix);
    
    print("---------------------------------------------");
    print("=== Batch processing complete ===");
    showMessage("Batch processing complete.");
}

// Recursively traverse directories and process matching TIFFs
function processDirectory(dir, searchStr, suffix) {
    print("Entering directory: " + dir);
    list = getFileList(dir);
    for (i = 0; i < list.length; i++) {
        path = dir + list[i];
        if (File.isDirectory(path)) {
            processDirectory(path, searchStr, suffix);
        }
        else if (endsWith(list[i], searchStr)) {
            print("Found file: " + path);
            processFile(path, suffix);
        }
    }
}

// Open, process, and save a single TIFF
function processFile(path, suffix) {
    print("→ Processing file: " + path);
    open(path);

    // Enhance contrast on channels 1-2
    for (c = 1; c <= 2; c++) {
        Stack.setChannel(c);
        run("Enhance Contrast", "saturated=0.35 stack");
    }

    // Crop to user-drawn ROI and clear outside
    setTool("polygon");
    waitForUser("Draw ROI and click OK");
    run("Crop");
    setBackgroundColor(0, 0, 0);
    run("Clear Outside");

    // Keep only channels 1–2
    run("Make Substack...", "channels=1-2");

    // Convert to a 2-channel hyperstack **without** overlaying (composite)
    run("Stack to Hyperstack...", "order=xyzct channels=2 slices=1 frames=1 display=Grayscale");

    run("Select None");

    // Save with user-defined suffix
    saveDir = File.getDirectory(path);
    name    = File.getNameWithoutExtension(path);
    output  = saveDir + name + suffix + ".tif";
    saveAs("Tiff", output);
    print("✔ Saved: " + output);

    // Close all image windows after saving
    run("Close All");
    print("---------------------------------------------");
}
