// ROI extraction & profiling on channel 2 with skip-if-exists logic

print("=== Batch tif to png ===");

File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");

parentDir = getDirectory("Select parent directory...");
print("Directory: " + parentDir);

pattern = getString("Image pattern:", "*proj.tif");

// Gather all matching files
regex = globsToRegex(pattern);
files = listFilesRecursivePattern(parentDir, regex);

print("=== Processing " + files.length + " datasets ===");

close("*");
setBatchMode(true);

for (i = 0; i < files.length; i++) {
    print("[" + i + "] " + files[i]);
    processTif(files[i]);
}

setBatchMode(false);

// Cleanup
close("*");
run("Collect Garbage");

print("=== Completed: " + files.length + " datasets ===");


// processTif.ijm - Macro to process each channel and slice of a TIFF hyperstack,
// enhance contrast, and save each plane as a separate PNG file

function processTif(path) {
    dir = File.getDirectory(path);
    basename = File.getName(path);
    nameNoExt = replace(basename, ".tif", "");

    outC1 = dir + nameNoExt + "_C1.png";
    outC2 = dir + nameNoExt + "_C2.png";

    if (File.exists(outC1) && File.exists(outC2)) {
        print("Skipping existing processed files for: " + path);
        return;
    }

    open(path);
    origTitle = getTitle();

    run("Split Channels");
    c1Title = "C1-" + origTitle;
    c2Title = "C2-" + origTitle;

    if (!File.exists(outC1)) {
        selectWindow(c1Title);
        run("Enhance Contrast", "saturated=0.35");
        saveAs("PNG", outC1);
    }

    if (!File.exists(outC2)) {
        selectWindow(c2Title);
        run("Enhance Contrast", "saturated=0.35");
        saveAs("PNG", outC2);
    }

    close("*");
}