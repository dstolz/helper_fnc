%% ECM ANALYSIS
% root = 'C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES/';
root = 'C:/Users/dstolz/My Drive/PROJECTS/GM6001/HISTOLOGY';


d = dir(fullfile(root,'**\*PNN25A*WFA-PV_Z3*proj.tif')); 
% d = dir(fullfile(root,'**\*PNN25A*S2*WFA-PV_Z3*proj.tif')); 
% d = dir(fullfile(root,'**\*dilution*proj.tif')); 


fileSuffix = "_ECManalysis";

% surfaceWindow = [-2000 4000];
surfaceWindow = [-1000 1000];

% skipExisting = 0 : don't skip; 1 : skip w/ prompt; 2 : skip silently
skipExisting = 2; 



ffn = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
ffn = string(ffn)';


i = 1;
while i <= length(ffn)

    [pth,fn,ext] = fileparts(ffn(i));

    fprintf('%d of %d.\t%s ...',i,length(ffn),fn+ext)

    ffnAnalysis = fullfile(pth,fn + fileSuffix + ".mat");
    ffnAnalysisPng = fullfile(pth,fn + fileSuffix + ".png");

    if skipExisting > 0 && isfile(ffnAnalysis)
        if skipExisting == 1
            use_fig('histology');
            imshow(ffnAnalysisPng);
            title('EXISTING ANALYSIS',Color = "r",FontWeight = "bold",FontSize = 20)
            r = input('Data already exists. Press any key to reanalyze or Enter to skip: ','s');
        else
            r = [];
        end
        if isempty(r)
            i = i + 1;
            fprintf(' skipped\n')
            continue
        end
    end



    M = straighten_cortex2(ffn(i), ...
        surfaceWindow = [-2000 4000], ...
        profileWidth = 1000, ...
        polyOrder = 4);


    tl = use_fig_tiledlayout("result");
    tl.Padding = "loose";
    tl.TileSpacing = "tight";
    
    nexttile
    imagesc(M.x,M.y,M.data(:,:,1));
    xline(0,'-w')
    title('PV+')
    clim([0 0.5*max(M.data(:,:,1),[],"all")]);
    axis image
    set(gca,'ydir','normal')
    colormap(gca,colorcet('L8'))
    xlabel("distance from reference (\mum)")

    nexttile
    imagesc(M.x,M.y,M.data(:,:,2));
    xline(0,'-w')
    title('ECM')
    clim([0 0.5*max(M.data(:,:,2),[],"all")]);
    axis image
    set(gca,'ydir','normal')
    colormap(gca,colorcet('L14'))
    xlabel("distance from reference (\mum)")

    title(tl,fn,'interpreter','none')


    drawnow


    r = input('Enter to accept or type any key to try again: ',"s");

    if ~isempty(r)
        fprintf(2,'Trying again!\n')
        continue
    end

    fprintf('\tsaving data ')

    ffnOut = ffnAnalysis;
    save(ffnOut,"M",'-v6');
    fprintf('.')



    saveas(gcf,ffnAnalysisPng);
    fprintf('.')

    fprintf(' done\n')

    i = i + 1;

    if i > length(ffn), break; end
end




%% Group analysis

procID = "PNN25A";

ffnSectionsInfo = "C:/Users/dstolz/My Drive/PROJECTS/Trackers - Sections.csv";

% root = 'C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES';
root = 'C:/Users/dstolz/My Drive/PROJECTS/GM6001/HISTOLOGY';

% pthOut = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/Prelim_Analysis";
pthOut = "C:/Users/dstolz/My Drive/PROJECTS/GM6001/Prelim_Analysis";


if ~isfolder(pthOut), mkdir(pthOut); end

S = readtable(ffnSectionsInfo,TextType="string",NumHeaderLines=1);

S = S(contains(S.ProcessingID,procID),:);

subjects = unique(S.SubjectID);

