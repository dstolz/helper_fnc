function xlabelf(varargin)

os = varargin{1};
if ishandle(os)
    os = varargin{1};
    varargin(1) = [];
end

str = sprintf(varargin{:});
xlabel(str,Interpreter = "none");