%%

histologyPath = "D:/GM6001_HISTOLOGY/";
metaDataFile = "D:/GM6001_HISTOLOGY/Trackers - Sections.csv";
projectFile = "D:/GM6001_HISTOLOGY/ECM Projects - GM6001.csv";

% histologyPath = "C:/Users/dstolz/My Drive/PROJECTS/GM6001/HISTOLOGY/";
% metaDataFile = "C:/Users/dstolz/My Drive/PROJECTS/GM6001/HISTOLOGY/Trackers - Sections.csv";


S = combine_values_csv(histologyPath, metadataCSV = metaDataFile);

ind = endsWith(S.combined.("Processing ID"),"IHC_ECM26A260727S1");
% ind = endsWith(S.combined.("Processing ID"),"IHC_ECM26A260519S2");

S.combined(~ind,:) = [];

S.Project = readtable(projectFile,"TextType","string");


%% attach project info (drug/vehicle assigned per hemisphere)

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

S.combined = outerjoin(S.combined, Plong, ...
    Keys = ["SubjectID","Hemisphere"], ...
    MergeKeys = true, ...
    Type = "left");

ind = S.combined.Treatment == "None";
S.combined.Treatment(ind) = "Control " + S.combined.Hemisphere(ind);

%% prep data for analysis

voi = ["SubjectID", "Atlas Plate #", "Treatment"];
% voi = ["SubjectID", "Atlas Plate #", "Hemisphere"];



plotType = "mean";
% plotType = "individual";



A = ecm_prepare_analysis_data(S, ...
    groupVars = voi, ...
    smoothingMethod = "gaussian", ...
    smoothingWindow = 25, ...
    normalizeMode = "none");


a = table2struct(A.aligned,ToScalar = true);

U = structfun(@unique,a,'uni',0);
U = orderfields(U);
N = structfun(@numel,U,'uni',0);

% inspect results

depthLimit = 1340; % microns from surface

clf
t = tiledlayout('flow');

cm = lines(N.SubjectID);

for r = 1:N.ROI
    for i = 1:N.AtlasPlate_
        nexttile

        for k = 1:N.SubjectID

            for h = 1:N.Treatment
                ind = a.AtlasPlate_ == U.AtlasPlate_(i) ...
                    & a.ROI == U.ROI(r) ...
                    & a.SubjectID == U.SubjectID(k) ...
                    & a.Treatment == U.Treatment(h);

                if ~any(ind), continue; end

                Asub = A.aligned(ind,:);

                fid = Asub.file_id;
                ufid = unique(fid);

                for j = 1:length(ufid)
                    indf = fid == ufid(j);

                    x = Asub.aligned_distance(indf);
                    y = Asub.intensity_raw(indf);
                    % y = Asub.intensity_smoothed(indf);

                    indx = x >= 0 & x <= depthLimit;

                    if j == 1
                        yM = nan(sum(indx),length(ufid));
                        xM = yM;
                    end
                    yM(:,j) = y(indx);
                    xM(:,j) = x(indx);

                    if plotType == "individual"
                        idx = find(indf,1);
                        dnstr = sprintf('%s-%s-%s',Asub.SubjectID(idx),Asub.SectionID(idx),Asub.Treatment(idx));

                        line(x,y, ...
                            Color = cm(k,:), ...
                            DisplayName = dnstr)
                    end
                end

                if plotType == "mean"
                    idx = find(indf,1);
                    dnstr = sprintf('%s - %s %c (%s)',Asub.SubjectID(idx),Asub.Treatment(idx),Asub.Hemisphere(idx),Asub.InfusionQuality(idx));


                    y_mean = mean(yM,2).';
                    y_std = std(yM,0,2).';
                    x_ = linspace(0,depthLimit,length(y_mean));

                    x_p = [x_ fliplr(x_)];
                    y_std_p = [y_mean+y_std fliplr(y_mean-y_std)];

                    % patch(x_p,y_std_p,[0 0 0], ...
                    %     EdgeColor = 'none', ...
                    %     FaceColor = cm(k,:), ...
                    %     FaceAlpha = 0.3, ...
                    %     HandleVisibility = 'off')

                    lh = line(x_,y_mean, ...
                        LineWidth = 2, ...
                        Color = cm(k,:), ...
                        DisplayName = dnstr);
                    if Asub.Treatment(idx) == "GM6001" || Asub.Treatment(idx) == "Control R"
                        lh.LineStyle = '--';
                    end

                end
            end % h: hemisphere

            if plotType == "individual"
                xline(0,HandleVisibility="off")
                xregion([0 depthLimit], ...
                    FaceColor = [0.9 0.9 0.9], ...
                    HandleVisibility="off")
            end

            titlef('%s -- Atlas Plate #%d',U.ROI(r),U.AtlasPlate_(i))
            legend
            grid on

            axis tight
            box on
        end % k: SubjectID
    end % i: AtlasPlate
end
linkaxes(t.Children)

ylabel(t,'raw fluorescence')
xlabel(t,'depth from cortical surface (\mum)')
title(t,'ECM expression in ACx')
subtitle(t,'Untrained Controls: SUBJ-ID-1127 & 1161')