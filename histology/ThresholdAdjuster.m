classdef ThresholdAdjuster < handle
    % ThresholdAdjuster  Interactive threshold adjustment via keyboard
    %   Arrow keys adjust threshold; Enter to finish. Overlays region boundaries

    properties
        OriginalImage       % Original input image (grayscale or RGB)
        ImageNorm           % Normalized image (0–1)
        Threshold = 0       % Normalized threshold (0–1)
        Fig                 % Figure handle
        Ax                  % Axes handle
        ImgHandle           % Handle for displayed image
        BoundHandles        % Handles for region boundary plots
    end

    properties(Dependent)
        ThresholdOriginal   % Threshold in original image scale
    end

    methods
        function obj = ThresholdAdjuster(I, ax, startThreshold)
            % obj = ThresholdAdjuster(I)
            % obj = ThresholdAdjuster(I, ax)
            % obj = ThresholdAdjuster(I, ax, startThreshold)

            obj.OriginalImage = I;
            % Prepare grayscale for normalization
            if ndims(I)==3
                Igray = rgb2gray(I);
            else
                Igray = I;
            end
            Igray = im2double(Igray);
            obj.ImageNorm = (Igray - min(Igray(:))) / (max(Igray(:)) - min(Igray(:)));

            if nargin == 3 && ~isempty(startThreshold)
                obj.Threshold = startThreshold;
            else
                % Default threshold via Otsu
                obj.Threshold = graythresh(obj.ImageNorm);
            end

            % Setup axes and figure
            if nargin>1 && isa(ax,'matlab.graphics.axis.Axes')
                obj.Ax = ax;
                obj.Fig = ancestor(obj.Ax, 'figure');
                set(obj.Fig, 'KeyPressFcn', @obj.onKeyPress);
            else
                obj.Fig = figure('Name','Threshold Adjuster', ...
                                 'NumberTitle','off', ...
                                 'KeyPressFcn',@obj.onKeyPress);
                obj.Ax = axes('Parent',obj.Fig);
            end

            % Initialize display
            obj.updateDisplay();
            uiwait(obj.Fig);
        end

        function val = get.ThresholdOriginal(obj)
            orig = obj.OriginalImage;
            if ndims(orig)==3
                origGray = rgb2gray(orig);
            else
                origGray = orig;
            end
            mn = double(min(origGray(:)));
            mx = double(max(origGray(:)));
            val = mn + obj.Threshold * (mx - mn);
        end

        function onKeyPress(obj,~,evt)
            switch evt.Key
                case {'uparrow','rightarrow'}
                    dt = 0.01;
                case {'downarrow','leftarrow'}
                    dt = -0.01;
                case 'return'
                    uiresume(obj.Fig);
                    return;
                otherwise
                    return;
            end
            if ismember('shift',evt.Modifier)
                dt = dt * 10;
            elseif ismember('control',evt.Modifier)
                dt = dt * 0.1;
            end
            obj.Threshold = min(max(obj.Threshold + dt, 0), 1);
            obj.updateDisplay();
        end

        function updateDisplay(obj)
            % Clear axes
            cla(obj.Ax);
            % Show original image
            if ndims(obj.OriginalImage)==3
                imshow(obj.OriginalImage, 'Parent', obj.Ax);
            else
                imagesc(obj.OriginalImage, 'Parent', obj.Ax);
            end

            colorcet('L8');
            clim([min(obj.OriginalImage(:)), 0.2*max(obj.OriginalImage(:))]);
            axis(obj.Ax, 'image', 'off');
            hold(obj.Ax, 'on');
            % Compute mask and boundaries
            mask = obj.ImageNorm > obj.Threshold;
            B = bwboundaries(mask);
            % Plot boundaries
            obj.BoundHandles = gobjects(numel(B), 1);
            for k = 1:numel(B)
                boundary = B{k};
                obj.BoundHandles(k) = plot(obj.Ax, boundary(:,2), boundary(:,1), 'w-', 'LineWidth', 1);
            end
            hold(obj.Ax, 'off');
            title(obj.Ax, sprintf('Norm Thr: %.3f | Orig Thr: %.2f', obj.Threshold, obj.ThresholdOriginal));
        end
    end
end