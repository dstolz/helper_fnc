// ROI extraction & profiling on channel 2

print("=== Batch tif to png ===");

File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");

parentDir = getDirectory("Select parent directory...");
print("Directory: " + parentDir);

pattern     = getString("Image pattern:","*proj.tif");

// Gather all matching files
regex    = globsToRegex(pattern);
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
enhanceSaturation = 0.35;

function processTif(path) {
    // Determine file directory and base name (without extension)
    dir = File.getDirectory(path);
    basename = File.getName(path);
    nameNoExt = replace(basename, ".tif", "");


    open(path);
	
	origTitle = getTitle();

    run("Split Channels");
    c1Title = "C1-" + origTitle;
    c2Title = "C2-" + origTitle;
    
    selectWindow(c1Title);
	run("Enhance Contrast", "saturated=0.35");
	saveAs("PNG", dir + replace(origTitle,".tif","_C1.png"));
    
    selectWindow(c2Title);
	run("Enhance Contrast", "saturated=0.35");
	saveAs("PNG", dir + replace(origTitle,".tif","_C2.png"));
	
	
    close("*");
}



