
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
            print((count++) + ". " + path);
            result = Array.concat(result, path);
        }
    }
    return result;
}




// --- Get file list ---
suffix = getString("Enter a suffix:", "_ACx.tif");
print("You entered: " + suffix);

fileList = listFilesRecursive(dir,suffix);

// --- Process each file ---
count = 1;
for (i = 0; i < fileList.length; i++) {
    inputFile = fileList[i];

    open(inputFile);
    print((count) +". Preprocessing: " + inputFile);

    run("Split Channels");

    // Select Channel 1 (C1)
    titles = getList("image.titles");
    found = 0;
    for (j = 0; j < titles.length; j++) {
        if (indexOf(titles[j], "C1-") != -1) {
            selectWindow(titles[j]);
            found = 1;
            break;
        }
    }
    if (found == 0) {
        print("C1 image not found in: " + inputFile);
        close("*");
        continue;
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

    dirOut = File.getParent(inputFile);
    name = File.getName(inputFile);
    dotIndex = indexOf(name, ".");
    if (dotIndex != -1)
        newName = substring(name, 0, dotIndex) + "_FF" + substring(name, dotIndex);
    else
        newName = name + "_FF";

    FFFile = dirOut + File.separator + newName;
    print((count++) + ". Saving: " + FFFile);
    saveAs("Tiff", FFFile);

    close("*");
}
