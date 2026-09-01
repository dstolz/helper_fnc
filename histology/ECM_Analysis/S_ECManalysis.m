%%

startup

addpath('C:\src\histology_browser\')
% addpath('C:\src\histology_browser\.claude\worktrees\published-tracker')
addpath_nogit('c:\src\bfmatlab')

HistologyImageBrowser;


%% Save exported histology data
save("histology_ACxProfiles_260901.mat","histology")

%% Reload histology data and combine with ECM Projects csv
load("histology_ACxProfiles_260901.mat")




projectFile = "D:/GM6001_HISTOLOGY/ECM Projects - GM6001.csv";


S.Project = readtable(projectFile,"TextType","string");




% attach project info (drug/vehicle assigned per hemisphere)

% "Left"/"Right" in the project sheet -> "L"/"R" used in the image filenames
hemiCode = @(s) regexprep(strtrim(string(s)), "^(L|R).*$", "$1", "ignorecase");

P = S.Project(S.Project.SubjectID ~= "" & ~ismissing(S.Project.SubjectID), :);
projVars = ["SubjectID", "Condition", "Sex", "InfusionQuality", "GM6001Molarity_uM_"];

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










%%

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



%% inspect results
% A.grid puts every section on one depth axis -- one column per section -- so
% sections measured over different lengths can be averaged without resampling
% them here, which is what the old sample-by-sample assembly assumed.


plotType = "mean";
% plotType = "individual";


depthLimit = 1500; % microns from cortical surface

inDepth = A.grid.depth >= 0 & A.grid.depth <= depthLimit;

depth = A.grid.depth(inDepth);
Y = A.grid.raw(inDepth, :);   % A.grid.smoothed for the smoothed traces
F = A.grid.files;             % one row per section, in the column order of Y

% Project columns are missing for any section the tracker did not match.
label = @(s) fillmissing(string(s), "constant", "n/a");

rois = unique(F.ROILabel);
plates = unique(F.AtlasPlate);
subjects = unique(F.SubjectID);
treatments = unique(F.Treatment);

cm = lines(numel(subjects));

clf
t = tiledlayout('flow');

for r = 1:numel(rois)
    for i = 1:numel(plates)
        ax = nexttile;
        hold(ax, 'on')

        for k = 1:numel(subjects)

            for h = 1:numel(treatments)
                sel = find(F.ROILabel == rois(r) ...
                    & F.AtlasPlate == plates(i) ...
                    & F.SubjectID == subjects(k) ...
                    & F.Treatment == treatments(h));

                if isempty(sel), continue; end

                switch plotType
                    case "individual"
                        for j = 1:numel(sel)
                            c = sel(j);

                            line(ax, depth, Y(:, c), ...
                                Color = cm(k, :), ...
                                DisplayName = sprintf('%s-%s-%s', ...
                                F.SubjectID(c), F.SectionID(c), F.Treatment(c)))
                        end

                    case "mean"
                        c = sel(1);

                        y_mean = mean(Y(:, sel), 2, "omitnan");
                        y_std = std(Y(:, sel), 0, 2, "omitnan");

                        % patch(ax, [depth; flipud(depth)], [y_mean+y_std; flipud(y_mean-y_std)], ...
                        %     cm(k,:), EdgeColor = 'none', FaceAlpha = 0.3, HandleVisibility = 'off')

                        lh = line(ax, depth, y_mean, ...
                            LineWidth = 2, ...
                            Color = cm(k, :), ...
                            DisplayName = sprintf('%s - %s %s (%s, n=%d)', ...
                            F.SubjectID(c), F.Treatment(c), F.Hemisphere(c), ...
                            label(F.InfusionQuality(c)), numel(sel)));

                        if ismember(F.Treatment(c), ["GM6001", "Control R"])
                            lh.LineStyle = '--';
                        end
                end
            end % h: treatment
        end % k: subject

        if isempty(ax.Children)
            continue
        end

        if plotType == "individual"
            xline(ax, 0, HandleVisibility = "off")
            xregion(ax, [0 depthLimit], ...
                FaceColor = [0.9 0.9 0.9], ...
                HandleVisibility = "off")
        end

        titlef(ax, '%s -- AtlasPlate %d', rois(r), plates(i))
        legend(ax)
        grid(ax, 'on')
        box(ax, 'on')
        axis(ax, 'tight')
    end % i: AtlasPlate
end % r: ROI

linkaxes(findobj(t, 'Type', 'axes'))   % the layout also holds each tile's legend

ylabel(t, 'raw fluorescence')
xlabel(t, 'depth from cortical surface (\mum)')
title(t, 'ECM expression in ACx')
subtitle(t, 'Untrained Controls: SUBJ-ID-1127 & 1161')


%%