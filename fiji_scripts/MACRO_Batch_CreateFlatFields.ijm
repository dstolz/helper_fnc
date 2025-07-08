//dfltDir = "G:/Shared drives/CarasLab/IMAGES";

dir = getDirectory("Choose a Directory");
count = 1;

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
            print((count++) + ". Found file: " + path);
            result = Array.concat(result, path);
        }
    }
    return result;
}

// --- Get file list ---
suffix = getString("Enter a suffix:", "_proj_ROI.tif");
print("You entered suffix: " + suffix);

fileList = listFilesRecursive(dir, suffix);
print("Total files to process: " + fileList.length);

// --- Process each file ---
setBatchMode(true);
count = 1;
for (i = 0; i < fileList.length; i++) {
    inputFile = fileList[i];
    print(count + ". Opening: " + inputFile);
    open(inputFile);

    // Split into channels
    print("    Splitting into channels...");
    run("Split Channels");

    // Duplicate Channel 2 (unaltered) and match bit depth
    print("    Extracting Channel 2...");
    titles = getList("image.titles");
    for (j = 0; j < titles.length; j++) {
        if (indexOf(titles[j], "C2-") != -1) {
            selectWindow(titles[j]);
            run("Duplicate...", "title=C2_Original");
            run("16-bit");
            print("      -> C2_Original duplicated and converted to 16-bit");
            break;
        }
    }

    // Select and process Channel 1
    print("    Processing Channel 1 pipeline...");
    for (j = 0; j < titles.length; j++) {
        if (indexOf(titles[j], "C1-") != -1) {
            selectWindow(titles[j]);
            break;
        }
    }
    run("Duplicate...", "title=C1_Original");
    run("Enhance Contrast...", "saturated=0.35 normalize");
    run("Duplicate...", "title=Illumination_Profile");

    run("16-bit");
    run("Pseudo flat field correction", "blurring=200 hide");
    run("Enhance Contrast", "saturated=0.1");
    rename("FlatField_Corrected");

    run("Convoluted Background Subtraction", "convolution=Mean radius=50");
    run("Enhance Contrast...", "saturated=0.35 normalize");


    // Save output
    dirOut = File.getParent(inputFile);
    name = File.getName(inputFile);
    dotIndex = indexOf(name, ".");
    if (dotIndex != -1)
        newName = substring(name, 0, dotIndex) + "_FF" + substring(name, dotIndex);
    else
        newName = name + "_FF_stack";
    FFFile = dirOut + File.separator + newName;

    saveAs("Tiff", FFFile);
    print(count + ". Finished and saved.\n");

    // Close all windows
    close("*");
    count++;
}
setBatchMode(false);













