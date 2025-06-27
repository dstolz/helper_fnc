%% ECM ANALYSIS
% root = 'G:/Shared drives/CarasLab/IMAGES/';
root = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-974';



skipExisting = true;

addpath('C:/src/bfmatlab')

d = dir(fullfile(root,'**\*WFA-PV_Z3*proj.tif'));

ffn = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
ffn = string(ffn)';




i = 1;
while i <= length(ffn)

    [pth,fn,ext] = fileparts(ffn(i));

    fprintf('%d of %d.\t%s ...',i,length(ffn),fn+ext)

    fnAnalysis = fn + "_ECManalysis.mat";
    fnAnalysisPng = fn + "_ECManalysis.png";

    if skipExisting && isfile(fullfile(pth,fnAnalysis))
        use_fig('histology');
        imshow(fullfile(pth,fnAnalysisPng));
        title('EXISTING IMAGE')
        r = input('Data already exists. Press any key to reanalyze or Enter to skip: ','s');
        if isempty(r)
            i = i + 1;
            continue
        end
    end



    [M,R] = straighten_cortex(ffn(i), ...
        surfaceWindow = [-1000 750], ...
        profileLocations = 0:-10:-600, ...
        numSegments = 100, ...
        polyOrder = 3);

    Mg = imgaussfilt(M,[1 2]);


    nexttile
    imagesc(R.M.x,R.M.y,Mg);
    xline(0,'-w')
    set(gca,'ydir','normal');
    title('ECM');
    xlabel('rostrocaudal distance (\mum)');
    ylabel('lateromedial distance (\mum)');
    colorcet('L16');
    colorbar


    drawnow



    r = input('Use any key to try again or press Enter to save and continue: ',"s");

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