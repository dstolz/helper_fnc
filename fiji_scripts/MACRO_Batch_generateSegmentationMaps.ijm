// Recursive Batch Segmenting with Labkit in ImageJ Macro language, with skip-if-exists logic

// Set your working directory
File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");

// User inputs
parentDir   = getDirectory("Choose Parent Directory…");
pattern     = getString("Image pattern:",       "*proj.tif");
classifier  = File.openDialog("Select Labkit classifier file");
useROIMask  = getBoolean("Use ROI mask?");
if (useROIMask) {
    patternROI = getString("ROI search pattern:", "*ROImask.tif");
}

// Gather all matching files
regex    = globsToRegex(pattern);
fileList = listFilesRecursivePattern(parentDir, regex);
print("=== BEGIN SEGMENTING  " + fileList.length + " IMAGES ===");

for (i = 0; i < fileList.length; i++) {
    imagePath = fileList[i];
    name = File.getName(imagePath);
    dot = lastIndexOf(name, ".");
    if (dot > 0) {
        base = substring(name, 0, dot);
    } else {
        base = name;
    }
    outPath = File.getParent(imagePath) + File.separator + base + "_seg.tif";

    if (File.exists(outPath)) {
        print("[" + i + "] Skipping existing segmentation: " + outPath);
        continue;
    }

    print("[" + i + "] Processing: " + imagePath);

    // locate the matching mask
    maskPath = "";
    if (useROIMask) {
        dir  = File.getDirectory(imagePath);
        regexROI = globsToRegex(patternROI);
        files    = getFileList(dir);
        for (j = 0; j < files.length; j++) {
            f = files[j];
            if (matches(f, regexROI) && startsWith(f, base)) {
                maskPath = dir + f;
                break;
            }
        }

        if (File.exists(maskPath)) {
            print("> Mask: " + maskPath);
        } else {
            print("> No mask found for " + name);
            continue;
        }
    }

    processFile(imagePath, classifier, maskPath);
}

print("=== DONE ===");

// Main processing: mask multiplication, segment channel 1 and recombine with channel 2
function processFile(path, classifier, maskPath) {
    // Open and split channels
    open(path);
    origTitle = getTitle();
    run("Split Channels");
    c1Title = "C1-" + origTitle;
    c2Title = "C2-" + origTitle;
    
    selectWindow(c1Title);

	c1Processed = c1Title;


    // Background subtraction
    run("Subtract Background...", "rolling=20");
    
   	run("Enhance Contrast", "saturated=0.10");


    // Apply binary mask to channel 1
    if (File.exists(maskPath)) {
        open(maskPath);
        maskTitle = getTitle();
        run("Make Binary");
        run("32-bit");
        imageCalculator("Multiply create 32-bit", c1Processed, maskTitle);
        c1Processed = getTitle();
    }

	


    // Segment masked channel 1
    print("> Segmenting ...");
    selectWindow(c1Processed);
    run("Segment Image With Labkit", "segmenter_file=[" + classifier + "] use_gpu=true");
    segTitle = getTitle();
    
    selectWindow(segTitle);
    run("8-bit");

    // Save final output
    name2 = File.getName(path);
    dot2  = lastIndexOf(name2, ".");
    if (dot2 > 0) {
        base2 = substring(name2, 0, dot2);
    } else {
        base2 = name2;
    }
    dir = File.getParent(path) + File.separator;
    ffnOut = dir + base2 + "_seg.tif";

    print("> Saving merged output as: " + ffnOut);
    saveAs("Tiff", ffnOut);
    
    
    // Find maxima
   	setAutoThreshold("Default dark no-reset");
   	setOption("BlackBackground", true);
	run("Convert to Mask");   

	run("Morphological Filters", "operation=Opening element=Disk radius=1");
	run("Morphological Filters", "operation=Closing element=Disk radius=1");
	

	// detect and remove small particles
	run("Analyze Particles...", "size=0-78 clear add");
	setForegroundColor(0, 0, 0);
    run("Select All");
	roiManager("Fill");
	roiManager("Deselect");
	roiManager("Delete");
    
	run("Chamfer Distance Map", "distances=[Chessknight (5,7,11)] output=[16 bits] normalize");
	
	run("Find Maxima...", "prominence=1 exclude output=List");
	
	ffnMax = dir + base2 + "_seg_maxima.csv";
    
	saveAs("Results", ffnMax);


    //print("> Saved ROIs: " + roiPath);
    print("> Saved maxima xy: " + ffnMax);


    // Cleanup
    close("*");
    run("Collect Garbage");
}
