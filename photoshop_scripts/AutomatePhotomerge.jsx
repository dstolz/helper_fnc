#target photoshop
app.displayDialogs = DialogModes.NO; // Suppress all dialogs

// Function to perform Photomerge on images in a given folder
function performPhotomerge(folder) {
    var fileList = folder.getFiles(/\.(jpg|jpeg|tif|tiff|bmp)$/i);
    if (fileList.length < 2) {
		alert("Skipping folder (not enough images): " + folder.fullName);
        return; // Skip folders with less than two images
    }
    
	var filesPSD = folder.getFiles(/\.(psd)$/i);
	if (filesPSD.length > 0) {
		return;
	}
		
	// Must be defined before including Photomerge.jsx
	var runphotomergeFromScript = true;

	var photomergeScript = new File(app.path + "/Presets/Scripts/Photomerge.jsx");
	if (photomergeScript.exists) {
		$.evalFile(photomergeScript);
	} else {
		alert("Photomerge.jsx not found.");
		return;
	}

	var photomergeOptions;
	photomergeOptions = {
		quality: 3, // 0 (Draft), 1 (Default), 2 (High), 3 (Maximum)
		alignment: "Reposition", // translation = Reposition
		blendImages: true,
		lensCorrection: false,
		automaticCrop: true,
		automaticLayout: true,
		removeVignette: true,
		correctGeometricDistortion: false
	};

    // Run Photomerge
    try {
		//alert("Starting Photomerge")
        //app.photomerge(fileList, photomergeOptions);
		photomerge.createPanorama(fileList, false); 

		// flatten the document
		//app.activeDocument.flatten();
				
		// Create the result names
		var resultNamePSD = folder.name + "_STITCHED.psd";
		var resultNamePNG = folder.name + "_STITCHED.png";

		// Create file paths for PSD and PNG
		var resultPathPSD = new File(folder + "/" + resultNamePSD);
		var resultPathPNG = new File(folder + "/" + resultNamePNG);

		// Save a copy as PNG
		var pngSaveOptions = new PNGSaveOptions();
		app.activeDocument.saveAs(resultPathPNG, pngSaveOptions, true, Extension.LOWERCASE);

		// Save as PSD
		app.activeDocument.saveAs(resultPathPSD, new PhotoshopSaveOptions(), true, Extension.LOWERCASE);
        app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);
    } catch (e) {
        alert("Photomerge failed in folder: " + folder.fullName + "\nError: " + e.message);
    }
}

// Function to recursively process all subfolders
function processAllSubfolders(parentFolder) {
    var folders = parentFolder.getFiles(function(file) {
        return file instanceof Folder;
    });

    for (var i = 0; i < folders.length; i++) {
		
		performPhotomerge(folders[i]);
		processAllSubfolders(folders[i]); // Recursive call
    }
}

// Function to check if a file with _STITCHED.psd exists in the folder
function hasStitchedFile(folder) {
    // Get all files in the folder
    var files = folder.getFiles(/\.(psd)$/i);
    // Loop through the files
	var r = files.length === 1
	
    return r;
}

// Main execution
var parentFolder = Folder.selectDialog("Select the parent folder containing subfolders for Photomerge");
if (parentFolder) {
    processAllSubfolders(parentFolder);
    alert("Batch Photomerge process completed.");
} else {
    alert("No folder selected. Operation cancelled.");
}


