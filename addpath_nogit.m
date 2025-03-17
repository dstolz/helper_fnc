function r = addpath_nogit(rootpth)
% ADDPATH_NOGIT Add folder and subfolders to MATLAB path, excluding `.git` directories.
%
%   r = ADDPATH_NOGIT(rootpth) adds the specified folder `rootpth` and all 
%   its subfolders to the MATLAB search path, except for any directories 
%   containing `.git` in their names. The function ensures compatibility 
%   with different operating systems by using the appropriate path 
%   separator (`;` for Windows, `:` for others).
%
%   Input:
%       rootpth - A character vector specifying the root folder whose 
%                 subdirectories should be added to the path.
%
%   Output:
%       r - A character vector of the resulting search path after adding 
%           the filtered directories.
%
%   Example:
%       % Add all subfolders of 'my_project', excluding `.git` directories
%       addpath_nogit('C:\my_project');
%
%   Notes:
%       - This function uses `genpath` to generate the list of subfolders 
%         and filters out those containing `.git`.
%       - The `mustBeFolder` validation ensures that `rootpth` is a valid 
%         folder.
%       - If no output argument is provided, the result is not returned.
%
% DJS 2024

arguments
    rootpth (1,:) char {mustBeFolder}
end

sep = ";";
if ~ispc(), sep = ":"; end

pth = genpath(rootpth);

pth = split(pth,sep);

i = cellfun(@(a) isempty(a) || contains(a,'.git'),pth);

pth(i) = [];

pth = join(pth,sep);

r = addpath(char(pth));

if nargout == 0, clear r; end