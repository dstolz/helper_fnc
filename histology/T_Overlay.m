%%

% ffnFG = "G:/Shared drives/CarasLab/SCIENTIFIC RESOURCES- PAPERS, TEXTBOOKS, ETC/Gerbil Atlas/Radke-Schuller et al 2016 - Outlines/AllOutlines_lowres/GerbilAtlas_Plate_30.tif";
ffnFG = "G:/Shared drives/CarasLab/SCIENTIFIC RESOURCES- PAPERS, TEXTBOOKS, ETC/Gerbil Atlas/Radke-Schuller et al 2016 - Outlines/AxialPlates_beta/Axial_Plate_14_-4.55mm.tif";

% ffnBG = "G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-978/SUBJ-ID-978_2B_R/SUBJ-ID-978_2B_R_DAPI_Z1_250609_dapi.png";
ffnBG = "G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-978/SUBJ-ID-978_2B_R/SUBJ-ID-978_2B_R_WFA-PV_Z3_250609_proj.tif";

use_fig('outlineOverlay');

ax = gca;
interactive_affine_overlay(ffnFG,ffnBG,ax = ax)



%%
t = Tiff(ffnFG);
imFG = t.read;
t.close;