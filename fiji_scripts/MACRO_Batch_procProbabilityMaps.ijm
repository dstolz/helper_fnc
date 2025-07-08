// ROI extraction & line profiling on channel 2, with centroid coords and user-defined length & thickness

print("=== ROI & Profile Macro Started ===");
parentDir = getDirectory("Select parent directory...");
print("Directory: " + parentDir);

// Prompt for line profile length and thickness
length_um = getNumber("Line profile length (µm):", 40);
thickness_um = getNumber("Profile thickness (µm):", 4);

sets = 0;

function scan(dir){
    files = getFileList(dir);
    for(i = 0; i < files.length; i++){
        name = files[i];
        path = dir + name;
        if(endsWith(name, "/")) scan(path);
        else if(endsWith(name, "_prob_map.tif")){
            print("Found: " + path);
            processPair(path);
            sets++;
        }
    }
}

function processPair(prob){
    close("*");

    orig = replace(prob, "_prob_map.tif", ".tif");
    if(!File.exists(orig)) orig = replace(orig, "/", "\\");
    if(!File.exists(orig)){
        print("Missing original: " + prob);
        return;
    }
    print("Processing: " + prob);

    // Build and save ROIs from the probability map
    open(prob);
    setAutoThreshold("Otsu dark no-reset");
    setOption("BlackBackground", true);
    run("Convert to Mask");
    run("Watershed");
    run("Analyze Particles...", "size=20-Infinity exclude clear overlay add composite");
    dirPath  = substring(prob, 0, lastIndexOf(prob, "/") + 1);
    baseProb = substring(prob, lastIndexOf(prob, "/") + 1, lastIndexOf(prob, "."));
    roiPath  = dirPath + baseProb + "_ROIs.zip";
    if(File.exists(roiPath)) File.delete(roiPath);
    roiManager("Save", roiPath);
    print("Saved ROIs: " + roiPath);
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
    csvPath = dirPath + base + "_ch2_profile.csv";
    if (File.exists(csvPath)) File.delete(csvPath);

    setBatchMode(true);
    run("Set Measurements...", "centroid redirect=None decimal=9");
    run("Clear Results");

    selectWindow(c2);
    roiManager("Select All");
    roiManager("Measure");
    count = roiManager("count");

    // Calibration using user inputs
    getVoxelSize(px, py, pz, unit);
    halfLenPix = (length_um/px) / 2.0;
    lenPix     = round(halfLenPix);
    dxPix      = 2 * lenPix;
    iw = getWidth(); ih = getHeight();

    // Loop and write rows with centroid coords + profile
    for (r = 0; r < count; r++) {
        // Centroid in calibrated units
        xCcal = getResult("X", r);
        yCcal = getResult("Y", r);
        
        // Pixel coords for sampling
        xC = round(xCcal/px);
        yC = round(yCcal/py);

        // Line endpoints without max/min
        x1 = xC - lenPix;
        if (x1 < 0) x1 = 0;
        x2 = xC + lenPix;
        if (x2 > iw - 1) x2 = iw - 1;
        
        // Vertical window based on thickness without max/min
        vertHalf = round((thickness_um/2.0) / py);
        yLow = yC - vertHalf;
        if (yLow < 0) yLow = 0;
        yHigh = yC + vertHalf;
        if (yHigh > ih - 1) yHigh = ih - 1;
        heightPix = yHigh - yLow + 1;

         // Initialize CSV row as a string, using d2s for numeric-to-string conversion
   		row = "" + d2s(xCcal,9) + "," + d2s(yCcal,9);
      
        // Sample along the line
        for (p = 0; p <= dxPix; p++) {
            sumVal = 0;
            xPos = x1 + p;
            for (q = yLow; q <= yHigh; q++) {
            	sumVal = sumVal + getPixel(xPos, q);
            }
            meanVal = sumVal / heightPix;
            row = row + "," + d2s(meanVal,3);
        }

        File.append(row, csvPath);
    }

    // Cleanup
    close("*");
    roiManager("reset");
    setBatchMode(false);
    print("Done: " + base);
}

scan(parentDir);
print("=== Completed: " + sets + " sets ===");
