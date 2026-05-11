% Quick test of ECMAnalysisApp with new layout
addpath(genpath('c:/src/helper_fnc'));

try
    app = ECMAnalysisApp();
    disp('✓ App instantiated successfully');
    
    % Verify control panel exists and components are in it
    if isvalid(app.PlotTypeDropDown) && isvalid(app.FacetVarsList)
        disp('✓ Plot controls initialized');
    else
        error('Plot controls not properly initialized');
    end
    
    % Verify axes is positioned correctly (right side)
    axPos = app.PlotAxes.Position;
    if axPos(1) >= 300  % Should be on right side
        disp('✓ Plot axes positioned correctly (right side)');
    else
        error('Plot axes not positioned correctly');
    end
    
    disp('✓ All checks passed');
    close(app.Fig);
    
catch ME
    disp(['✗ Error: ', ME.message]);
    disp(ME.stack(1));
end
