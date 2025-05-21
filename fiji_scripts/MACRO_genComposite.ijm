// Batch Process CZI Files with filename filter and save to COMPOSITE subfolder



dir = getDirectory("Choose parent directory");
count = 1;

// --- Recursive file collection ---
function listFilesRecursive(dir, targetString, suffix) {
    list = getFileList(dir);
    result = newArray();
    for (i = 0; i < list.length; i++) {
        path = dir + list[i];
        if (File.isDirectory(path)) {
            sublist = listFilesRecursive(path, targetString, suffix);
            result = Array.concat(result, sublist);
        } else if (endsWith(list[i], suffix)) {
            if (indexOf(list[i], targetString) != -1) {
                print((count++) + ". " + path);
                result = Array.concat(result, newArray(path));
            }
        }
    }
    return result;
}

// --- Get file list ---
fileList = listFilesRecursive(dir, "WFA-PV-DAPI", ".czi");


// --- Process each file ---
for (f=0; f<fileList.length; f++) {
   print((f+1) + ". Processing: " + fileList[f]);
       
fileDir = File.getParent(fileList[f]);
fileName = File.getName(fileList[f]);
dotIndex = indexOf(fileName, ".");
    


   run("Bio-Formats Importer", "open=[" + fileDir + File.separator + fileName + "] autoscale color_mode=Colorized rois_import=[ROI manager] split_channels view=Hyperstack stack_order=XYCZT series_1");

   origTitle = getTitle();

   titles = getList("image.titles");

   c0 = "";
   c1 = "";
   c2 = "";

   for (i=0; i<titles.length; i++) {
      if (indexOf(titles[i], "C=0") != -1) c0 = titles[i];
      if (indexOf(titles[i], "C=1") != -1) c1 = titles[i];
      if (indexOf(titles[i], "C=2") != -1) c2 = titles[i];
   }

   if (c0 == "" || c1 == "" || c2 == "") {
      exit("Error: Missing channel.\nFound:\nC0=" + c0 + "\nC1=" + c1 + "\nC2=" + c2);
   }

   run("Merge Channels...", "c1=[" + c0 + "] c2=[" + c1 + "] c3=[" + c2 + "] create");

   Stack.setChannel(1);
   run("Magenta");

   run("Enhance Contrast", "saturated=0.35");

   run("Z Project...", "projection=[Sum Slices]");


   composite    = fileDir + File.separator + substring(fileName, 0, dotIndex) + "_COMPOSITE.tif";
   compositeRGB = fileDir + File.separator + substring(fileName, 0, dotIndex) + "_COMPOSITE_RGB.tif";

   print("Writing: " + composite);
   saveAs("Tiff", composite);
   
   run("Stack to RGB");
   print("Writing: " + compositeRGB);
   saveAs("Tiff", compositeRGB);

   // Clean up images before next loop
   close("*");

}
