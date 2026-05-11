function app = launch_ecm_analysis_gui()
% launch_ecm_analysis_gui
%   app = launch_ecm_analysis_gui()
%
% Launch the ECM analysis GUI application.

app = ECMAnalysisApp();

if nargout == 0
    clear app
end

end
