%% ECM ANALYSIS
% root = 'G:/Shared drives/CarasLab/IMAGES/';
root = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-957';

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
        profileLocations=0:-5:-600, ...
        numSegments = 100, ...
        polyOrder = 5);

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
    save(ffnOut,"M","Mg","R",'-v6');
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

root = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-952';


d = dir(fullfile(root,'**\*_R_*ECManalysis.mat'));

ffn = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
ffn = string(ffn)';

ffn(2) = [];

disp(ffn)

data = arrayfun(@load,ffn,'uni',0);
data = cell2mat(data);

%%
M = [];
z = 0;

use_fig;
tiledlayout('flow');
for i = 1:length(data)
    % M(:,:,i) = data(i).M;
    d = data(i);
    [~,fn] = fileparts(d.R.params.tiffFile);

    nexttile;
    imagesc(d.R.M.x,d.R.M.y,d.M);
    axis image
    set(gca,'ydir','normal')
    xline(0,'-w')
    titlef(fn)
    subtitlef('z = %.3f mm',z)
    z = z - 0.35;

end