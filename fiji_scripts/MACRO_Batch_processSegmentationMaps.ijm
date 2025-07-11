// ROI extraction & profiling on channel 2

print("=== ROI & Profile Macro Started ===");

File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");

parentDir = getDirectory("Select parent directory...");
print("Directory: " + parentDir);

pattern     = getString("Image pattern:","*seg.tif");
enlarge_px = getNumber("Enlarge ROI profiles (# pixels):", -3);



// Gather all matching files
regex    = globsToRegex(pattern);
files = listFilesRecursivePattern(parentDir, regex);


sets = 0;

print("=== Processing " + files.length + " datasets ===");

//setBatchMode(true);
    
for (i = 0; i < files.length; i++) {
    name = File.getName(files[i]);
    path = File.getParent(files[i]);
	if (endsWith(name, "_seg.tif")){
		    print("[" + sets + "] " + files[i]);
            processPair(files[i]);
            sets++;
	}
}
setBatchMode(false);

print("=== Completed: " + sets + " datasets ===");




function processPair(seg){
    close("*");

    orig = replace(seg, "_seg.tif", ".tif");
    if(!File.exists(orig)) orig = replace(orig, "/", "\\");
    if(!File.exists(orig)){
        print("> Missing original: " + seg);
        return;
    }


    // Build and save ROIs from the segmentation map
    open(seg);
    setAutoThreshold("Default dark no-reset");
    setOption("BlackBackground", true);
    run("Convert to Mask");
    run("Watershed");
    run("Close-");
    run("Open");
	run("Analyze Particles...", "size=40-1000 circularity=0.20-1.00 exclude clear overlay add composite");
    dirPath  = substring(seg, 0, lastIndexOf(seg, "/") + 1);
    baseProb = substring(seg, lastIndexOf(seg, "/") + 1, lastIndexOf(seg, "."));
    roiPath  = dirPath + baseProb + "_ROIs.zip";

	
    roiManager("Save", roiPath);
    print("> Saved ROIs: " + roiPath);
    close();

    // Prepare channel 2 image
    open(orig);
    title = getTitle();
    run("Split Channels");
    c2 = "C2-" + title;
    selectWindow(c2);
   // run("Enhance Contrast", "saturated=0.35");
    roiManager("Show All without labels");

    dirPath = substring(orig, 0, lastIndexOf(orig, "/") + 1);
    base    = substring(orig, lastIndexOf(orig, "/") + 1, lastIndexOf(orig, "."));
    csvPath = dirPath + base + "_ch2Profile.csv";


    nROI = roiManager("count");

	run("Set Measurements...", "area mean standard min centroid center perimeter fit shape feret's integrated median skewness kurtosis redirect=None decimal=9");
    roiManager("Select All");
    roiManager("Measure");

	saveAs("Results",csvPath);	
		
		
    // Cleanup
    close("*");
    roiManager("reset");
    run("Collect Garbage");
}



