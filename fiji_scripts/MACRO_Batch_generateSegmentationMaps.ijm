// Recursive Batch Segmenting with Labkit in ImageJ Macro language

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
    print("[" + i + "] Processing: " + imagePath);

    // locate the matching mask
    maskPath = "";
    if (useROIMask) {
        dir  = File.getDirectory(imagePath);
        name = File.getName(imagePath);

        // strip extension without ternary
        dot = lastIndexOf(name, ".");
        if (dot > 0) {
            base = substring(name, 0, dot);
        } else {
            base = name;
        }

        // find mask in same folder
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


// Main processing: mask multiplication, then segment channel 1
function processFile(path, classifier, maskPath) {
    // Open and split channels
    open(path);
    origTitle = getTitle();
    run("Split Channels");
    c1Title = "C1-" + origTitle;
    selectWindow(c1Title);

    run("Subtract Background...", "rolling=20");

    // Apply binary mask by multiplication
    if (File.exists(maskPath)) {
        open(maskPath);
        maskTitle = getTitle();
        run("Make Binary");
        run("32-bit");
        imageCalculator("Multiply create 32-bit", c1Title, maskTitle);
    }

    // Segment
    print("> Segmenting ...");
    run("Segment Image With Labkit", "segmenter_file=[" + classifier + "] use_gpu=true");
    
    // Prepare output filename with ROI suffix if available
    name2 = File.getName(path);
    dot2  = lastIndexOf(name2, ".");
    if (dot2 > 0) {
        base2 = substring(name2, 0, dot2);
    } else {
        base2 = name2;
    }
    dir = File.getParent(path) + File.separator;

    // Compute mask suffix
    maskSuffix = "";
    if (File.exists(maskPath)) {
        maskName2 = File.getName(maskPath);
        dot3      = lastIndexOf(maskName2, ".");
        if (dot3 > 0) {
            maskBase2 = substring(maskName2, 0, dot3);
        } else {
            maskBase2 = maskName2;
        }
        if (startsWith(maskBase2, base2)) {
            maskSuffix = substring(maskBase2, lengthOf(base2), lengthOf(maskBase2));
        } else {
            maskSuffix = "_" + maskBase2;
        }
    }

    // Save output
    ffnOut = dir + base2 + maskSuffix + "_seg.tif";
    print("> Saving segmentation as: " + ffnOut;
    saveAs("Tiff", ffnOut);

    close("*");
    run("Collect Garbage");
}




// Recursive file listing
function listFilesRecursivePattern(dir, regex) {
    list   = getFileList(dir);
    result = newArray();
    for (i = 0; i < list.length; i++) {
        path = dir + list[i];
        if (File.isDirectory(path)) {
            sub = listFilesRecursivePattern(path, regex);
            result = Array.concat(result, sub);
        } else if (matches(list[i], regex)) {
            result = Array.concat(result, newArray(path));
        }
    }
    return result;
}



// Utility: Convert glob to regex
function globsToRegex(glob) {
    regex = replace(glob, "\\.", "\\\\.");
    regex = replace(regex, "*", ".*");
    regex = replace(regex, "?", ".");
    return "^" + regex + "$";
}
