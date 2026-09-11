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
ind = histology.Condition == "Control";
d(ind) = histology.AtlasPlate(ind) - 30;
histology.CannulaDist = d;


% save
ffnOut = "D:/GM6001_HISTOLOGY/ECM Projects - GM6001 - full.mat";
save(ffnOut,"histology")






% export for R

ecm_export_for_r(ffnOut,"D:/GM6001_HISTOLOGY")







%% prep data for analysis

voi = ["SubjectID", "AtlasPlate", "Treatment"];
% voi = ["SubjectID", "AtlasPlate", "Hemisphere"];


A = ecm_prepare_analysis_data(histology, ...
    fileVar = "ImagePath", ...
    groupVars = voi, ...
    smoothingMethod = "gaussian", ...
    smoothingWindow = 25, ...
    normalizeMode = "none");


B = launch_ecm_browser(A);

%%
% The ECM Browser view of 2026-09-07 14:53, as commands.
% Everything not named here is what a browser opens on.
B.setComparison("difference", "Treatment", ...
    reference = "Vehicle", within = "AtlasPlate");
B.GroupDropDown.Value = "SubjectID";
B.setTiling("AtlasPlate");
B.setFilter("IncludeInAnalysis", "TRUE");
B.setFilter("Condition", "Trained");
B.setFilter("AtlasPlate", ["28" "29" "30" "31" "32"]);
B.DepthMinField.Value = 0;
B.DepthMaxField.Value = 2000;
B.SpacingDropDown.Value = "none";
B.TickLabelDropDown.Value = "left and bottom axes";
B.refresh();

% And what can then be done with it:
%   B.popOut()                                                      draws it into a figure of its own
%   B.savePlot("figure.pdf")                                        PNG, TIFF, JPEG, PDF, EPS, SVG, or .fig
%   B.saveData("profiles.csv", Layout = "long")                     one row per sample, every field beside it
%   d = B.viewData()                                                the numbers behind the plot
%   B.copySummary()                                                 the account of this view a caption needs
%   B.setGroupStyle("SubjectID", "SUBJ-ID-1174", Color = [0 0 0])   one group in a color of your own


%% GM6001 - Vehicle within sections
% The ECM Browser view of 2026-09-04 15:53, as commands.
% Everything not named here is what a browser opens on.
B.setComparison("difference", "Treatment", ...
    reference = "Vehicle", within = ["SubjectID" "AtlasPlate"]);
B.GroupDropDown.Value = "SubjectID";
B.setTiling("AtlasPlate");
B.setFilter("IncludeInAnalysis", "TRUE");
B.setFilter("Condition", "Trained");
B.DepthMinField.Value = 0;
B.DepthMaxField.Value = 1600;
B.refresh();

% And what can then be done with it:
%   B.popOut()                                                      draws it into a figure of its own
%   B.savePlot("figure.pdf")                                        PNG, TIFF, JPEG, PDF, EPS, SVG, or .fig
%   B.saveData("profiles.csv", Layout = "long")                     one row per sample, every field beside it
%   d = B.viewData()                                                the numbers behind the plot
%   B.copySummary()                                                 the account of this view a caption needs
%   B.setGroupStyle("SubjectID", "SUBJ-ID-1174", Color = [0 0 0])   one group in a color of your own

%% Compare Treated vs Controls by Atlas Plate
% The ECM Browser view of 2026-09-08 12:06, as commands.
% Everything not named here is what a browser opens on.
B.ShowDropDown.Value = "group mean";
B.GroupDropDown.Value = "Treatment";
B.setTiling(["AtlasPlate" "Condition"]);
B.setFilter("IncludeInAnalysis", "TRUE");
B.setFilter("AtlasPlate", ["28" "29" "30" "31" "32"]);
B.DepthMinField.Value = 0;
B.DepthMaxField.Value = 2000;
B.SpacingDropDown.Value = "none";
B.TickLabelDropDown.Value = "left and bottom axes";
B.refresh();

% And what can then be done with it:
%   B.popOut()                                                   draws it into a figure of its own
%   B.savePlot("figure.pdf")                                     PNG, TIFF, JPEG, PDF, EPS, SVG, or .fig
%   B.saveData("profiles.csv", Layout = "long")                  one row per sample, every field beside it
%   d = B.viewData()                                             the numbers behind the plot
%   B.copySummary()                                              the account of this view a caption needs
%   B.setGroupStyle("Treatment", "Control L", Color = [0 0 0])   one group in a color of your own