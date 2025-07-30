classdef histologyLabeller < handle
    %histologyLabeller Browse and interact with ImgA/ImgB image crops
    %   Allows switching between two image sets ('q' for ImgA, 'w' for ImgB)

    properties
        ImgA                % First image
        ImgB                % Second image
        halfWidth           (1,1) double {mustBePositive,mustBeFinite} = 15
        halfHeight          (1,1) double {mustBePositive,mustBeFinite} = 15
        nUp                 (1,1) double {mustBePositive,mustBeInteger} = 36
        XY                  (:,2) double {mustBeFinite,mustBePositive} = []
        subimageLabel       (:,1)

        cmapA               (1,:) char = 'L19'
        cmapB               (1,:) char = 'L16'
        useGaussianFilter   (1,1) logical = false
        useMedianFilter     (1,1) logical = false
        contrastLim         (1,2) double {mustBeNonnegative,mustBeFinite} = [0 1]
        limTol              (1,2) double {mustBeInRange(limTol,0,1)} = [0 1]
        gamma               (1,1) double {mustBeFinite,mustBePositive} = 1

        % showImgCorr         (1,1) logical = false

        activeID            (1,1) double {mustBeInteger,mustBeInRange(activeID,0,9)} = 0
    end

    properties (Access = private)
        FigHandle
        TileLayout
        currentIdx          (1,1) double = 1
        currentStartIdx     (1,1) double = 1
        ImageTextHandles    cell
        ImageHandles        cell
        orignalState
        currentImageSet     (1,1) double {mustBeMember(currentImageSet,[1 2])} = 1 % 1 = A, 2 = B
        subImagesA
        subImagesB

    end

    properties (Dependent)
        currentPage
        totalPages
        subImages
    end

    methods
        function obj = histologyLabeller(ImgA, XY, options)
            arguments
                ImgA
                XY (:,2) {mustBeFinite,mustBePositive} = []
                options.ImgB = []
                options.nUp = 36
                options.halfWidth = 15
                options.halfHeight = 15
                options.cmapA = 'L19'
                options.cmapB = 'L16'
            end

            obj.ImgA = ImgA;
            obj.ImgB = options.ImgB;
            obj.nUp = options.nUp;
            obj.halfHeight = options.halfHeight;
            obj.halfWidth = options.halfWidth;
            obj.cmapA = options.cmapA;
            obj.cmapB = options.cmapB;

            if ndims(ImgA) == 3 && isempty(XY)
                nSlices = size(ImgA, 3);
                obj.subImagesA = ImgA;
                obj.XY = [ones(nSlices,1), ones(nSlices,1)]; % Dummy XY for consistency
            else
                obj.XY = XY;
                obj.subImagesA = obj.computesubImages(ImgA, XY, obj.halfWidth, obj.halfHeight);
            end

            if ~isempty(obj.ImgB)
                if ndims(obj.ImgB) == 3 && isequal(size(obj.ImgB,3), size(obj.subImagesA,3))
                    obj.subImagesB = obj.ImgB;
                else
                    obj.subImagesB = obj.computesubImages(obj.ImgB, obj.XY, obj.halfWidth, obj.halfHeight);
                end
            end

            obj.subimageLabel = zeros(size(obj.subImagesA,3),1);
        end

        function delete(obj)
            set(groot,'defaultAxesToolbarVisible', obj.orignalState)
        end

        function showMontage(obj)
            obj.orignalState = get(groot,'defaultAxesToolbarVisible');
            set(groot,'defaultAxesToolbarVisible', 'off')
            obj.FigHandle = use_fig('histologyLabeller');
            set(obj.FigHandle, 'KeyPressFcn', @(src,evt)obj.keyPressCallback(evt));
            obj.renderMontage();
        end

        function renderMontage(obj, updateOnly)
            if nargin < 2
                updateOnly = false;
            end

            total = size(obj.subImages,3);
            startIdx = obj.currentStartIdx;
            stopIdx = min(startIdx + obj.nUp - 1, total);

            if ~updateOnly && isempty(obj.ImageHandles)
                delete(findobj(obj.FigHandle,'type','axes'));
                drawnow
                NR = ceil(sqrt(obj.nUp));
                NC = ceil(obj.nUp / NR);
                obj.TileLayout = tiledlayout(obj.FigHandle, NR, NC);
                obj.TileLayout.Padding = 'tight';
                obj.TileLayout.TileSpacing = 'none';
                obj.ImageTextHandles = cell(obj.nUp, 1);
                obj.ImageHandles = cell(obj.nUp, 1);

                v = 1:(stopIdx - startIdx + 1);
                fprintf('Rendering images ...\n')
                parfor_progress(length(v));
                for j = v
                    idx = startIdx + j - 1;
                    nexttile(j);
                    img = obj.applyFilter(obj.subImages(:,:,idx));
                    img = imadjust(img,stretchlim(img,obj.limTol),[],obj.gamma);
                    hImg = imagesc(img);
                    hImg.UserData = idx;
                    hImg.ButtonDownFcn = @(s,e) obj.clickCallback(s,e);
                    axis image off;
                    labelStr = sprintf('%d [%d]', idx, obj.subimageLabel(idx));
                    labelColor = obj.getLabelColor(obj.subimageLabel(idx));
                    obj.ImageTextHandles{j} = text(1,3, labelStr, 'FontSize',12, 'FontWeight','bold', 'Color', labelColor);
                    obj.ImageHandles{j} = hImg;
                    parfor_progress;
                end
                parfor_progress(0);
            end

            for j = 1:(stopIdx - startIdx + 1)
                idx = startIdx + j - 1;
                if isgraphics(obj.ImageHandles{j})
                    img = obj.applyFilter(obj.subImages(:,:,idx));
                    img = imadjust(img,stretchlim(img,obj.limTol),[],obj.gamma);
                    obj.ImageHandles{j}.CData = img;
                    % clim(obj.ImageHandles{j}.Parent,obj.contrastLim);
                end
                if isgraphics(obj.ImageTextHandles{j})
                    obj.ImageTextHandles{j}.String = sprintf('%d [%d]', idx, obj.subimageLabel(idx));
                    obj.ImageTextHandles{j}.Color = obj.getLabelColor(obj.subimageLabel(idx));
                end
            end

            if obj.currentImageSet == 1
                colorcet(obj.cmapA);
                title(obj.TileLayout, sprintf('Image A: %d to %d of %d', startIdx, stopIdx, total));
            else
                colorcet(obj.cmapB);
                title(obj.TileLayout, sprintf('Image B: %d to %d of %d', startIdx, stopIdx, total));
            end
        end

        function keyPressCallback(obj, evt)
            total = size(obj.subImages,3);
            C = evt.Character;
            MK = join(string(evt.Modifier),"_");
            switch C
                case cellstr(('0':'9')')'
                    obj.activeID = str2double(C);
                case char(13)
                    switch (MK)
                        case "shift"
                            if obj.currentStartIdx - obj.nUp >= 1
                                obj.currentStartIdx = obj.currentStartIdx - obj.nUp;
                            end

                        otherwise
                            if obj.currentStartIdx + obj.nUp <= total
                                obj.currentStartIdx = obj.currentStartIdx + obj.nUp;
                            end
                    end
                    obj.renderMontage();

                case {'+','='}
                    switch (MK)
                        case "shift"
                            x = obj.contrastLim - [0 0.05];
                            obj.contrastLim = [max(x(1),0) min(x(2),1)];
                        case "control"
                            obj.gamma = max(obj.gamma+0.05,0);
                        otherwise
                            x = obj.limTol + [0.01 -0.01];
                            obj.limTol = [max(x(1),0) min(x(2),1)];
                    end
                    obj.renderMontage(true);
                case {'-','_'}
                    switch (MK)
                        case "shift"
                            x = obj.contrastLim + [0 0.05];
                            obj.contrastLim = [max(x(1),0) min(x(2),1)];
                        case "control"
                            obj.gamma = max(obj.gamma-0.05,0);
                        otherwise
                            x = obj.limTol + [-0.01 0.01];
                            obj.limTol = [max(x(1),0) min(x(2),1)];
                    end
                    obj.renderMontage(true);
                case 'r'
                    obj.contrastLim = [0 1];
                    obj.limTol = [0 1];
                    obj.gamma = 1;
                    obj.renderMontage(true);
                case 'q'
                    obj.currentImageSet = 1;
                    obj.renderMontage(true);
                case 'w'
                    if ~isempty(obj.ImgB)
                        obj.currentImageSet = 2;
                        obj.renderMontage(true);
                    end
                case 't'
                    ids = unique(obj.subimageLabel);
                    for i = 1:numel(ids)
                        fprintf('ID %d: %d\n', ids(i), sum(obj.subimageLabel == ids(i)));
                    end
                case {'/','?'}
                    fprintf('Keyboard commands:\n');
                    fprintf(' Shift+Enter : Previous page\n');
                    fprintf(' Enter       : Next page\n');
                    fprintf(' q           : Show Image A\n');
                    fprintf(' w           : Show Image B (if available)\n');
                    fprintf(' + or =      : Increase display tolerance\n');
                    fprintf('   Shift     : Expand contrast limits\n');
                    fprintf('   Ctrl      : Increase gamma correction\n');
                    fprintf(' - or _      : Decrease display tolerance\n');
                    fprintf('   Shift     : Contract contrast limits\n');
                    fprintf('   Ctrl      : Decrease gamma correction\n');
                    fprintf(' r           : Reset contrast and gamma\n');
                    fprintf(' g           : Toggle Gaussian filter\n');
                    fprintf(' m           : Toggle Median filter\n');
                    fprintf(' t           : Print label summary\n');
                    fprintf(' 0-9         : Assign label at left mouse click\n');
                    fprintf(' Right click : Assign label ''0''\n')
                case 'g'
                    obj.useGaussianFilter = ~obj.useGaussianFilter;
                    obj.useMedianFilter = false;
                    obj.renderMontage(true);
                case 'm'
                    obj.useMedianFilter = ~obj.useMedianFilter;
                    obj.useGaussianFilter = false;
                    obj.renderMontage(true);
            end

            
        end

        function p = get.totalPages(obj)
            p = ceil(size(obj.subImages,3) / obj.nUp);
        end

        function p = get.currentPage(obj)
            p = ceil(obj.currentStartIdx / obj.nUp);
        end

        function subImgs = get.subImages(obj)
            if obj.currentImageSet == 1
                subImgs = obj.subImagesA;
            else
                subImgs = obj.subImagesB;
            end
        end
    end

    methods (Access = private)
        function imgOut = applyFilter(obj, imgIn)
            if obj.useGaussianFilter
                imgOut = imgaussfilt(imgIn, 1);
            elseif obj.useMedianFilter
                imgOut = medfilt2(imgIn, [3 3]);
            else
                imgOut = imgIn;
            end
        end

        function clickCallback(obj, src, evt)
            idx = src.UserData;
            idx = idx + obj.currentStartIdx - 1;
            switch evt.Button
                case 1
                    obj.subimageLabel(idx) = obj.activeID;
                case 3
                    obj.subimageLabel(idx) = 0;
            end


            obj.renderMontage(true);
            fprintf('subimage %d ID set to %d\n', idx, obj.subimageLabel(idx));
        end

        function color = getLabelColor(~, label)
            colors = lines(10);
            if label == 0
                color = [0 0 0];
            else
                color = colors(mod(label-1,size(colors,1))+1, :);
            end
        end
    end

    methods (Static)
        function subImages = computesubImages(Img,XY,halfWidth,halfHeight)
            nPoints = size(XY,1);
            x = XY(:,1);
            y = XY(:,2);
            rects = [x-halfWidth, y-halfHeight, repmat(halfWidth*2,nPoints,1), repmat(halfHeight*2,nPoints,1)];
            rects = num2cell(rects,2);
            crops = cellfun(@(r) imcrop(Img, r), rects, 'uni', 0);
            subImages = cat(3, crops{:});
        end
    end
end
