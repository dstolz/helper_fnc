function ylabelf(varargin)

os = varargin{1};
if ishandle(os)
    os = varargin{1};
    varargin(1) = [];
end

str = sprintf(varargin{:});
ylabel(str,Interpreter = "none");