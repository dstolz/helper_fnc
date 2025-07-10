// ROI extraction & line profiling on channel 2

print("=== ROI & Profile Macro Started ===");

File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");

parentDir = getDirectory("Select parent directory...");
print("Directory: " + parentDir);


enlarge_px = getNumber("Enlarge ROI profiles (# pixels):", -3);
thickness_um = getNumber("Profile thickness (µm):", 6);


files = listFilesRecursive(parentDir, "_seg.tif");

sets = 0;

print("=== Processing " + files.length + " datasets ===");

setBatchMode(true);
    
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



// --- Recursive file collection ---
function listFilesRecursive(dir, suffix) {
    list = getFileList(dir);
    result = newArray();
    for (i = 0; i < list.length; i++) {
        path = dir + list[i];
        if (File.isDirectory(path)) {
            sublist = listFilesRecursive(path, suffix);
            result = Array.concat(result, sublist);
        } else if (endsWith(list[i], suffix)) {
            result = Array.concat(result, path);
        }
    }
    return result;
}


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
    setAutoThreshold("Otsu dark no-reset");
    setOption("BlackBackground", true);
    run("Convert to Mask");
    run("Watershed");
    run("Close-");
    run("Open");
	run("Analyze Particles...", "size=150-750 circularity=0.40-1.00 exclude clear overlay add composite");
    dirPath  = substring(seg, 0, lastIndexOf(seg, "/") + 1);
    baseProb = substring(seg, lastIndexOf(seg, "/") + 1, lastIndexOf(seg, "."));
    roiPath  = dirPath + baseProb + "_ROIs.zip";
    if(File.exists(roiPath)) File.delete(roiPath);
    roiManager("Save", roiPath);
    print("> Saved ROIs: " + roiPath);
    close();

    // Prepare channel 2 image
    open(orig);
    title = getTitle();
    run("Split Channels");
    c2 = "C2-" + title;
    selectWindow(c2);
    run("Enhance Contrast", "saturated=0.35");
    roiManager("Show All without labels");

    dirPath = substring(orig, 0, lastIndexOf(orig, "/") + 1);
    base    = substring(orig, lastIndexOf(orig, "/") + 1, lastIndexOf(orig, "."));
    csvPath = dirPath + base + "_ch2Profile.csv";


    nROI = roiManager("count");
    print("> Processing " + nROI + " ROIs");
    
	run("Set Measurements...", "area mean standard min centroid center perimeter fit shape feret's integrated median skewness kurtosis redirect=None decimal=9");

    
    for (r = 0; r < nROI; r++) {
    	roiManager("Select",r);
		run("Make Band...", "band=" + thickness_um);
		
	    if (enlarge_px != 0)
	    	run("Enlarge...", "enlarge=" + enlarge_px);
    }

    roiManager("Select All");
    roiManager("Measure");

	saveAs("Results",csvPath);	
		
		
    // Cleanup
    close("*");
    roiManager("reset");
    
    run("Collect Garbage");
}
