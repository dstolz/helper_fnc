classdef histologyLabeller < handle
    %histologyLabeller Browse and interact with Img image crops around points
    %   This class extracts fixed-size crops around specified points in an
    %   image and displays them in a tiled montage with click callbacks.
    properties
        Img                 % Full image matrix to crop from
        halfWidth           (1,1) double {mustBePositive,mustBeFinite} = 15 
        halfHeight          (1,1) double {mustBePositive,mustBeFinite} = 15 
        nUp                 (1,1) double {mustBePositive,mustBeInteger} = 36         % Number of crops per page
        XY                  (:,2) double {mustBeFinite,mustBePositive}
        subImageID          (:,1)
        subImages               % 3D array of image crops
    end

    properties (Access = private)
        FigHandle           % Figure handle
        TileLayout          % TiledLayout handle
        currentStartIdx     (1,1) double = 1
        ImageTextHandles    cell
        ImageHandles        cell
        contrastLim         (1,2) double = [0 1]
        orignalState
    end

    properties (Dependent)
        currentPage
        totalPages
    end

    methods
        function obj = histologyLabeller(Img, XY, options)
            arguments
                Img
                XY   (:,2) {mustBeFinite,mustBePositive}
                options.nUp = 36;
                options.halfWidth = 15;
                options.halfHeight = 15;
            end
            obj.Img = Img;
            obj.XY = XY;
            
            obj.nUp = options.nUp;
            obj.halfHeight = options.halfHeight;
            obj.halfWidth = options.halfWidth;


            obj.subImages = obj.computesubImages(Img,XY,obj.halfWidth,obj.halfHeight);
            obj.subImageID = zeros(size(obj.subImages,3),1);
        end



        function delete(obj)
            set(groot,'defaultAxesToolbarVisible', obj.orignalState)
        end

        function showMontage(obj)
            obj.orignalState = get(groot,'defaultAxesToolbarVisible');
            set(groot,'defaultAxesToolbarVisible', 'off')
            obj.FigHandle = use_fig('montage');
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

            if ~updateOnly
                delete(findobj(obj.FigHandle,'type','axes'));
                drawnow
                NR = ceil(sqrt(obj.nUp));
                NC = ceil(obj.nUp / NR);
                obj.TileLayout = tiledlayout(obj.FigHandle, NR, NC);
                obj.TileLayout.Padding = 'tight';
                obj.TileLayout.TileSpacing = 'none';
                obj.ImageTextHandles = cell(obj.nUp, 1);
                obj.ImageHandles = cell(obj.nUp, 1);

                for j = 1:(stopIdx - startIdx + 1)
                    idx = startIdx + j - 1;
                    nexttile(j);
                    hImg = imagesc(obj.subImages(:,:,idx), obj.contrastLim);
                    hImg.UserData = idx;
                    hImg.ButtonDownFcn = @(s,e) obj.clickCallback(s,e);
                    axis image off;
                    labelStr = sprintf('%d [%d]', idx, obj.subImageID(idx));
                    obj.ImageTextHandles{j} = text(1,3, labelStr, 'FontSize',12, ...
                                                   'FontWeight','bold', 'Color','k');
                    obj.ImageHandles{j} = hImg;
                end
                colorcet('L19');
                title(obj.TileLayout, sprintf('%d to %d of %d', startIdx, stopIdx, total));
            else
                for j = 1:(stopIdx - startIdx + 1)
                    idx = startIdx + j - 1;
                    if isgraphics(obj.ImageHandles{j})
                        obj.ImageHandles{j}.CData = obj.subImages(:,:,idx);
                        obj.ImageHandles{j}.CDataMapping = 'scaled';
                        clim(obj.ImageHandles{j}.Parent,obj.contrastLim);
                    end
                    if isgraphics(obj.ImageTextHandles{j})
                        obj.ImageTextHandles{j}.String = sprintf('%d [%d]', idx, obj.subImageID(idx));
                    end
                end
                
            end
        end

        function keyPressCallback(obj, evt)
            total = size(obj.subImages,3);
            switch evt.Character
                case {']',char(13)}
                    if obj.currentStartIdx + obj.nUp <= total
                        fprintf('Navigate to page %d of %d, starting at index %d\n', obj.currentPage+1, obj.totalPages, obj.currentStartIdx + obj.nUp);
                        obj.currentStartIdx = obj.currentStartIdx + obj.nUp;
                        obj.renderMontage();
                    end
                case '['
                    if obj.currentStartIdx - obj.nUp >= 1
                        obj.currentStartIdx = obj.currentStartIdx - obj.nUp;
                        obj.renderMontage();
                        fprintf('Navigated to previous page starting at index %d\n', obj.currentStartIdx);
                    end
                case {'+','='}
                    obj.contrastLim = obj.contrastLim - [0 0.05];
                    fprintf('Increased contrast to [%0.2f %0.2f]\n', obj.contrastLim);
                    obj.renderMontage(true);
                case {'-','_'}
                    obj.contrastLim = obj.contrastLim + [0 0.05];
                    fprintf('Decreased contrast to [%0.2f %0.2f]\n', obj.contrastLim);
                    obj.renderMontage(true);
                case 'r'
                    obj.contrastLim = [0 1];
                    fprintf('Reset images\n');
                    obj.renderMontage(true);
                case 't'
                    ids = unique(obj.subImageID);
                    fprintf('Label counts:\n');
                    for i = 1:numel(ids)
                        fprintf('ID %d: %d\n', ids(i), sum(obj.subImageID == ids(i)));
                    end
            end
        end

        function p = get.totalPages(obj)
            n = length(obj.subImages);
            p = ceil(n ./ obj.nUp);
        end

        function p = get.currentPage(obj)
            p = ceil(obj.currentStartIdx ./ obj.nUp);
        end
    end

    methods (Access = private)
        function clickCallback(obj, src, ~)
            idx = src.UserData;
            selType = obj.FigHandle.SelectionType;
            key = get(obj.FigHandle, 'CurrentCharacter');
            if strcmp(selType, 'alt')
                obj.subImageID(idx) = 0;
            elseif strcmp(selType, 'normal')
                if ismember(key, '0':'9')
                    obj.subImageID(idx) = str2double(key);
                else
                    obj.subImageID(idx) = 1;
                end
            end
            startIdx = obj.currentStartIdx;
            relIdx = idx - startIdx + 1;
            if relIdx >= 1 && relIdx <= obj.nUp && relIdx <= numel(obj.ImageTextHandles)
                if isgraphics(obj.ImageTextHandles{relIdx})
                    obj.ImageTextHandles{relIdx}.String = sprintf('%d [%d]', idx, obj.subImageID(idx));
                end
            end
            fprintf('Crop %d clicked. ID set to %d\n', idx, obj.subImageID(idx));
        end
    end

    methods (Static)
        function subImages = computesubImages(Img,XY,halfWidth,halfHeight)
            if nargin < 3
                halfWidth = 15;
                halfHeight = 15;
            end

            nPoints = size(XY,1);
            x = XY(:,1);
            y = XY(:,2);
            rects = [x-halfWidth, y-halfHeight, ...
                repmat(halfWidth*2, nPoints,1), ...
                repmat(halfHeight*2, nPoints,1)];
            rects = num2cell(rects,2);
            crops = cellfun(@(r) imcrop(Img, r), rects, 'uni', 0);
            crops = cellfun(@(r) r ./ max(r(:)), crops, 'uni', 0);
            subImages = cat(3, crops{:});
        end
    end
end
