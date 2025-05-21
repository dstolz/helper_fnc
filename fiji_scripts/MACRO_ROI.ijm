// 1. Prompt user to open a _COMPOSITE.tif file
openPath = File.openDialog("Select a '_COMPOSITE.tif' file");
if (endsWith(openPath, "_COMPOSITE.tif")) {
    open(openPath);
} else {
    exit("Selected file does not end with '_COMPOSITE.tif'.");
}

// 2. Auto-adjust contrast on all slices (without changing pixel values)
// Enhance contrast on all channels across the stack
for (c = 1; c <= 3; c++) {
    Stack.setChannel(c);
    run("Enhance Contrast", "saturated=0.35 stack");
}



// 3. Prompt user to draw polygon
waitForUser("Draw a polygon ROI, then click 'OK' to continue.");

// 4. Crop
run("Crop");

// 5. Clear outside
setBackgroundColor(0, 0, 0);
run("Clear Outside");

// 6. Select none
run("Select None");

// 7. Save the modified image in same directory
saveDir = File.getDirectory(openPath);
fileName = File.getNameWithoutExtension(openPath);
newName = replace(fileName, "_COMPOSITE", "_ACx");
saveAs("Tiff", saveDir + newName + ".tif");