for k = 1:length(subjects)
    d = dir(fullfile(root,sprintf('**\\%s*ECManalysis.mat',subjects(k))));
    if isempty(d), continue; end


    ffn = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
    ffn = string(ffn)';

    disp(ffn)

    data = arrayfun(@load,ffn,'uni',0);
    data = cell2mat(data);

    % M = cat(3,data(:).M);

    use_fig;
    tl = tiledlayout('flow');
    tl.TileIndexing = 'columnmajor';
    tl.Padding = "tight";
    tl.TileSpacing = "tight";
    for i = 1:length(data)
        M = data(i).M;
        [~,fn] = fileparts(ffn(i));

        ind = arrayfun(@(a) contains(fn,a),S.ImageFilename);

        s = S(ind,:);

        Mg = imgaussfilt(M.data,[1 2]);

        nexttile;

        imagesc(M.x,M.y,Mg(:,:,2));

        axis image
        set(gca,'ydir','normal')
        % xline(0,'-w')
        titlef("%s %d%c-%c Axial #%d",s.SubjectID,s.Slide_,s.SliceID,s.Hemisphere,s.AtlasPlate_);

    end
    title(tl,subjects(k));
    colorcet('L5')

    ax = findobj(gcf,'type','axes');
    set(ax,'clim',[0 40])

    linkaxes;


    % set(gcf,'Name',tok(1))
    drawnow

    pause;
    
    ffnOut = fullfile(pthOut,subjects(k) + "_ECM.png");
    saveas(gcf,ffnOut)

end



%% Summed by depth


subjectGroups = [ ...
    "SUBJ-ID-974"    "Baseline" "A"; ...
    "SUBJ-ID-975"    "Baseline"  "A"; ...
    "SUBJ-ID-976"    "NE14" "B"; ...
    "SUBJ-ID-977"    "NE14"  "B"; ...
    "SUBJ-ID-940"    "NE14"  "B"; ...
    "SUBJ-ID-978"    "Sham14" "C"; ...
    "SUBJ-ID-979"    "Sham14" "C"; ...
    "SUBJ-ID-952"    "NE35"  "D"; ...
    "SUBJ-ID-954"    "NE35"  "D"; ...
    "SUBJ-ID-957"    "Sham35" "E"; ...
    "SUBJ-ID-958"    "Sham35"  "E"];



depths = 0:-100:-600;

targetAtlasPlates = 9:14;

procID = "PNN25A";

ffnSectionsInfo = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES/Trackers - Sections.csv";


root = 'C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES';

pthOut = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/Prelim_Analysis";


S = readtable(ffnSectionsInfo,TextType="string",NumHeaderLines=1);

S = S(contains(S.ProcessingID,procID),:);



subjects = unique(S.SubjectID);

clear AP
for p = 1:length(targetAtlasPlates)
    fprintf('Atlas Plate %d\n',targetAtlasPlates(p))
    for k = 1:length(subjects)
        d = dir(fullfile(root,sprintf('**\\%s*ECManalysis.mat',subjects(k))));
        if isempty(d), continue; end

        AP(k,p).subjectID = subjects(k);
        AP(k,p).atlasPlate = targetAtlasPlates(p);

        AP(k,p).dataAvailable = false;

        ffn = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
        ffn = string(ffn)';

        for i = 1:length(ffn)
            [~,fn] = fileparts(ffn(i));

            ind = arrayfun(@(a) contains(fn,a),S.ImageFilename);
            ind = ind & S.AtlasPlate_ == targetAtlasPlates(p);

            if ~any(ind), continue; end

            AP(k,p).dataAvailable = true;
            AP(k,p).x = M.x;

            s = S(ind,:);


            disp(ffn(i))

            load(ffn(i));

            % Mg = imgaussfilt(M.data,[1 2]);

            for j = 1:length(depths)-1
                dind = M.y < depths(j) & M.y >= depths(j+1);
                AP(k,p).D(j,:) = sum(M.data(dind,:,2),1);
            end
        end
    end
end

%% Plot depth profiles
depthInd = depths == -200;

meanSubtract = true;

ug = unique(subjectGroups(:,2),'stable');

up = unique([AP.atlasPlate]);


use_fig('profiles');

tl = tiledlayout('flow');
tl.Padding = 'tight';
tl.TileSpacing = 'tight';

