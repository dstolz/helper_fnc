// Batch macro: Split 2-channel TIF files into individual single-channel TIF images.
// Recursively searches a parent directory. Skips files that already have outputs.
// Optionally rescales to a target pixel size (µm/px) using bilinear interpolation.

File.setDefaultDirectory("C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES");
dir = getDirectory("Choose the top-level directory");

// --- Configuration dialog ---
Dialog.create("Split Channel Settings");
Dialog.addString("Filter TIF files (leave blank for all):", "");
Dialog.addMessage("Output filename suffixes:");
Dialog.addString("Channel 1 suffix:", "_ECM");
Dialog.addString("Channel 2 suffix:", "_PV");
Dialog.addCheckbox("Swap channel assignment (Ch2 → suffix1, Ch1 → suffix2)", false);
Dialog.addMessage("--- Scaling ---");
Dialog.addCheckbox("Rescale images to target pixel size", true);
Dialog.addNumber("Source pixel size (µm/px):", 1.6573); // TO DO: derive this from image metadata instead of user input
Dialog.addNumber("Target pixel size (µm/px):", 0.645);
Dialog.show();

searchString = Dialog.getString();
suffix1     = Dialog.getString();
suffix2     = Dialog.getString();
swapCh      = Dialog.getCheckbox();
doScale     = Dialog.getCheckbox();
srcPx       = Dialog.getNumber();
tgtPx       = Dialog.getNumber();

if (swapCh) {
    tmp = suffix1; suffix1 = suffix2; suffix2 = tmp;
}

scaleFactor = srcPx / tgtPx;  // >1 means upscale

// --- Confirmation ---
msg  = "Proceed with these settings?\n\n";
msg += "  Channel 1  →  *" + suffix1 + ".tif\n";
msg += "  Channel 2  →  *" + suffix2 + ".tif\n";
if (searchString != "")
    msg += "  Filename filter: " + searchString + "\n";
if (doScale)
    msg += "  Scale: " + srcPx + " → " + tgtPx + " µm/px  (factor " + d2s(scaleFactor, 4) + ")\n";
else
    msg += "  No scaling.\n";

if (!getBoolean(msg))
    exit("Cancelled.");

// --- Run ---
processFolder(dir, searchString, suffix1, suffix2, doScale, scaleFactor);
print("Done.");

// =========================================================
function processFolder(folder, searchString, suffix1, suffix2, doScale, scaleFactor) {
    list = getFileList(folder);
    for (i = 0; i < list.length; i++) {
        path = folder + list[i];
        if (File.isDirectory(path)) {
            processFolder(path, searchString, suffix1, suffix2, doScale, scaleFactor);
        } else {
            lpath = toLowerCase(path);
            if (endsWith(lpath, ".tif") || endsWith(lpath, ".tiff")) {
                // Skip files that are already split outputs
                if (endsWith(lpath, toLowerCase(suffix1) + ".tif")  ||
                    endsWith(lpath, toLowerCase(suffix1) + ".tiff") ||
                    endsWith(lpath, toLowerCase(suffix2) + ".tif")  ||
                    endsWith(lpath, toLowerCase(suffix2) + ".tiff")) {
                    print("Skipping output file: " + path);
                    continue;
                }
                // Apply filename filter
                if (searchString != "" && indexOf(path, searchString) == -1)
                    continue;
                processFile(path, suffix1, suffix2, doScale, scaleFactor);
            }
        }
    }
}

function processFile(path, suffix1, suffix2, doScale, scaleFactor) {
    baseName = extractBaseName(path);
    outDir   = extractDir(path);
    out1     = outDir + baseName + suffix1 + ".tif";
    out2     = outDir + baseName + suffix2 + ".tif";

    if (File.exists(out1) && File.exists(out2)) {
        print("Skipping (outputs exist): " + path);
        return;
    }

    print("Processing: " + path);

    // Open without autoscale so display settings do not affect saved data
    run("Bio-Formats Importer",
        "open=[" + path + "] color_mode=Grayscale view=Hyperstack stack_order=XYCZT");

    origTitle = getTitle();
    origID    = getImageID();

    // Verify channel count
    getDimensions(imgW, imgH, nCh, nZ, nFrames);
    if (nCh != 2) {
        print("WARNING: Expected 2 channels, found " + nCh + " — skipping: " + path);
        selectImage(origID);
        close();
        return;
    }

    // Split channels — closes original, opens "C1-<title>" and "C2-<title>"
    run("Split Channels");

    c1Title = "C1-" + origTitle;
    c2Title = "C2-" + origTitle;

    if (!File.exists(out1)) {
        selectWindow(c1Title);
        if (doScale) scaleImage(scaleFactor);


        % TO DO: make this user option
        run("Subtract Background...", "rolling=10 sliding disable");

        saveAs("Tiff", out1);
        print("  Saved Ch1: " + out1);
    } else {
        print("  Ch1 output already exists, skipping save.");
        selectWindow(c1Title);
    }
    close();

    if (!File.exists(out2)) {
        selectWindow(c2Title);
        if (doScale) scaleImage(scaleFactor);
        saveAs("Tiff", out2);
        print("  Saved Ch2: " + out2);
    } else {
        print("  Ch2 output already exists, skipping save.");
        selectWindow(c2Title);
    }
    close();
}

function extractBaseName(path) {
    slashIdx = maxOf(lastIndexOf(path, "/"), lastIndexOf(path, "\\"));
    name = substring(path, slashIdx + 1);
    dotIdx = lastIndexOf(name, ".");
    if (dotIdx > 0)
        name = substring(name, 0, dotIdx);
    return name;
}

function extractDir(path) {
    slashIdx = maxOf(lastIndexOf(path, "/"), lastIndexOf(path, "\\"));
    return substring(path, 0, slashIdx + 1);
}

function scaleImage(scaleFactor) {
    // Rescale the current image by scaleFactor using bilinear interpolation.
    // scaleFactor = srcPx / tgtPx  (e.g. 2.0 = upscale 2×)
    origID = getImageID();
    origName = getTitle();
    w = getWidth();
    h = getHeight();
    newW = round(w * scaleFactor);
    newH = round(h * scaleFactor);
    run("Scale...", "x=" + scaleFactor + " y=" + scaleFactor +
        " width=" + newW + " height=" + newH +
        " interpolation=Bilinear average create");
    // Rename scaled window to match original title, then close the original
    rename(origName);
    selectImage(origID);
    close();
    selectWindow(origName);
}
