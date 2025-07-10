// Batch-processing Fiji/ImageJ macro saving ROI masks

// Entry point
File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");
parentDir    = getDirectory("Select parent directory to process:");
pattern      = getString("Search for files ending with:", "*_proj.tif");
suffix       = getString("Suffix for saved mask files (without extension):", "_ROImask");
skipExisting = getBoolean("Skip files if output already exists?");

// Build regex for search
globPattern = globToRegex(pattern);

// Gather all files recursively
fileList = listFilesRecursivePattern(parentDir, globPattern);
print("# files found: " + fileList.length);

// Clear the Log and announce start
call("ij.IJ.log", "");
print("=== Batch ROI Mask Generation ===");
print("Parent directory: " + parentDir);
print("Processing files ending with: " + globPattern);
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

// Utility: Convert a glob pattern to a Java regex
function globToRegex(glob) {
    regex = replace(glob, "\\.", "\\\\.");  // escape dot
    regex = replace(regex, "*", ".*");
    regex = replace(regex, "?", ".");
    return "^" + regex + "$";
}

// Recursive file collection
function listFilesRecursivePattern(dir, regex) {
    list = getFileList(dir);
    result = newArray();
    for (j = 0; j < list.length; j++) {
        path = dir + list[j];
        if (File.isDirectory(path)) {
            sub = listFilesRecursivePattern(path, regex);
            result = Array.concat(result, sub);
        } else if (matches(list[j], regex)) {
            result = Array.concat(result, path);
        }
    }
    return result;
}

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