cm = colormap(lines(length(ug)));
for p = 1:length(up)
    nexttile
    
    hold on
    for g = 1:length(ug)
        ind = subjectGroups(:,2) == ug(g);

    
        im = ismember([AP(:,p).subjectID],subjectGroups(ind,1));
        % im = im & [AP(:,p).dataAvailable];
        
        % if ~any(im), continue; end

        ap = AP(im,p);

        
        for j = 1:length(ap)
            if ~ap(j).dataAvailable, continue; end
            y = ap(j).D(depthInd,:);
            y = smoothdata(y,"gaussian",200);
            if meanSubtract
                y = y - mean(y);
                % y = y - mean(y(1:100));
            end
            plot(ap(j).x,y, ...
                DisplayName=sprintf('%s [%s]',ug(g),extractAfter(ap(j).subjectID,8)), ...
                Color = cm(g,:), ...
                LineWidth = 2);
        end

    end
    xline(0,'-k',LineWidth = 2,HandleVisibility="off")
    yline(0,'-k',LineWidth = 2,HandleVisibility="off")
    hold off
    grid on
    legend(Location="northwest",Interpreter="none");
    titlef('Plate %d',up(p));
    
end

titlef(tl,"cortical depth = %.1f",depths(depthInd))


%% Show All Plates for All subjects
targetAtlasPlates = 9:14;

procID = "PNN25A";

ffnSectionsInfo = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES/Trackers - Sections.csv";


root = 'C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES';

pthOut = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/Prelim_Analysis";


S = readtable(ffnSectionsInfo,TextType="string",NumHeaderLines=1);

S = S(contains(S.ProcessingID,procID),:);

subjects = subjectGroups(:,1);
ug = unique(subjectGroups(:,2));


use_fig('subj_plates')

tl = tiledlayout(length(subjects), length(targetAtlasPlates));
tl.Padding = 'tight';
tl.TileSpacing = 'tight';

