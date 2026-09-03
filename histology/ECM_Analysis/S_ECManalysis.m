%%

startup

addpath('C:\src\histology_browser\')
% addpath('C:\src\histology_browser\.claude\worktrees\published-tracker')
addpath_nogit('c:\src\bfmatlab')


%%
HistologyImageBrowser;


%% Save exported histology data
save("histology_ACxProfiles_260901.mat","histology")

%% Reload histology data and combine with ECM Projects csv
load("histology_ACxProfiles_260901.mat")




projectFile = "D:/GM6001_HISTOLOGY/ECM Projects - GM6001.csv";


P = readtable(projectFile,"TextType","string");




% attach project info (drug/vehicle assigned per hemisphere)

% "Left"/"Right" in the project sheet -> "L"/"R" used in the image filenames
hemiCode = @(s) regexprep(strtrim(string(s)), "^(L|R).*$", "$1", "ignorecase");

P = P(P.SubjectID ~= "" & ~ismissing(P.SubjectID), :);
projVars = ["SubjectID", "Condition", "LeftCannulaPlate", "RightCannulaPlate", "Sex", "InfusionQuality", "GM6001Molarity_uM_","IncludeInAnalysis"];

% reshape to one row per (subject, hemisphere) so the drug/vehicle columns
% land on the hemisphere they were actually infused into
Pveh = P(:,projVars);
Pveh.Hemisphere = hemiCode(P.VehicleInfusionHemisphere);
Pveh.Treatment  = repmat("Vehicle",height(P),1);
Pveh.Infusion1h = P.VehicleInfusion1H;
Pveh.Infusion3h = P.VehicleInfusion3H;

Pdrug = P(:,projVars);
Pdrug.Hemisphere = hemiCode(P.GM6001InfusionHemisphere);
Pdrug.Treatment  = repmat("GM6001",height(P),1);
Pdrug.Infusion1h = P.GM6001Infusion1H;
Pdrug.Infusion3h = P.GM6001Infusion3H;

% controls have no infused hemisphere; keep their subject-level info on both
isCtl = ~ismember(Pveh.Hemisphere,["L","R"]) & ~ismember(Pdrug.Hemisphere,["L","R"]);
Pctl = [Pveh(isCtl,:); Pdrug(isCtl,:)];
Pctl.Hemisphere = [repmat("L",sum(isCtl),1); repmat("R",sum(isCtl),1)];
Pctl.Treatment  = repmat("None",height(Pctl),1);

Plong = [Pveh; Pdrug; Pctl];
Plong(~ismember(Plong.Hemisphere,["L","R"]),:) = [];   % drop uninfused/NA rows

histology = outerjoin(histology, Plong, ...
    Keys = ["SubjectID","Hemisphere"], ...
    MergeKeys = true, ...
    Type = "left");

ind = histology.Treatment == "None";
histology.Treatment(ind) = "Control " + histology.Hemisphere(ind);

% cannula distance
d = nan(size(histology,1),1);
ind = histology.Hemisphere == "L";
d(ind) = histology.AtlasPlate(ind) - histology.LeftCannulaPlate(ind);
ind = histology.Hemisphere == "R";
d(ind) = histology.AtlasPlate(ind) - histology.RightCannulaPlate(ind);
histology.CannulaDist = d;


% prep data for analysis

voi = ["SubjectID", "AtlasPlate", "Treatment"];
% voi = ["SubjectID", "AtlasPlate", "Hemisphere"];


A = ecm_prepare_analysis_data(histology, ...
    fileVar = "ImagePath", ...
    groupVars = voi, ...
    smoothingMethod = "gaussian", ...
    smoothingWindow = 25, ...
    normalizeMode = "none");


launch_ecm_browser(A);



