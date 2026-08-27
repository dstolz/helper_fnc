// Robust batch macro for Bio-Formats CZI import + Z-projection (Sum), skipping dialog and DAPI enhancement



File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");
dir = getDirectory("Choose the top-level directory");
searchString = getString("Enter search string to filter CZI files", "");

Dialog.create("Z3 Processing Mode");
Dialog.addRadioButtonGroup("Z3 stack handling", newArray("Middle Z section", "Z-projection (Sum Slices)"), 2, 1, "Middle Z section");
Dialog.show();
z3Mode = Dialog.getRadioButton();

processFolder(dir, searchString, z3Mode);

function processFolder(folder, searchString, z3Mode) {
    list = getFileList(folder);
    for (i = 0; i < list.length; i++) {
        path = folder + list[i];
        if (File.isDirectory(path)) {
            processFolder(path, searchString, z3Mode); // recurse into subfolders
        } else if (endsWith(path, ".czi")) {
            // Skip files that don't match the search string (if provided)
            if (searchString != "" && indexOf(path, searchString) == -1) {
                continue;
            }
            if (indexOf(path, "SLIDE") != -1) {
                baseName = extractBaseName(path);
                outPath = getOutputPath(path, baseName + ".png");
                if (File.exists(outPath)) {
                    print("Skipping existing SLIDE processed file: " + outPath);
                    continue;
                }
                processSLIDEFile(path);
                run("Close All");
            }
            else if (indexOf(path, "Z3") != -1) {
                baseName = extractBaseName(path);
                if (z3Mode == "Z-projection (Sum Slices)") {
                    outPath = getOutputPath(path, baseName + "_proj.tif");
                } else {
                    outPath = getOutputPath(path, baseName + "_mid.tif");
                }
                if (File.exists(outPath)) {
                    print("Skipping existing Z3 processed file: " + outPath);
                    continue;
                }
                processZ3File(path, z3Mode);
                run("Close All");
            } else if (indexOf(path, "Z1") != -1) {
                baseName = extractBaseName(path);
                outPath = getOutputPath(path, baseName + "_dapi.png");
                if (File.exists(outPath)) {
                    print("Skipping existing Z1 processed file: " + outPath);
                    continue;
                }
                //processZ1File(path);
            }
        }
    }
}

function processSLIDEFile(path) {
    print("Processing SLIDE file: " + path);

    baseName = extractBaseName(path);

    run("Bio-Formats Importer", 
        "open=[" + path + "] autoscale color_mode=Colorized view=Hyperstack stack_order=XYCZT");

    origTitle = getTitle();
    print("Opened image: " + origTitle);
    selectWindow(origTitle);

    run("Z Project...", "projection=[Average Intensity]");
    run("Enhance Contrast", "saturated=0.1 normalize");
    run("Grays");

    projTitle = getTitle();
    print("Z-projected image: " + projTitle);

    outName = baseName + ".png";
    outPath = getOutputPath(path, outName);

    print("Saving to: " + outPath);
    saveAs("PNG", outPath);

    close();
    selectWindow(origTitle);
    close();
    run("Close All");
}

function processZ3File(path, z3Mode) {
    print("Processing Z3 file: " + path);

    baseName = extractBaseName(path);

    run("Bio-Formats Importer",
        "open=[" + path + "] autoscale color_mode=Colorized view=Hyperstack stack_order=XYCZT");

    origID = getImageID();
    origTitle = getTitle();
    print("Opened image: " + origTitle);

    if (z3Mode == "Z-projection (Sum Slices)") {
        // Generate Z-projection across all slices
        run("Duplicate...", "title=Z_Proj duplicate channels=1-2 frames=1");
        run("Z Project...", "projection=[Sum Slices]");
        outName = baseName + "_proj.tif";
    } else {
        // select only the middle Z slice (Z3) for projection
        run("Duplicate...", "title=Middle_Z duplicate channels=1-2 slices=2 frames=1");
        outName = baseName + "_mid.tif";
    }

    outPath = getOutputPath(path, outName);

    print("Saving to: " + outPath);
    saveAs("Tiff", outPath);
    
    // Apply Make Composite to the Z-projected image
    run("Make Composite");
    compTitle = getTitle();
    print("Composite image: " + compTitle);

    outName = baseName + "_composite.png";
    outPath = getOutputPath(path, outName);

    print("Saving to: " + outPath);
    saveAs("PNG", outPath);
    close();

    // Close original
    selectImage(origID);
    close();
    run("Close All");
}

function processZ1File(path) {
    print("Processing Z1 file: " + path);

    baseName = extractBaseName(path);

    run("Bio-Formats Importer", 
        "open=[" + path + "] autoscale color_mode=Colorized view=Hyperstack stack_order=XYCZT");

    origTitle = getTitle();
    print("Opened image: " + origTitle);
    selectWindow(origTitle);


    run("Enhance Contrast", "saturated=0.35");
    run("Subtract Background...", "rolling=100");
    run("Enhance Contrast", "saturated=0.35");

    outName = baseName + "_dapi.png";
    outPath = getOutputPath(path, outName);

    print("Saving to: " + outPath);
    saveAs("PNG", outPath);

    close();
    run("Close All");
}

function extractBaseName(path) {
    slashIndex = lastIndexOf(path, File.separator);
    baseName = substring(path, slashIndex + 1);
    baseName = replace(baseName, ".czi", "");
    return baseName;
}

function getOutputPath(path, outName) {
    slashIndex = lastIndexOf(path, File.separator);
    outDir = substring(path, 0, slashIndex + 1);
    return outDir + outName;
}
