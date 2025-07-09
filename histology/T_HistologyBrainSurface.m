%% ECM ANALYSIS
root = 'C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/IMAGES/SUBJ-ID-957';


d = dir(fullfile(root,'**\*WFA-PV_Z3*proj.tif')); fileSuffix = "_ECManalysis";
% d = dir(fullfile(root,'**\*dilution*proj.tif')); 


fileSuffix = "_analysis";



skipExisting = true;

addpath('C:/src/bfmatlab')

ffn = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
ffn = string(ffn)';


i = 1;
while i <= length(ffn)

    [pth,fn,ext] = fileparts(ffn(i));

    fprintf('%d of %d.\t%s ...',i,length(ffn),fn+ext)

    fnAnalysis = fn + fileSuffix + ".mat";
    fnAnalysisPng = fn + fileSuffix + ".png";

    if skipExisting && isfile(fullfile(pth,fnAnalysis))
        use_fig('histology');
        imshow(fullfile(pth,fnAnalysisPng));
        title('EXISTING IMAGE',Color = "r",FontWeight = "bold",FontSize = 20)
        r = input('Data already exists. Press any key to reanalyze or Enter to skip: ','s');
        if isempty(r)
            i = i + 1;
            continue
        end
    end



    M = straighten_cortex2(ffn(i), ...
        surfaceWindow = [-1000 1000], ...
        profileWidth = 1000, ...
        polyOrder = 4);
    % [M,R] = straighten_cortex(ffn(i), ...
    %     surfaceWindow = [-1000 1000], ...
    %     profileLocations = 0:-10:-600, ...
    %     numSegments = 100, ...
    %     refChannel = 1, ...
    %     dataChannel = 1, ...
    %     polyOrder = 4);


    tl = use_fig_tiledlayout;
    tl.Padding = "tight";
    tl.TileSpacing = "tight";
    for j = 1:size(M.data,3)
        nexttile
        imagesc(M.x,M.y,M.data(:,:,j));
        clim([0 0.5*max(M.data(:,:,j),[],"all")]);
        axis image
        set(gca,'ydir','normal')
    end
    colorcet('L8')
    drawnow


    r = input('Enter to accept or type any key to try again: ',"s");

    if ~isempty(r)
        fprintf(2,'Trying again!\n')
        continue
    end

    fprintf('\tsaving data ')

    ffnOut = fullfile(pth,fnAnalysis);
    save(ffnOut,"M","R",'-v6');
    fprintf('.')

    % takes too long to save figure because of all of the trapezoid patches
    % fnOut = fn + "_ECManalysis.fig";
    % savefig(fullfile(pth,fnOut));
    % fprintf('.')

    saveas(gcf,fullfile(pth,fnAnalysisPng));
    fprintf('.')

    fprintf(' done\n')

    i = i + 1;
end




%% 



ffnSectionsInfo = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/Trackers - Sections.csv";


root = 'G:/Shared drives/CarasLab/IMAGES/';

pthOut = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/Prelim_Analysis";


S = readtable(ffnSectionsInfo,TextType="string");


subjects = unique(S.SubjectID);

for k = 1:length(subjects)
    d = dir(fullfile(root,sprintf('**\\%s*ECManalysis.mat',subjects(k))));
    if isempty(d), continue; end


    ffn = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
    ffn = string(ffn)';

    % ffn(2) = [];

    disp(ffn)

    data = arrayfun(@load,ffn,'uni',0);
    data = cell2mat(data);

    % M = cat(3,data(:).M);

    use_fig;
    tl = tiledlayout('vertical');
    tl.Padding = "tight";
    tl.TileSpacing = "tight";
    for i = 1:length(data)
        D = data(i);
        [~,fn] = fileparts(D.R.params.tiffFile);

        sfn = fn(1:find(fn=='_',1,'last')-1);
        ind = contains(S.ImageFilename,sfn);

        % tok = string(split(fn,"_"));
        s = S(ind,:);

        Mg = imgaussfilt(D.M,[1 2]);

        nexttile;


        imagesc(D.R.M.x,D.R.M.y,Mg);
        % imagesc(d.R.M.x,d.R.M.y,M(:,:,i));

        axis image
        set(gca,'ydir','normal')
        xline(0,'-w')
        titlef("%s %d%c-%c Axial #%d",s.SubjectID,s.Slide_,s.SliceID,s.Hemisphere,s.AtlasPlate_);
    end
    title(tl,subjects(k));
    colorcet('L8')

    ax = findobj(gcf,'type','axes');
    set(ax,'clim',[0 10000])

    % set(gcf,'Name',tok(1))
    drawnow

    ffnOut = fullfile(pthOut,subjects(k) + "_All.png");
    saveas(gcf,ffnOut)

end