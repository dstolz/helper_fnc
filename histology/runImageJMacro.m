function [status, cmdout] = runImageJMacro(fijiExe, macroFile, inputFile, outputDir)
% runImageJMacro  Run an ImageJ/Fiji macro from MATLAB.
%
% [status, cmdout] = runImageJMacro(fijiExe, macroFile, inputFile, outputDir)
% runs an ImageJ macro using Fiji in headless mode.

arguments
    fijiExe (1,1) string
    macroFile (1,1) string {mustBeFile}
    inputFile (1,1) string {mustBeFile}
    outputDir (1,1) string {mustBeFolder}
end

args = sprintf('input="%s",output="%s"', inputFile, outputDir);

cmd = sprintf('"%s" --headless --run "%s" "%s"', ...
    fijiExe, macroFile, args);

[status, cmdout] = system(cmd);

if status ~= 0
    error("runImageJMacro:ImageJFailed", ...
        "ImageJ macro failed:\n%s", cmdout)
end