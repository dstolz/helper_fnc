classdef InteractiveRotator < handle
    % InteractiveRotator  Encapsulates interactive rotation and flipping of an image
    %   Usage:
    %     rot = InteractiveRotator(image);
    %     rot.TargetAxis = ax;  % optional: axis handle
    %     rot.start();
    %     finalImg = rot.accept();

    properties
        Image              % Original image matrix
        ModifiedImage      % Transformed image
        Angle = 0          % Current rotation angle (deg)
        Flipped = false(1,2)  % [vertical horizontal] flip flags
        FigureHandle       % Handle to the figure window
        TargetAxis         % Handle to axes for plotting; if empty, uses current axes

        % Control increments
        DefaultStep = 1    % default rotation increment (deg)
        CoarseStep = 5     % coarse rotation increment (deg)
        FineStep = 0.1     % fine rotation increment (deg)
        BigStep = 90       % large rotation jump (deg)

        % Key mappings
        HKey = 'h'         % horizontal flip
        VKey = 'v'         % vertical flip
        ResetKey = 'r'     % reset transforms
        LeftKey = 'leftarrow'
        RightKey = 'rightarrow'
        UpKey = 'uparrow'
        DownKey = 'downarrow'
        AcceptKey = 'return'

        % Display settings
        InterpMethod = 'bilinear'  % interpolation for imrotate
        ShowAxes = false           % show axes ticks
        ShowGrid = true            % overlay grid lines
        GridLines = 5              % number of grid lines
        GridStyle = ':w'           % grid line style
        Colormap = 'L8'            % display colormap
        Clim = []                  % contrast limits [min max]
    end

    methods
        function obj = InteractiveRotator(image)
            % Constructor: store image and initialize
            obj.Image = image;
            obj.ModifiedImage = image;
            obj.TargetAxis = [];
        end

        function start(obj)
            % Initialize interactive loop; open a figure only if TargetAxis is not set
            if isempty(obj.TargetAxis) || ~isvalid(obj.TargetAxis)
                obj.FigureHandle = figure('Name','Interactive Rotator', ...
                    'KeyPressFcn',@(src,evt)obj.keyPressCallback(src,evt));
            else
                % Use existing figure containing TargetAxis
                obj.FigureHandle = ancestor(obj.TargetAxis, 'figure');
                set(obj.FigureHandle, 'KeyPressFcn', @(src,evt)obj.keyPressCallback(src,evt));
            end
            obj.applyTransform();
            uiwait(obj.FigureHandle);
        end

        function keyPressCallback(obj, src, evt)
            % Handle key presses to adjust angle or flips
            mods = evt.Modifier;
            if ismember('shift',mods)
                step = obj.CoarseStep;
            elseif ismember('control',mods)
                step = obj.FineStep;
            else
                step = obj.DefaultStep;
            end
            k = lower(evt.Key);
            switch k
                case obj.HKey,     obj.Flipped(2) = ~obj.Flipped(2);
                case obj.VKey,     obj.Flipped(1) = ~obj.Flipped(1);
                case obj.ResetKey
                    obj.Angle = 0;
                    obj.Flipped = false(1,2);
                case obj.LeftKey,  obj.Angle = obj.Angle - step;
                case obj.RightKey, obj.Angle = obj.Angle + step;
                case obj.UpKey,    obj.Angle = obj.Angle + obj.BigStep;
                case obj.DownKey,  obj.Angle = obj.Angle - obj.BigStep;
                case obj.AcceptKey
                    uiresume(src);
                    return;
                otherwise
                    return;
            end
            obj.Angle = mod(obj.Angle,360);
            obj.applyTransform();
        end

        function img = applyTransform(obj)
            % Rotate, flip, and display on target or current axis
            img = imrotate(obj.Image, obj.Angle, obj.InterpMethod);
            if obj.Flipped(1), img = flip(img,1); end
            if obj.Flipped(2), img = flip(img,2); end
            obj.ModifiedImage = img;

            % Determine axis
            if isempty(obj.TargetAxis) || ~isvalid(obj.TargetAxis)
                ax = gca;
            else
                ax = obj.TargetAxis;
            end
            % Plot
            imagesc(ax, img);
            axis(ax, 'image');
            if ~obj.ShowAxes
                ax.XTick = []; ax.YTick = [];
            end
            if obj.ShowGrid
                hold(ax,'on');
                [h,w,~] = size(img);
                yL = linspace(1,h,obj.GridLines);
                xL = linspace(1,w,obj.GridLines);
                yline(ax,yL,obj.GridStyle);
                xline(ax,xL,obj.GridStyle);
                hold(ax,'off');
            end
            colormap(ax, colorcet(obj.Colormap));
            % Note: caxis removed per request
            if ~isempty(obj.Clim)
                clim(ax, obj.Clim);
            else
                clim(ax, [min(img(:)),0.2*max(img(:))]);
            end
            title(ax, sprintf('Rotation: %.1f°  •  Flip V=%d, H=%d', obj.Angle, obj.Flipped(1), obj.Flipped(2)), 'FontWeight','bold');
            % Subtitle with keyboard bindings
            subtitle(ax, sprintf('←/→: ±%.1f° (Shift: ±%.1f°, Ctrl: ±%.3f°) • ↑/↓: ±%.1f°\nH: flip horiz • V: flip vert • R: reset • Enter: accept', ...
                obj.DefaultStep, obj.CoarseStep, obj.FineStep, obj.BigStep));
        end

        function img = accept(obj)
            % Resume UI and return the final image
            uiresume(obj.FigureHandle);
            close(obj.FigureHandle);
            img = obj.ModifiedImage;
        end
    end
end
