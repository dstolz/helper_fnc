// Recursive Batch Segmenting with Labkit in ImageJ Macro language
// Prompts user for: parent directory, search pattern, and Labkit classifier file.

// Global counter for progress
processedCount = 0;

// Main processing function
function processFolder(parent, pattern, classifier) {
    list = getFileList(parent);
    regex = globToRegex(pattern);
    for (i = 0; i < list.length; i++) {
        name = list[i];
        path = parent + name;
        // Recurse into directories
        if (File.isDirectory(path)) {
            processFolder(path, pattern, classifier);
        } else {
            // Process files matching pattern
            if (matches(name, regex)) {

                // Increment and log progress
                processedCount++;
                print("[" + processedCount + "] Processing: " + path);

                // Open image and remember its title
                open(path);
                origTitle = getTitle();
                
                // Run Labkit segmentation with quoted path to handle spaces
                run("Segment Image With Labkit", "segmenter_file=[" + classifier + "] use_gpu=false");
                
                // Build base filename (without extension)
                base = substring(name, 0, lengthOf(name) - 4);
                
                // Save probability map (currently active window)
                saveAs("Tiff", parent + base + "_prob_map.tif");
                print("[" + processedCount + "] Saved probability map: " + parent + base + "_prob_map.tif");
                
                // Close all open windows
                close("*");
            }
        }
    }
}

// Utility: Convert a glob pattern (e.g., "*proj.tif") to a Java regex
function globToRegex(glob) {
    regex = replace(glob, "\\.", "\\\\.");  // escape literal dots
    regex = replace(regex, "*", ".*");
    regex = replace(regex, "?", ".");
    return "^" + regex + "$";
}

// Prompt user inputs
parentDir = getDirectory("Choose Parent Directory...");
pattern   = getString("Search pattern (glob):", "*proj_ROI_FF.tif");

// Set default folder for classifier dialog (change as needed)
File.setDefaultDirectory("G:/Shared drives/CarasLab/IMAGES/");
// Prompt for Labkit classifier file via dialog
classifier = File.openDialog("Select Labkit classifier file");

// Run processing with logging
setBatchMode(true);
processFolder(parentDir, pattern, classifier);
setBatchMode(false);

// Final summary
print("Done! Processed " + processedCount + " files.");
