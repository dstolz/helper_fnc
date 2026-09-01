function B = launch_ecm_browser(A)
% launch_ecm_browser
%   launch_ecm_browser(A)
%   B = launch_ecm_browser(A)
%
% Open the ECM browser on the output of ecm_prepare_analysis_data.
%
% Parameters
%   A: Struct returned by ecm_prepare_analysis_data.
%
% Returns
%   B: The browser object, when one is asked for.
%
% See also ECMBROWSER, ECM_PREPARE_ANALYSIS_DATA.

arguments
    A struct
end

B = ECMBrowser(A);

if nargout == 0
    clear B
end

end
