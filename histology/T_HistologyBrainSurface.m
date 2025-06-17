% ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-952/SUBJ-ID-952_2C_R/SUBJ-ID-952_2C_R_WFA-PV_Z3_250609_proj.tif';
% ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-952/SUBJ-ID-952_2B_R/SUBJ-ID-952_2B_R_WFA-PV_Z3_250609_proj.tif';
% ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-957/SUBJ-ID-957_2B_R/SUBJ-ID-957_2B_R_WFA-PV_Z3_250609_proj.tif';
% ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-976/SUBJ-ID-976_2B_R/SUBJ-ID-976_2B_R_WFA-PV_Z3_250609_proj.tif';

% ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-940/SUBJ-ID-940_1A_R/SUBJ-ID-940_1A_R_WFA-PV_Z3_250613_proj.tif';
ffn = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-940/SUBJ-ID-940_1B_R/SUBJ-ID-940_1B_R_WFA-PV_Z3_250613_proj.tif';


[M,Mg,R] = extract_ECM_profiles(ffn,[-1000 200],90,100,2,0:-20:-600);

