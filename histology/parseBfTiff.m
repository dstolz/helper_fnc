function [img, info, xy_res, nChannels] = parseBfTiff(tiffFile)
%PARSEBFTIFF Read an OME-TIFF using Bio-Formats and extract image data and metadata.
%   
%   [img, info, nChannels, xy_res] = parseBfTiff(tiffFile) opens the specified
%   OME-TIFF file using the Bio-Formats library and returns:
%     img       - a 3D array where each slice along the third dimension
%                 corresponds to one image channel.
%     info      - a struct containing OME metadata fields converted to valid
%                 MATLAB field names.
%     xy_res    - a 1×2 vector [GlobalXResolution, GlobalYResolution] from metadata.
%     nChannels - the number of channels in the TIFF file.
%
%   Input:
%     tiffFile  - path to the OME-TIFF file (char array or string).
%
%   Example:
%     [img, info, nCh, res] = parseBfTiff('sample.ome.tiff');

arguments
    tiffFile (1,:) char
end

img = [];
info = [];
xy_res = [];
nChannels = [];
if ~isfile(tiffFile), return; end

% Open file with Bio-Formats
T = bfopen(tiffFile);

% Parse OME metadata into a struct
allKeys = T{2}.keySet().toArray();
info = struct();
for i = 1:length(allKeys)
    key = char(allKeys(i));
    info.(matlab.lang.makeValidName(key)) = T{2}.get(key);
end

% Extract image data and channel count
nChannels = size(T{1}, 1);
img       = zeros([size(T{1}{1,1}), nChannels], class(T{1}{1,1}));
for i = 1:nChannels
    img(:,:,i) = T{1}{i, 1};
end

% Get global XY resolutions
xy_res = [info.GlobalXResolution, info.GlobalYResolution];
