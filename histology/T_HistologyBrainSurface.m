%% ECM ANALYSIS
% root = 'G:/Shared drives/CarasLab/IMAGES/';
root = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-952';


d = dir(fullfile(root,'**\*WFA-PV_Z3*proj.tif'));

ffn = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
ffn = string(ffn)';


% ffn = "G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-957/SUBJ-ID-957_1C_R/SUBJ-ID-957_1C_R_WFA-PV_Z3_250613_2_proj.tif";
% ffn = "G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-958/SUBJ-ID-958_2A_R/SUBJ-ID-958_2A_R_WFA-PV_Z3_250612_proj.tif";
% ffn = "G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-954/SUBJ-ID-954_2A_R/SUBJ-ID-954_2A_R_WFA-PV_Z3_250611_proj.tif"

% for i = 1:length(ffn)
i = 1;
while i < length(ffn)
% for i = 9
    [pth,fn,ext] = fileparts(ffn(i));

    fprintf('%d of %d.\t%s ...',i,length(ffn),fn+ext)


    [M,R] = extract_ECM_profiles(ffn(i), ...
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



    r = input('Try Again?: ',"s");

    if ~isempty(r)
        fprintf(2,'Trying again!\n')
        continue
    end

    fprintf('\tsaving data ...')
    fnOut = fn + "_ECManalysis.mat";
    ffnOut = fullfile(pth,fnOut);

    save(ffnOut,"M","Mg","R");


    fnOut = fn + "_ECManalysis.fig";
    savefig(fullfile(pth,fnOut));

    fnOut = fn + "_ECManalysis.png";
    saveas(gcf,fullfile(pth,fnOut));

    fprintf(' done\n')

    i = i + 1;
end




%% 

root = 'G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-957';


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