for sbj = 1:length(subjects)
    grp = subjectGroups(subjectGroups(:,1) == subjects(sbj),2);

    for ap = 1:length(targetAtlasPlates)
        ind = S.SubjectID == subjects(sbj) & ...
            S.AtlasPlate_ == targetAtlasPlates(ap);
        s = S(ind,:);

        nexttile

        if sum(ind) > 1
            s = s(s.Hemisphere=="L",:);
        end

        if ap == 1
            ylabel(sprintf('%s [%s]',grp,extractAfter(subjects(sbj),8)),Interpreter="none")
        end
        if sbj == 1
            titlef("Plate %d",targetAtlasPlates(ap))
        end
        xticks([]);
        yticks([]);
        box off
        if ~any(ind), continue; end
        
        fn = s.ImageFilename + "_proj_ECManalysis.mat";

        d = dir(fullfile(root,"**\"+fn));

        if isempty(d), continue; end

        ffn = fullfile(d.folder,d.name);

        load(ffn)

        y = M.data(:,:,2);

        % q = quantile(y(:),[0.01 0.99]);
        % y = min(max(y,q(1)),q(2));

        imagesc(M.x,M.y,y);

        xticks([]);
        yticks([]);
        box off

        if ap == 1
            ylabel(sprintf('%s [%s]',grp,extractAfter(subjects(sbj),8)),Interpreter="none")
        end
        if sbj == 1
            titlef("Plate %d",targetAtlasPlates(ap))
        end

        set(gca,'ydir','normal');

        xline(0,'-w');

        clim([0 80])
    end

end
linkaxes;
colorcet('L5')



%% PV-ECM correlation
targetAtlasPlates = 9:14;


windowSize = 21;         % odd integer window size

% Create averaging kernel
% kernel = ones(windowSize, windowSize, 'double') / (windowSize^2);
gsigma = windowSize/4;
kernel = fspecial('gaussian', windowSize, gsigma);
W      = sum(kernel(:));         % sum of all weights in the kernel

procID = "PNN25A";

ffnSectionsInfo = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES/Trackers - Sections.csv";


root = 'C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES';

pthOut = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/Prelim_Analysis";


S = readtable(ffnSectionsInfo,TextType="string",NumHeaderLines=1);

S = S(contains(S.ProcessingID,procID),:);

subjects = subjectGroups(:,1);
ug = unique(subjectGroups(:,2));


use_fig('subj_plates')

tl = tiledlayout(length(subjects), length(targetAtlasPlates));
tl.Padding = 'tight';
tl.TileSpacing = 'tight';

nw = windowSize^2;              % number of pixels in window

for sbj = 1:length(subjects)
    grp = subjectGroups(subjectGroups(:,1) == subjects(sbj),2);

    for ap = 1:length(targetAtlasPlates)
        ind = S.SubjectID == subjects(sbj) & ...
            S.AtlasPlate_ == targetAtlasPlates(ap);
        s = S(ind,:);

        nexttile

        if sum(ind) > 1
            s = s(s.Hemisphere=="L",:);
        end

        if ap == 1
            ylabel(sprintf('%s [%s]',grp,extractAfter(subjects(sbj),8)),Interpreter="none")
        end
        if sbj == 1
            titlef("Plate %d",targetAtlasPlates(ap))
        end
        xticks([]);
        yticks([]);
        box off
        if ~any(ind), continue; end
        
        fn = s.ImageFilename + "_proj_ECManalysis.mat";

        d = dir(fullfile(root,"**\"+fn));

        if isempty(d), continue; end

        ffn = fullfile(d.folder,d.name);

        load(ffn)

        A = M.data(:,:,1);
        B = M.data(:,:,2);

        sumA  = conv2(A,  kernel, 'same');
        sumB  = conv2(B,  kernel, 'same');
        sumAB = conv2(A.*B, kernel, 'same');
        sumA2 = conv2(A.^2, kernel, 'same');
        sumB2 = conv2(B.^2, kernel, 'same');

        %--- Compute Pearson correlation coefficient -------------------------------
        rn   = sumAB - (sumA.*sumB)/W;
        rd= sqrt((sumA2 - (sumA.^2)/W) .* (sumB2 - (sumB.^2)/W));

        rd(rd==0) = eps;  % avoid division by zero

        r = rn ./ rd;

        mc = max(r(:));

        r = imgaussfilt(r,3);
        r = r ./ max(r(:));
        r = r .* mc;

        imagesc(M.x,M.y,r);

        xticks([]);
        yticks([]);
        box off

        if ap == 1
            ylabel(sprintf('%s [%s]',grp,extractAfter(subjects(sbj),8)),Interpreter="none")
        end
        if sbj == 1
            titlef("Plate %d",targetAtlasPlates(ap))
        end

        set(gca,'ydir','normal');

        % clim([0 1])
    end

end
linkaxes;
colorcet('L18')


%% dist
%% Show All Plates for All subjects
targetAtlasPlates = 9:14;

procID = "PNN25A";

ffnSectionsInfo = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES/Trackers - Sections.csv";


root = 'C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES';

pthOut = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/Prelim_Analysis";


S = readtable(ffnSectionsInfo,TextType="string",NumHeaderLines=1);

S = S(contains(S.ProcessingID,procID),:);

subjects = subjectGroups(:,1);
ug = unique(subjectGroups(:,2));


use_fig('subj_plates')

tl = tiledlayout(length(subjects), length(targetAtlasPlates));
tl.Padding = 'tight';
tl.TileSpacing = 'tight';

for sbj = 1:length(subjects)
    grp = subjectGroups(subjectGroups(:,1) == subjects(sbj),2);

    for ap = 1:length(targetAtlasPlates)
        ind = S.SubjectID == subjects(sbj) & ...
            S.AtlasPlate_ == targetAtlasPlates(ap);
        s = S(ind,:);

        nexttile

        if sum(ind) > 1
            s = s(s.Hemisphere=="L",:);
        end

        if ap == 1
            ylabel(sprintf('%s [%s]',grp,extractAfter(subjects(sbj),8)),Interpreter="none")
        end
        if sbj == 1
            titlef("Plate %d",targetAtlasPlates(ap))
        end
        xticks([]);
        yticks([]);
        box off
        if ~any(ind), continue; end
        
        fn = s.ImageFilename + "_proj_ECManalysis.mat";

        d = dir(fullfile(root,"**\"+fn));

        if isempty(d), continue; end

        ffn = fullfile(d.folder,d.name);

        load(ffn)

        y = M.data(:,:,2);

        % q = quantile(y(:),[0.01 0.99]);
        % y = min(max(y,q(1)),q(2));

        imagesc(M.x,M.y,y);

        xticks([]);
        yticks([]);
        box off

        if ap == 1
            ylabel(sprintf('%s [%s]',grp,extractAfter(subjects(sbj),8)),Interpreter="none")
        end
        if sbj == 1
            titlef("Plate %d",targetAtlasPlates(ap))
        end

        set(gca,'ydir','normal');

        clim([0 80])
    end

end
linkaxes;
colorcet('L5')



