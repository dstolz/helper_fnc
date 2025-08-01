%% Show histology section hemispheres


searchString = "*_proj.tif";

imagePth = "C:/Users/dstolz/My Drive/PROJECTS/GM6001/HISTOLOGY/";

ffnSections = "C:/Users/dstolz/My Drive/PROJECTS/GM6001/HISTOLOGY/Trackers - Sections.csv";


P = readtable(ffnSections,NumHeaderLines=1,TextType="string");

d = dir(fullfile(imagePth,'**',searchString));

pth = string({d.folder})';
fn = string({d.name})';
ffnImages = string(arrayfun(@fullfile,pth,fn,'uni',0))';

subjects = unique(P.SubjectID);

si = cellfun(@(a) startsWith(fn,a),subjects,'uni',0);
e = ~cellfun(@any,si);
subjects(e) = [];
si(e) = [];


P = P(ismember(P.SubjectID,subjects),:);
P = P(P.SliceID ~= "SLIDE",:);

uSliceID = unique(P.SliceID);

P = sortrows(P,"Hemisphere");

for i = 1:length(subjects)

    use_fig('hemispheres');
    tl = tiledlayout(length(uSliceID),2);
    tl.Padding = "tight";
    tl.TileSpacing = "tight";

    for j = 1:length(uSliceID)
        Pij = P(P.SubjectID==subjects(i) & P.SliceID == uSliceID(j),:);

        sd = "SUBJ-ID-" + Pij.ProcessingID + "_" + Pij.Slide_ + Pij.SliceID + "_" + Pij.Hemisphere;
        ffnTif = fullfile(imagePth,subjects(i),sd,Pij.ImageFilename+"_proj.tif");
        
        e = isfile(ffnTif);

        imgL = []; imgR = [];
        
        try imgL = parseBfTiff(ffnTif(1)); end
        try imgR = parseBfTiff(ffnTif(2)); end

        if isempty(imgL), imgL = zeros(size(imgR),"like",imgR); end
        if isempty(imgR), imgR = zeros(size(imgL),"like",imgL); end

        [mL,nL,pL] = size(imgL);
        [mR,nR,pR] = size(imgR);

        if mR > mL, imgL = [imgL; zeros(mR - mL,nL,pL,"like",imgL)]; end
        if mL > mR, imgR = [imgR; zeros(mL - mR,nR,pR,"like",imgR)]; end

        A = [imgR(:,:,1) imgL(:,:,1)];
        B = [imgR(:,:,2) imgL(:,:,2)];

        A = rescale(double(A));
        B = rescale(double(B));
        
        A = imadjust(A,stretchlim(A,[0.001 0.999]));
        B = imadjust(B,stretchlim(B,[0.001 0.999]));
        
        nexttile
        imagesc(A);
        axis image
        colormap(gca,colorcet('L7'))
        xline(size(imgR,2),'-w');
        
        ylabelf('Plate %d',Pij.AtlasPlate_(1))

        nexttile
        imagesc(B);
        axis image
        colormap(gca,colorcet('L5'))
        xline(size(imgR,2),'-w');
        
    end    

    sgtitle(tl,subjects(i));
    set(tl.Children,XTick=[],YTick=[]);

    drawnow

    ffnOut = fullfile(imagePth,subjects(i)+"_LR.png");
    fprintf('Writing: %s ...',ffnOut)
    print(ffnOut,"-dpng","-r600");
    fprintf(' done\n')
end

