// Batch-processing Fiji/ImageJ macro saving ROI masks

// Entry point
File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");
parentDir    = getDirectory("Select parent directory to process:");
pattern      = getString("Search for files ending with:", "*_proj.tif");
suffix       = getString("Suffix for saved mask files (without extension):", "_ROImask");
skipExisting = getBoolean("Skip files if output already exists?");

// Build regex for search
regex = globsToRegex(pattern);

// Gather all files recursively
fileList = listFilesRecursivePattern(parentDir, regex);
print("# files found: " + fileList.length);

// Clear the Log and announce start
call("ij.IJ.log", "");
print("=== Batch ROI Mask Generation ===");
print("Parent directory: " + parentDir);
print("Processing files ending with: " + regex);
print("Mask output suffix: " + suffix);
print("---------------------------------------------");

for (i = 0; i < fileList.length; i++) {
    dir     = File.getDirectory(fileList[i]);
    name    = File.getNameWithoutExtension(fileList[i]);
    output  = dir + name + suffix + ".tif";
    if (skipExisting && File.exists(output)) {
        print("> Skipping (exists): " + output);
        continue;
    }
    print("[" + i + "] " + fileList[i]);
    processFile(fileList[i], suffix);
}

print("---------------------------------------------");
print("=== Batch mask generation complete ===");
showMessage("Batch mask generation complete.");


// Open, prompt ROI, create and save mask
function processFile(path, suffix) {
    open(path);
    for (c = 1; c <= 2; c++) {
    	 Stack.setChannel(c);
    	run("Enhance Contrast", "saturated=0.5");
    }
    Stack.setChannel(1);

    setTool("polygon");
    waitForUser("Draw ROI and click OK");

    // Generate binary mask from ROI
    run("Create Mask");

    // Save mask image
    dir    = File.getDirectory(path);
    name   = File.getNameWithoutExtension(path);
    output = dir + name + suffix + ".tif";
    saveAs("Tiff", output);
    print("> Saved mask: " + output);

    // Close all images
    close("*");
}