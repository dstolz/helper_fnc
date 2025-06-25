function h = titlef(varargin)

os = varargin{1};
if ishandle(os)
    os = varargin{1};
    varargin(1) = [];
else
    os = gca;
end

str = sprintf(varargin{:});
h = title(os,str,Interpreter = "none");

if nargout == 0, clear h; end