%%

% ffnFG = "G:/Shared drives/CarasLab/SCIENTIFIC RESOURCES- PAPERS, TEXTBOOKS, ETC/Gerbil Atlas/Radke-Schuller et al 2016 - Outlines/AllOutlines_lowres/GerbilAtlas_Plate_30.tif";
ffnFG = "G:/Shared drives/CarasLab/SCIENTIFIC RESOURCES- PAPERS, TEXTBOOKS, ETC/Gerbil Atlas/Radke-Schuller et al 2016 - Outlines/AxialPlates_beta/Axial_Plate_14_-4.55mm.tif";

ffnBG = "G:/Shared drives/CarasLab/IMAGES/SUBJ-ID-994/SUBJ-ID-994cFos25dilutions250617S2_1SLIDE_LR_DAPI_Z1_250701_1.png";
% Script to control InteractiveAffineOverlay rotation with a uiknob


% UI script: InteractiveAffineOverlay with command list
f = uifigure;
g = uigridlayout(f);
g.ColumnWidth = {'1x',200};
g.RowHeight = {'1x'};

% Create axes and overlay
ax = uiaxes(g);
ax.Layout.Column = 1;
ax.Layout.Row = 1;

% Initialize overlay, passing the axes handle
ia = InteractiveAffineOverlay(ffnFG, ffnBG, 'ax', ax);
% Remove default title
title(ax, '');

% Create non-editable text area for commands
txt = uitextarea(g, 'Editable', 'off');
txt.Layout.Column = 2;
txt.Layout.Row =  1;

% List available keyboard commands
txt.Value = {
    'Arrow Keys : Translate overlay';
    ', / .      : Rotate CCW / CW';
    '+ / =      : Scale up';
    '- / _      : Scale down';
    'h          : Toggle horizontal flip';
    'v          : Toggle vertical flip';
    '[ / ]      : Decrease / Increase contrast';
    'i          : Toggle info display';
    'r          : Reset transforms';
    't          : Save transform parameters';
    'w          : Save composite image';
    'o          : Save overlay object';
    '?          : Show commands'
};
