classdef InteractiveAffineOverlay < handle
    % InteractiveAffineOverlay  Interactive affine overlay tool
    %
    % USAGE:
    %   overlay = InteractiveAffineOverlay(ffnFG, ffnBG, Name, Value, ...);
    %
    % DESCRIPTION:
    %   Provides an interactive GUI to overlay an RGB(A) foreground image
    %   over a background image. Supports translation, rotation, scaling,
    %   horizontal/vertical flips, and contrast adjustments in real time.
    %   Keyboard shortcuts (with CTRL/SHIFT modifiers) adjust parameters,
    %   and the '?' key displays command usage. Methods allow saving
    %   transforms, composites, or the overlay object.

    properties
        % Filepaths
        ffnFG char            % Foreground image filepath
        ffnBG char            % Background image filepath

        % Parsed constructor options
        opts struct           % Name-Value options struct
        showInfo logical      % Toggle text overlay with parameters

        % Transformation flags and display limits
        flipH logical         % Horizontal flip flag
        flipV logical         % Vertical flip flag
        climVal double        % Contrast limits for background display

        % Images and spatial reference
        imgBg                 % Background image array
        fgRGB                 % Foreground RGB channels
        alphaRaw              % Foreground alpha channel mask
        Rbg                   % imref2d reference for background

        % Graphics handles
        hFig matlab.ui.Figure                         % Figure handle
        ax matlab.graphics.axis.Axes                  % Axes handle
        hOverlay matlab.graphics.primitive.Image      % Overlay image handle
        hText matlab.graphics.primitive.Text          % Text handle for info
    end

    properties (Dependent)
        scale      % Scaling factor
        thetaDeg   % Rotation angle (degrees)
        tx         % Translation in X (pixels)
        ty         % Translation in Y (pixels)
    end

    properties (Access=private)
        % Backing properties for dependent values
        pScale double
        pThetaDeg double
        pTx double
        pTy double
    end

    methods
        function obj = InteractiveAffineOverlay(ffnFG, ffnBG, varargin)
            % Constructor: setup images, transforms, and UI
            %
            % PARAMETERS:
            %   ffnFG (char): path to foreground image (RGB or RGBA)
            %   ffnBG (char): path to background image
            %   Name-Value pairs:
            %     'transBaseStep', 'rotBaseStep', 'scaleBaseStep',
            %     'ctrlTransFactor', 'ctrlRotFactor', 'ctrlScaleFactor',
            %     'shiftTransFactor', 'shiftRotFactor', 'shiftScalePower',
            %     'scale', 'thetaDeg', 'tx', 'ty', 'clim', 'ax', 'showInfo'
            %
            % EXAMPLE:
            %   overlay = InteractiveAffineOverlay('fg.png','bg.jpg', ...
            %               'scale',2,'thetaDeg',30);

            % Parse inputs
            p = inputParser;
            addRequired(p,'ffnFG',@(x) exist(x,'file')==2);
            addRequired(p,'ffnBG',@(x) exist(x,'file')==2);
            addParameter(p,'transBaseStep',50);
            addParameter(p,'rotBaseStep',5);
            addParameter(p,'scaleBaseStep',1.2);
            addParameter(p,'ctrlTransFactor',10/50);
            addParameter(p,'ctrlRotFactor',1/5);
            addParameter(p,'ctrlScaleFactor',1.025);
            addParameter(p,'shiftTransFactor',5);
            addParameter(p,'shiftRotFactor',2);
            addParameter(p,'shiftScalePower',1.5);
            addParameter(p,'scale',3.0);
            addParameter(p,'thetaDeg',0);
            addParameter(p,'tx',0);
            addParameter(p,'ty',0);
            addParameter(p,'clim',[0 100]);
            addParameter(p,'ax',[]);
            addParameter(p,'showInfo',true);
            parse(p,ffnFG,ffnBG,varargin{:});

            % Initialize properties
            obj.ffnFG = ffnFG;
            obj.ffnBG = ffnBG;
            obj.opts = p.Results;
            obj.showInfo = obj.opts.showInfo;
            obj.flipH = false;
            obj.flipV = false;
            obj.climVal = obj.opts.clim;

            % Read images
            obj.imgBg = imread(obj.ffnBG);
            imgFG = imread(obj.ffnFG);
            if size(imgFG,3)==4
                obj.fgRGB = imgFG(:,:,1:3);
                obj.alphaRaw = double(imgFG(:,:,4))/255;
            else
                obj.fgRGB = imgFG;
                obj.alphaRaw = 1 - double(all(obj.fgRGB==0,3));
            end

            % Set initial transforms
            obj.pScale = obj.opts.scale;
            obj.pThetaDeg = obj.opts.thetaDeg;
            obj.pTx = obj.opts.tx;
            obj.pTy = obj.opts.ty;
            obj.Rbg = imref2d(size(obj.imgBg(:,:,1)));

            % Build UI and overlay
            obj.setupUI();
            obj.updateOverlay();
        end

        %% Dependent property accessors
        function val = get.scale(obj)
            % GET.scale Returns current scale factor
            val = obj.pScale;
        end
        function set.scale(obj,val)
            % SET.scale Assign scale, validate, then update overlay
            validateattributes(val,{'numeric'},{'scalar','positive'});
            obj.pScale = val;
            obj.updateOverlay();
        end

        function val = get.thetaDeg(obj)
            % GET.thetaDeg Returns current rotation in degrees
            val = obj.pThetaDeg;
        end
        function set.thetaDeg(obj,val)
            % SET.thetaDeg Assign rotation angle (deg), validate, update
            validateattributes(val,{'numeric'},{'scalar'});
            obj.pThetaDeg = val;
            obj.updateOverlay();
        end

        function val = get.tx(obj)
            % GET.tx Returns current X translation (px)
            val = obj.pTx;
        end
        function set.tx(obj,val)
            % SET.tx Assign X translation, validate, update
            validateattributes(val,{'numeric'},{'scalar'});
            obj.pTx = val;
            obj.updateOverlay();
        end

        function val = get.ty(obj)
            % GET.ty Returns current Y translation (px)
            val = obj.pTy;
        end
        function set.ty(obj,val)
            % SET.ty Assign Y translation, validate, update
            validateattributes(val,{'numeric'},{'scalar'});
            obj.pTy = val;
            obj.updateOverlay();
        end

        %% UI Setup
        function setupUI(obj)
            % SETUPUI Create figure/axes or use provided axes,
            % register KeyPress callback, and initialize display.
            if ~isempty(obj.opts.ax) && isvalid(obj.opts.ax)
                obj.ax = obj.opts.ax;
                obj.hFig = ancestor(obj.ax,'figure');
                set(obj.hFig,'KeyPressFcn',@(~,evt)obj.keyPressCallback(evt));
                cla(obj.ax);
            else
                obj.hFig = figure('Name','Affine Overlay','NumberTitle','off', ...
                    'KeyPressFcn',@(~,evt)obj.keyPressCallback(evt));
                obj.ax = axes('Parent',obj.hFig);
            end
            % Show background
            imshow(obj.imgBg,[], 'Parent',obj.ax);
            colormap(obj.ax,'bone');
            clim(obj.ax,obj.climVal);
            hold(obj.ax,'on');
            % Annotate filenames
            [~,bgName] = fileparts(obj.ffnBG);
            [~,fgName] = fileparts(obj.ffnFG);
            title(obj.ax,sprintf('BG: %s   FG: %s',bgName,fgName),'Interpreter','none');
            % Place overlay image
            obj.hOverlay = imshow(obj.fgRGB,'Parent',obj.ax);
            set(obj.hOverlay,'AlphaData',obj.alphaRaw);
                        % Prepare text handle for transform info at bottom-right
            obj.hText = text(obj.ax,0.98,0.02,'', ...  % normalized coords near bottom-right
                             'Units','normalized', ...
                             'HorizontalAlignment','right', ...
                             'VerticalAlignment','bottom', ...
                             'Color','yellow','FontSize',12, ...
                             'Interpreter','none');
            hold(obj.ax,'off');
        end

        %% Keyboard interaction
        function keyPressCallback(obj,event)
            % KEYPRESSCALLBACK Process key events for transformations
            %   arrow, comma/period, +/-, h, v, i, [, ], r, t, w, o, ?
            o = obj.opts;
            isCtrl  = any(strcmp(event.Modifier,'control'));
            isShift = any(strcmp(event.Modifier,'shift'));
            % Determine step sizes
            ts = o.transBaseStep * (isCtrl*o.ctrlTransFactor + ~isCtrl);
            if isShift, ts = ts * o.shiftTransFactor; end
            rs = o.rotBaseStep * (isCtrl*o.ctrlRotFactor + ~isCtrl);
            if isShift, rs = rs * o.shiftRotFactor; end
            ss = (isCtrl*o.ctrlScaleFactor + ~isCtrl*o.scaleBaseStep);
            if isShift, ss = ss ^ o.shiftScalePower; end
            cs = 10*(~isCtrl) + 2*isCtrl;
            if isShift, cs = cs * 2; end
            switch event.Key
                case 'leftarrow',  obj.tx = obj.tx - ts;
                case 'rightarrow', obj.tx = obj.tx + ts;
                case 'uparrow',    obj.ty = obj.ty - ts;
                case 'downarrow',  obj.ty = obj.ty + ts;
                case 'comma',      obj.thetaDeg = obj.thetaDeg - rs;
                case 'period',     obj.thetaDeg = obj.thetaDeg + rs;
                case {'add','equal'},       obj.scale = obj.scale * ss;
                case {'subtract','hyphen'}, obj.scale = obj.scale / ss;
                case 'h'
                    obj.flipH = ~obj.flipH;
                case 'v'
                    obj.flipV = ~obj.flipV;
                case 'i'
                    obj.showInfo = ~obj.showInfo;
                case 'leftbracket'
                    obj.climVal(2) = obj.climVal(2) - cs;
                    clim(obj.ax,obj.climVal);
                    return;
                case 'rightbracket'
                    obj.climVal(2) = obj.climVal(2) + cs;
                    clim(obj.ax,obj.climVal);
                    return;
                case 'r'
                    % Reset to initial parameters
                    obj.pScale    = o.scale;
                    obj.pThetaDeg = o.thetaDeg;
                    obj.pTx       = o.tx;
                    obj.pTy       = o.ty;
                    obj.flipH     = false;
                    obj.flipV     = false;
                    obj.climVal   = o.clim;
                    clim(obj.ax,obj.climVal);
                case 't'
                    obj.saveTransform(); return;
                case 'w'
                    obj.saveComposite(); return;
                case 'o'
                    obj.saveObject(); return;
                case {'slash','?'}
                    obj.displayHelp(); return;
                otherwise
                    return;
            end
            obj.updateOverlay();
        end

        %% Display help in console
        function displayHelp(obj)
            % DISPLAYHELP Print available key commands to the MATLAB console
            fprintf('\n=== InteractiveAffineOverlay Commands ===\n');
            fprintf('  Arrow Keys    : Translate overlay \n');
            fprintf('  , / .         : Rotate CCW / CW \n');
            fprintf('  + / =         : Scale up \n');
            fprintf('  - / _         : Scale down \n');
            fprintf('  h             : Toggle horizontal flip \n');
            fprintf('  v             : Toggle vertical flip \n');
            fprintf('  [ / ]         : Decrease / Increase contrast limit \n');
            fprintf('  i             : Toggle information display \n');
            fprintf('  r             : Reset all transforms \n');
            fprintf('  t             : Save transform parameters \n');
            fprintf('  w             : Save current composite image \n');
            fprintf('  o             : Save overlay object to .mat \n');
            fprintf('  ?             : Show this help message \n\n');
        end

        %% Update overlay rendering
        function updateOverlay(obj)
            % UPDATEOVERLAY Recompute and render transformed overlay
            fg    = obj.fgRGB;
            alpha = obj.alphaRaw;
            % Apply flips
            if obj.flipH, fg = fliplr(fg); alpha = fliplr(alpha); end
            if obj.flipV, fg = flipud(fg); alpha = flipud(alpha); end
            % Compute affine transform around image center
            cx = size(fg,2)/2; cy = size(fg,1)/2;
            theta = deg2rad(obj.thetaDeg);
            sc = obj.scale;
            Tneg   = [1 0 0; 0 1 0; -cx -cy 1];
            RS     = [sc*cos(theta) sc*sin(theta) 0; -sc*sin(theta) sc*cos(theta) 0; 0 0 1];
            Tpos   = [1 0 0; 0 1 0; cx cy 1];
            Ttrans = [1 0 0; 0 1 0; obj.tx obj.ty 1];
            A = Tneg * RS * Tpos * Ttrans;
            tform = affine2d(A);
            % Warp foreground and alpha into background frame
            [wRGB,Rw] = imwarp(fg,tform,'OutputView',obj.Rbg);
            wAlpha    = imwarp(alpha,tform,'OutputView',obj.Rbg);
            % Update graphic objects
            set(obj.hOverlay,'CData',wRGB, ...
                             'AlphaData',wAlpha, ...
                             'XData',Rw.XWorldLimits, ...
                             'YData',Rw.YWorldLimits);
            % Update text display if enabled
            if obj.showInfo
                infoStr = sprintf('TX: %.1f TY: %.1f  Scale: %.2f  Rot: %.1f°', ...
                                  obj.tx,obj.ty,obj.scale,obj.thetaDeg);
                set(obj.hText,'String',infoStr,'Visible','on');
            else
                set(obj.hText,'Visible','off');
            end
            drawnow;
        end

        %% Saving utilities
        function saveTransform(obj)
            % SAVETRANSFORM Prompt user and save transform parameters
            tf = struct('tx',obj.tx,'ty',obj.ty, ...
                        'scale',obj.scale,'thetaDeg',obj.thetaDeg, ...
                        'flipH',obj.flipH,'flipV',obj.flipV);
            [file,path] = uiputfile('transform.mat','Save Transform');
            if isequal(file,0), return; end
            save(fullfile(path,file),'tf');
            disp(['Transform saved to ' fullfile(path,file)]);
        end

        function saveComposite(obj)
            % SAVECOMPOSITE Prompt user and save composite image
            frame = getframe(obj.ax);
            [file,path] = uiputfile({'*.png';'*.jpg'},'Save Composite');
            if isequal(file,0), return; end
            imwrite(frame.cdata,fullfile(path,file));
            disp(['Composite saved to ' fullfile(path,file)]);
        end

        function saveObject(obj)
            % SAVEOBJECT Prompt user and save overlay object to .mat
            [file,path] = uiputfile('*.mat','Save Overlay Object');
            if isequal(file,0), return; end
            save(fullfile(path,file),'obj');
            disp(['Object saved to ' fullfile(path,file)]);
        end
    end
end
