function labelLayout(obj, t, groupField, tileFields, nTiles, edgeLabels)
    %LABELLAYOUT Name the axes once for the whole layout.
    % Two or more Tile by fields split the grid on one field down its
    % rows and one across its columns, and that split is what the
    % layout's own axis labels are for -- a reader already has it once
    % on the edges of the grid, not once again in a subtitle. Fewer
    % than two fields leaves nothing to split an axis on, so the axes
    % fall back to naming the quantity every tile plots instead.

    if string(obj.ShowDropDown.Value) == "metric summary"
        % The x axis is the split itself rather than a quantity: the
        % ticks under the points already name the groups, so what is
        % said here is the field they are values of. With no field to
        % color by there is one slot holding everything, and naming it
        % "(none)" would say less than saying nothing.
        depthLabel = groupField;

        if groupField == obj.NoField
            depthLabel = "";
        end

        valueLabel = obj.metricLabel();

    elseif string(obj.ShowDropDown.Value) == "peak summary"
        % Named from the analysis rather than from the Signal control,
        % which does not reach the peaks: they were taken from whichever
        % trace ecm_prepare_analysis_data was asked to search.
        depthLabel = obj.withUnit("peak depth from surface");
        valueLabel = obj.withNormalization(strtrim(obj.peakSource() + " peak intensity"));

        if obj.View.Comparison ~= ""
            % The peaks of a comparison are the peaks of the curves
            % drawn from it, not of the trace A.peaks was searched in.
            depthLabel = obj.withUnit("depth of largest difference");
            valueLabel = obj.withNormalization( ...
                string(obj.SignalDropDown.Value) + " intensity there");
        end
    else
        depthLabel = obj.withUnit("depth from cortical surface");
        valueLabel = obj.withNormalization(string(obj.SignalDropDown.Value) + " intensity");
    end

    valueLabel = obj.withComparison(valueLabel);

    % And under it, the comparison written out in the values it was
    % taken between -- "GM6001 - Vehicle" -- so that what the plot
    % computes is on the figure whatever the curves are colored by.
    formula = obj.comparisonFormula();

    if edgeLabels
        % The edges wear values rather than field names, so the field
        % names are said here instead, split the way the grid is --
        % which is the other way round on a transposed layout.
        lead = strjoin(tileFields(1:end-1), " x ");
        last = tileFields(end);

        if obj.TransposeCheckBox.Value
            [rowsBy, colsBy] = deal(last, lead);
        else
            [rowsBy, colsBy] = deal(lead, last);
        end

        if obj.AxisQuantityCheckBox.Value
            if depthLabel ~= ""
                colsBy = colsBy + "  (" + depthLabel + ")";
            end

            rowsBy = rowsBy + "  (" + valueLabel + ")";
            rowsBy = with_formula(rowsBy, formula);
        end

        xlabel(t, colsBy, Interpreter = "none")
        ylabel(t, rowsBy, Interpreter = "none")
    else
        xlabel(t, depthLabel)
        % Read as plain text rather than as TeX: the formula is made of
        % values off the sheet, and an underscore in one of them would
        % otherwise take the rest of the name down into a subscript.
        ylabel(t, with_formula(valueLabel, formula), Interpreter = "none")
    end

    if groupField == obj.NoField
        title(t, "all sections")
    else
        title(t, "colored by " + groupField, Interpreter = "none")
    end

    if ~edgeLabels && nTiles > 1 && ~isempty(tileFields)
        subtitle(t, "tiled by " + strjoin(tileFields, " x "), Interpreter = "none")
    end

end

function lines = with_formula(label, formula)
%WITH_FORMULA LABEL, with FORMULA under it where there is one.
% A cell array of strings, which is what a text object reads as one line
% each; a label with nothing to put under it stays the one line it was.

if formula == ""
    lines = cellstr(label);
    return
end

lines = cellstr([label; formula]);

end
