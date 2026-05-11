        function [co, cmap] = resolvePlotColors(obj, nColors)
            if nargin < 2 || isempty(nColors)
                nColors = 12;
            end

            mode = string(obj.PlotColorDropDown.Value);
            nMap = max(256, nColors);

            switch mode
                case "lines"
                    co = lines(nColors);
                    cmap = lines(nMap);
                case "parula"
                    cmap = parula(nMap);
                    co = parula(nColors);
                case "turbo"
                    cmap = turbo(nMap);
                    co = turbo(nColors);
                case "gray"
                    cmap = gray(nMap);
                    co = gray(nColors);
                case "hot"
                    cmap = hot(nMap);
                    co = hot(nColors);
                case "cool"
                    cmap = cool(nMap);
                    co = cool(nColors);
                case {"viridis", "plasma", "magma", "inferno"}
                    if exist(mode, "file") == 2 || exist(mode, "builtin") == 5
                        cmap = feval(mode, nMap);
                        co = feval(mode, nColors);
                    else
                        cmap = parula(nMap);
                        co = parula(nColors);
                    end
                otherwise
                    cmap = parula(nMap);
                    co = lines(nColors);
            end
        end
