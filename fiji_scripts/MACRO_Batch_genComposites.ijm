// Robust batch macro for Bio-Formats CZI import + Z-projection (Sum), skipping dialog and DAPI enhancement



File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");
dir = getDirectory("Choose the top-level directory");
searchString = getString("Enter search string to filter CZI files", "");
processFolder(dir, searchString);

function processFolder(folder, searchString) {
    list = getFileList(folder);
    for (i = 0; i < list.length; i++) {
        path = folder + list[i];
        if (File.isDirectory(path)) {
            processFolder(path, searchString); // recurse into subfolders
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
            }
            else if (indexOf(path, "Z3") != -1) {
                baseName = extractBaseName(path);
                outPath = getOutputPath(path, baseName + "_proj.tif");
                if (File.exists(outPath)) {
                    print("Skipping existing Z3 processed file: " + outPath);
                    continue;
                }
                processZ3File(path);
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

    run("Z Project...", "projection=[Sum Slices]");
    run("Royal");

    projTitle = getTitle();
    print("Z-projected image: " + projTitle);

    outName = baseName + ".png";
    outPath = getOutputPath(path, outName);

    print("Saving to: " + outPath);
    saveAs("PNG", outPath);

    close();
    selectWindow(origTitle);
    close();
}

function processZ3File(path) {
    print("Processing Z3 file: " + path);

    baseName = extractBaseName(path);

    run("Bio-Formats Importer", 
        "open=[" + path + "] autoscale color_mode=Colorized view=Hyperstack stack_order=XYCZT");

    origTitle = getTitle();
    print("Opened image: " + origTitle);
    selectWindow(origTitle);

    run("Z Project...", "projection=[Sum Slices]");
    projTitle = getTitle();
    print("Z-projected image: " + projTitle);

    outName = baseName + "_proj.tif";
    outPath = getOutputPath(path, outName);

    print("Saving to: " + outPath);
    saveAs("Tiff", outPath);
    close();
    
    selectWindow(origTitle);
    close();
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
