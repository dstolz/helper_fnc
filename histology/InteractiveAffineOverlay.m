classdef InteractiveAffineOverlay < handle
    % InteractiveAffineOverlay  Interactive affine overlay tool
    %
    % USAGE:
    %   overlay = InteractiveAffineOverlay(ffnFG, ffnBG, Name, Value, ...);
    %
    % DESCRIPTION:
    %   Provides an interactive GUI to overlay an RGB(A) foreground image
    %   over a background image. Supports translation, rotation, scaling,
    %   horizontal/vertical flips, contrast adjustments, and custom colormaps
    %   for the background. Keyboard shortcuts (with CTRL/SHIFT modifiers)
    %   adjust parameters. Press 'm' to choose a colormap from a popup GUI.

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

        % Colormap properties
        bgColormap char        % Background colormap name
        availableColormaps cell % List of available colormap names

        % Images and spatial reference
        imgBg                 % Background image array
        fgRGB                 % Foreground RGB channels
        alphaRaw              % Foreground alpha channel mask
        Rbg                   % imref2d reference for background

        % Graphics handles
        hFig matlab.ui.Figure
        ax matlab.graphics.axis.Axes
        hBg matlab.graphics.primitive.Image       % Background image handle
        hOverlay matlab.graphics.primitive.Image
        hText matlab.graphics.primitive.Text
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
            addParameter(p,'bgColormap','bone');
            addParameter(p,'showInfo',true);
            parse(p,ffnFG,ffnBG,varargin{:});

            obj.ffnFG = ffnFG;
            obj.ffnBG = ffnBG;
            obj.opts = p.Results;
            obj.showInfo = obj.opts.showInfo;
            obj.flipH = false;
            obj.flipV = false;
            obj.climVal = obj.opts.clim;

            obj.availableColormaps = { ...
                'parula','jet','hsv','hot','cool','spring','summer', ...
                'autumn','winter','gray','bone','copper','pink','lines'};
            obj.bgColormap = obj.opts.bgColormap;

            obj.imgBg = imread(obj.ffnBG);
            imgFG = imread(obj.ffnFG);
            if size(imgFG,3)==4
                obj.fgRGB = imgFG(:,:,1:3);
                obj.alphaRaw = double(imgFG(:,:,4))/255;
            else
                obj.fgRGB = imgFG;
                obj.alphaRaw = 1 - double(all(obj.fgRGB==0,3));
            end

            obj.pScale = obj.opts.scale;
            obj.pThetaDeg = obj.opts.thetaDeg;
            obj.pTx = obj.opts.tx;
            obj.pTy = obj.opts.ty;
            obj.Rbg = imref2d(size(obj.imgBg(:,:,1)));

            obj.setupUI();
            obj.updateOverlay();
        end

        %% Dependent property accessors
        function val = get.scale(obj),      val = obj.pScale; end
        function set.scale(obj,val), validateattributes(val,{'numeric'},{'scalar','positive'}); obj.pScale = val; obj.updateOverlay(); end
        function val = get.thetaDeg(obj),   val = obj.pThetaDeg; end
        function set.thetaDeg(obj,val), validateattributes(val,{'numeric'},{'scalar'}); obj.pThetaDeg = val; obj.updateOverlay(); end
        function val = get.tx(obj),         val = obj.pTx; end
        function set.tx(obj,val), validateattributes(val,{'numeric'},{'scalar'}); obj.pTx = val; obj.updateOverlay(); end
        function val = get.ty(obj),         val = obj.pTy; end
        function set.ty(obj,val), validateattributes(val,{'numeric'},{'scalar'}); obj.pTy = val; obj.updateOverlay(); end

        %% UI Setup
        function setupUI(obj)
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
            set(obj.hFig,'Renderer','opengl');

            obj.hBg = imshow(obj.imgBg, [], 'Parent', obj.ax);
            colormap(obj.ax, obj.bgColormap);
            clim(obj.ax, obj.climVal);
            hold(obj.ax,'on');

            [~,bgName] = fileparts(obj.ffnBG);
            [~,fgName] = fileparts(obj.ffnFG);
            title(obj.ax,sprintf('BG: %s   FG: %s',bgName,fgName),'Interpreter','none');

            obj.hOverlay = imshow(obj.fgRGB,'Parent',obj.ax);
            set(obj.hOverlay,'AlphaData',obj.alphaRaw);

            obj.hText = text(obj.ax,0.98,0.02,'', ...
                             'Units','normalized', ...
                             'HorizontalAlignment','right', ...
                             'VerticalAlignment','bottom', ...
                             'Color','yellow','FontSize',12, ...
                             'Interpreter','none');
            hold(obj.ax,'off');
        end

        %% Keyboard interaction
        function keyPressCallback(obj,event)
            o = obj.opts;
            isCtrl = any(strcmp(event.Modifier,'control'));
            isShift = any(strcmp(event.Modifier,'shift'));
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
                case 'h', obj.flipH = ~obj.flipH;
                case 'v', obj.flipV = ~obj.flipV;
                case 'i', obj.showInfo = ~obj.showInfo;
                case 'm', obj.selectColormap(); return;
                case 'leftbracket'
                    obj.climVal(2) = obj.climVal(2) - (10*(~isCtrl)+2*isCtrl)*(isShift+1);
                    clim(obj.ax,obj.climVal); return;
                case 'rightbracket'
                    obj.climVal(2) = obj.climVal(2) + (10*(~isCtrl)+2*isCtrl)*(isShift+1);
                    clim(obj.ax,obj.climVal); return;
                case 'r'
                    obj.pScale    = o.scale;
                    obj.pThetaDeg = o.thetaDeg;
                    obj.pTx       = o.tx;
                    obj.pTy       = o.ty;
                    obj.flipH     = false;
                    obj.flipV     = false;
                    obj.climVal   = o.clim;
                    colormap(obj.ax,obj.bgColormap);
                    clim(obj.ax,obj.climVal); return;
                case 't', obj.saveTransform(); return;
                case 'w', obj.saveComposite(); return;
                case 'o', obj.saveObject(); return;
                case {'slash','?'}, obj.displayKeys(); return;
                otherwise, return;
            end
            obj.updateOverlay();
        end

        %% Help text
        function txt = displayKeys(obj)
            txt = {'=== InteractiveAffineOverlay Commands ===', ...
                   'Arrow Keys    : Translate overlay', ...
                   ', / .         : Rotate CCW / CW', ...
                   '+ / =         : Scale up', ...
                   '- / _         : Scale down', ...
                   'h             : Toggle horizontal flip', ...
                   'v             : Toggle vertical flip', ...
                   '[ / ]         : Adjust contrast limit', ...
                   'i             : Toggle info display', ...
                   'r             : Reset transforms', ...
                   'm             : Select background colormap', ...
                   't             : Save transform params', ...
                   'w             : Save composite image', ...
                   'o             : Save overlay object', ...
                   '?             : Show this help'};
            if nargout==0, fprintf('%s\n',txt{:}); end
        end

        %% Rendering update
        function updateOverlay(obj)
            fg = obj.fgRGB; alpha = obj.alphaRaw;
            if obj.flipH, fg = fliplr(fg); alpha = fliplr(alpha); end
            if obj.flipV, fg = flipud(fg); alpha = flipud(alpha); end
            theta = deg2rad(obj.thetaDeg); sc = obj.scale;
            cx = size(fg,2)/2; cy = size(fg,1)/2;
            T = [1 0 0; 0 1 0; -cx -cy 1]* ...
                [sc*cos(theta) sc*sin(theta) 0; -sc*sin(theta) sc*cos(theta) 0; 0 0 1]* ...
                [1 0 0; 0 1 0; cx cy 1]* ...
                [1 0 0; 0 1 0; obj.tx obj.ty 1];
            tform = affine2d(T);
            [wRGB,Rw] = imwarp(fg,tform,'OutputView',obj.Rbg);
            wA = imwarp(alpha,tform,'OutputView',obj.Rbg);
            set(obj.hOverlay,'CData',wRGB,'AlphaData',wA, ...
                'XData',Rw.XWorldLimits,'YData',Rw.YWorldLimits);
            if obj.showInfo
                set(obj.hText,'String',sprintf('TX:%.1f TY:%.1f S:%.2f R:%.1f°', ...
                    obj.tx,obj.ty,obj.scale,obj.thetaDeg),'Visible','on');
            else
                set(obj.hText,'Visible','off');
            end
            drawnow limitrate;
        end

        %% Colormap GUI
        function selectColormap(obj)
            d = dialog('Name','Select Colormap','Position',[300 300 250 300]);
            uicontrol('Parent',d,'Style','listbox','String',obj.availableColormaps,...
                'Units','normalized','Position',[0.1 0.2 0.8 0.7],...
                'Value',find(strcmp(obj.availableColormaps,obj.bgColormap)),...
                'Callback',@(src,~) obj.applyColormap(src,d));
        end

        function applyColormap(obj,src,dlg)
            obj.bgColormap = obj.availableColormaps{src.Value};
            if ishandle(dlg), delete(dlg); end
            colormap(obj.ax,obj.bgColormap);
            clim(obj.ax,obj.climVal);
            set(obj.hBg,'CData',obj.imgBg);
            uistack(obj.hBg,'bottom');
            drawnow;
        end

        %% Saving utilities
        function saveTransform(obj)
            tf = struct('tx',obj.tx,'ty',obj.ty,'scale',obj.scale,...
                        'thetaDeg',obj.thetaDeg,'flipH',obj.flipH,...
                        'flipV',obj.flipV);
            [f,p] = uiputfile('transform.mat','Save Transform');
            if isequal(f,0), return; end
            save(fullfile(p,f),'tf'); disp(['Saved transform to ' fullfile(p,f)]);
        end

        function saveComposite(obj)
            frm = getframe(obj.ax);
            [f,p] = uiputfile({'*.png';'*.jpg'},'Save Composite');
            if isequal(f,0), return; end
            imwrite(frm.cdata,fullfile(p,f)); disp(['Saved composite to ' fullfile(p,f)]);
        end

        function saveObject(obj)
            [f,p] = uiputfile('*.mat','Save Overlay Object');
            if isequal(f,0), return; end
            save(fullfile(p,f),'obj'); disp(['Saved object to ' fullfile(p,f)]);
        end
    end
end
