%%

ffnFG = "G:/Shared drives/CarasLab/SCIENTIFIC RESOURCES- PAPERS, TEXTBOOKS, ETC/Gerbil Atlas/Radke-Schuller et al 2016 - Outlines/AllOutlines_lowres/GerbilAtlas_Plate_30.tif";
% ffnFG = "G:/Shared drives/CarasLab/SCIENTIFIC RESOURCES- PAPERS, TEXTBOOKS, ETC/Gerbil Atlas/Radke-Schuller et al 2016 - Outlines/AxialPlates_beta/Axial_Plate_14_-4.55mm.tif";
% ffnFG = "G:/Shared drives/CarasLab/SCIENTIFIC RESOURCES- PAPERS, TEXTBOOKS, ETC/Gerbil Atlas/Radke-Schuller et al 2016 - Outlines/AxialPlates_beta/Axial_Plate_12_-3.85mm.tif";

ffnBG = "G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-994/SUBJ-ID-994cFos25dilutions250617S2_1SLIDE_LR_DAPI_Z1_250701_1.png";
% ffnBG = "a.png";

ia = InteractiveAffineOverlay(ffnFG, ffnBG);
ia.scale = 1;
ia.thetaDeg = 90;
ia.displayKeys
