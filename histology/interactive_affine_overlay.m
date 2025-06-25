function interactive_affine_overlay(ffnFG, ffnBG, options)
    %% Interactive Affine Overlay GUI
    % INTERACTIVE_AFFINE_OVERLAY  Overlay a transparent RGBA image on a background
    %   and interactively manipulate translation, rotation, scale, contrast,
    %   flip, and view commands via keyboard.
    %
    %   Controls (with modifiers):
    %     Arrow keys       : Translate image       (Ctrl=fine adjust, Shift=amplify)
    %     ',' and '.'      : Rotate CCW/CW         (Ctrl=fine adjust, Shift=amplify)
    %     '+' and '-'      : Scale up/down         (Ctrl=fine adjust, Shift=amplify)
    %     '[' and ']'      : Decrease/increase CLim range (Ctrl=fine adjust, Shift=amplify)
    %     'h'              : Toggle horizontal flip
    %     'v'              : Toggle vertical flip
    %     '?'              : Display available commands in Command Window
    %     'r'              : Reset transform, flips, and CLim to initial
    %
    %   Modifier keys:
    %     Ctrl  : Use finer/smaller increments for translation, rotation, scale, and CLim adjustments
    %     Shift : Use larger/amplified increments for translation, rotation, scale, and CLim adjustments
    %
    arguments
        ffnFG            (1,:) char {mustBeFile}
        ffnBG            (1,:) char {mustBeFile}
        % Base step sizes
        options.transBaseStep    (1,1) double = 50       % translation step
        options.rotBaseStep      (1,1) double = 5        % rotation step (deg)
        options.scaleBaseStep    (1,1) double = 1.2      % scale multiplier
        % Ctrl modifiers (fraction of base)
        options.ctrlTransFactor  (1,1) double = 10/50   % translation fine factor
        options.ctrlRotFactor    (1,1) double = 1/5     % rotation fine factor
        options.ctrlScaleFactor  (1,1) double = 1.1     % scale fine factor
        % Shift modifiers
        options.shiftTransFactor (1,1) double = 5       % translation amplify
        options.shiftRotFactor   (1,1) double = 2       % rotation amplify
        options.shiftScalePower  (1,1) double = 1.5     % scale exponent
        % Initial transform and contrast
        options.scale            (1,1) double = 3.0
        options.thetaDeg         (1,1) double = 0.0
        options.tx               (1,1) double = 0       % default top-left
        options.ty               (1,1) double = 0       % default top-left
        options.clim             (1,2) double = [0 100]  % initial axes CLim
        options.ax               matlab.graphics.axis.Axes = []
    end

    % Read background and foreground images
    imgBg = imread(ffnBG);
    imgFG = imread(ffnFG);
    if size(imgFG,3) == 4
        fgRGB    = imgFG(:,:,1:3);
        alphaRaw = double(imgFG(:,:,4))/255;
    else
        fgRGB    = imgFG;
        % mask where all channels are zero
        alphaRaw = 1-double(all(fgRGB == 0, 3));
    end

    % Initialize state, including flip flags
    state = struct('scale',    options.scale, ...
        'thetaDeg', options.thetaDeg, ...
        'tx',       options.tx, ...
        'ty',       options.ty, ...
        'flipH',    false, ...
        'flipV',    false, ...
        'opts',     options);

    % Setup figure/axes
    if isempty(options.ax)
        hFig = figure('Name','Outline Overlay','NumberTitle','off',...
                      'KeyPressFcn',@keyPressCallback);
        ax = axes('Parent',hFig);
    else
        ax = options.ax;
        hFig = ancestor(ax,'figure');
        set(hFig,'KeyPressFcn',@keyPressCallback);
        cla(ax);
    end

    % Display background
    imshow(imgBg,[],'Parent',ax);
    colormap(ax,'bone');
    clim(ax,options.clim);
    hold(ax,'on');

    % Display filenames in title
    [~,fnBG] = fileparts(ffnBG);
    [~,fnFG] = fileparts(ffnFG);
    title(ax, sprintf('BG: %s\nFG: %s',fnBG,fnFG), 'Interpreter', 'none');

    % Create overlay object (data will be set in update)
    state.hOverlay = imshow(fgRGB,'Parent',ax);
    set(state.hOverlay,'AlphaData',alphaRaw);
    hold(ax,'off');

    % Store additional state
    state.imgBg    = imgBg;
    state.fgRGB    = fgRGB;
    state.alphaRaw = alphaRaw;
    state.Rbg      = imref2d(size(imgBg(:,:,1)));
    state.ax       = ax;
    guidata(hFig,state);

    % Initial drawing
    updateOverlay(state);

    function keyPressCallback(src,event)
        s      = guidata(src);
        o      = s.opts;
        isCtrl = any(strcmp(event.Modifier,'control'));
        isShift= any(strcmp(event.Modifier,'shift'));

        % Help
        if isequal(event.Character,'?')
            help interactive_affine_overlay
            return;
        end

        % Flip toggles
        switch event.Key
            case 'h'  % horizontal flip
                s.flipH = ~s.flipH;
                updateOverlay(s);
                guidata(src,s);
                return;
            case 'v'  % vertical flip
                s.flipV = ~s.flipV;
                updateOverlay(s);
                guidata(src,s);
                return;
        end

        % Translation step
        ts = o.transBaseStep * (isCtrl*o.ctrlTransFactor + ~isCtrl);
        if isShift, ts = ts * o.shiftTransFactor; end
        % Rotation step
        rs = o.rotBaseStep   * (isCtrl*o.ctrlRotFactor   + ~isCtrl);
        if isShift, rs = rs * o.shiftRotFactor; end
        % Scale factor
        ss = (isCtrl * o.ctrlScaleFactor + ~isCtrl*o.scaleBaseStep);
        if isShift, ss = ss^o.shiftScalePower; end
        % CLim step
        cs = 10*(~isCtrl) + 2*isCtrl;
        if isShift, cs = cs*2; end

        switch event.Key
            case 'leftarrow',  s.tx = s.tx - ts;
            case 'rightarrow', s.tx = s.tx + ts;
            case 'uparrow',    s.ty = s.ty - ts;
            case 'downarrow',  s.ty = s.ty + ts;
            case 'comma',      s.thetaDeg = s.thetaDeg - rs;
            case 'period',     s.thetaDeg = s.thetaDeg + rs;
            case {'add','equal'},       s.scale = s.scale * ss;
            case {'subtract','hyphen'}, s.scale = s.scale / ss;
            case 'leftbracket'  % decrease CLim
                c=clim(s.ax); clim(s.ax, [0, c(2)-cs]); return;
            case 'rightbracket' % increase CLim
                c=clim(s.ax); clim(s.ax, [0, c(2)+cs]); return;
            case 'r'  % reset
                s.scale    = o.scale;
                s.thetaDeg = o.thetaDeg;
                s.tx       = o.tx;
                s.ty       = o.ty;
                s.flipH    = false;
                s.flipV    = false;
                clim(s.ax, o.clim);
            otherwise, return;
        end
        updateOverlay(s);
        guidata(src,s);
    end

    function updateOverlay(s)
        % Prepare foreground data with flips
        fg = s.fgRGB;
        alpha = s.alphaRaw;
        if s.flipH
            fg = fliplr(fg);
            alpha = fliplr(alpha);
        end
        if s.flipV
            fg = flipud(fg);
            alpha = flipud(alpha);
        end

        % Build transform
        cx    = size(fg,2)/2;
        cy    = size(fg,1)/2;
        theta = deg2rad(s.thetaDeg);
        sc    = s.scale;
        Tneg  = [1 0 0; 0 1 0; -cx -cy 1];
        RS    = [sc*cos(theta) sc*sin(theta) 0; -sc*sin(theta) sc*cos(theta) 0; 0 0 1];
        Tpos  = [1 0 0; 0 1 0; cx cy 1];
        Ttrans= [1 0 0; 0 1 0; s.tx s.ty 1];
        A     = Tneg * RS * Tpos * Ttrans;
        tform = affine2d(A);

        % Warp and update overlay
        [wRGB,Rw] = imwarp(fg,    tform, 'OutputView', s.Rbg);
        wAlpha    = imwarp(alpha, tform, 'OutputView', s.Rbg);

        set(s.hOverlay, 'CData', wRGB, 'AlphaData', wAlpha, ...
            'XData', Rw.XWorldLimits, 'YData', Rw.YWorldLimits);
        drawnow;
    end
end
