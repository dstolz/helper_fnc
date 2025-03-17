function subtitlef(varargin)

os = varargin{1};
if ishandle(os)
    os = varargin{1};
    varargin(1) = [];
else
    os = gca;
end

str = sprintf(varargin{:});
subtitle(os,str,Interpreter = "none");