function applySettings(obj, s)
    %APPLYSETTINGS Put every control on the panel into the state S describes.
    % Color by, Tile by, and Filter by name fields that belong to
    % whatever dataset was open when S was saved. Anything this
    % dataset does not also have is left as it was rather than
    % raising an error over a mismatch.

    obj.SignalDropDown.Value = s.Signal;
    obj.NormalizeDropDown.Value = s.Normalize;
    obj.ScopeDropDown.Value = s.Scope;
    obj.RefMinField.Value = s.RefMin;
    obj.RefMaxField.Value = s.RefMax;
    obj.ShowDropDown.Value = obj.oneOf(s.Show, obj.ShowModes);
    obj.ErrorDropDown.Value = s.ErrorBand;

    % A configuration saved before the metric summary existed says
    % nothing about which metric, and opens on the first of them.
    if isfield(s, "Metric")
        obj.MetricDropDown.Value = obj.oneOf(s.Metric, obj.SummaryMetrics);
    end
    obj.SectionsCheckBox.Value = s.SectionsBehind;

    if ismember(s.Group, string(obj.GroupDropDown.Items))
        obj.GroupDropDown.Value = s.Group;
    end

    tile = s.Tile(ismember(s.Tile, string(obj.TileListBox.Items)));

    if isempty(tile)
        tile = obj.NoField;
    end

    obj.TileListBox.Value = cellstr(tile);

    % A configuration saved before a filter could hold more than one field
    % names the one it held, and comes back as the single condition it was.
    if isfield(s, "Filters")
        obj.Filters = obj.knownFilters(s.Filters);
    elseif isfield(s, "FilterField") && s.FilterField ~= obj.AllSections
        obj.Filters = obj.knownFilters(struct( ...
            Field = s.FilterField, Values = s.FilterValues, Keep = true));
    else
        obj.Filters(:) = [];
    end

    if isfield(s, "FilterMatch")
        obj.FilterMatchDropDown.Value = obj.oneOf(s.FilterMatch, obj.FilterMatches);
    end

    % The editor opens on the first condition restored, so that a view put
    % back filtered shows what it is filtered by rather than an empty list
    % of values over a panel that is quietly dropping sections.
    if isempty(obj.Filters)
        obj.FilterFieldDropDown.Value = obj.AllSections;
    else
        obj.FilterFieldDropDown.Value = obj.Filters(1).Field;
    end

    obj.onFilterFieldChanged(false);
    obj.refreshFilterList();

    obj.DepthMinField.Value = s.DepthMin;
    obj.DepthMaxField.Value = s.DepthMax;
    obj.LegendDropDown.Value = obj.legendPlacement(s.Legend);
    obj.LinkCheckBox.Value = s.Link;

    % A configuration saved before one of these was a control says
    % nothing about it, and is left at whatever the panel is showing
    % rather than being read as a missing field.
    if isfield(s, "Transpose")
        obj.TransposeCheckBox.Value = s.Transpose;
    end

    if isfield(s, "TileSpacing")
        obj.SpacingDropDown.Value = obj.oneOf(s.TileSpacing, obj.TileSpacings);
    end

    if isfield(s, "Padding")
        obj.PaddingDropDown.Value = obj.oneOf(s.Padding, obj.LayoutPaddings);
    end

    if isfield(s, "TickLabels")
        obj.TickLabelDropDown.Value = obj.oneOf(s.TickLabels, obj.TickLabelModes);
    end

    if isfield(s, "AxisQuantity")
        obj.AxisQuantityCheckBox.Value = s.AxisQuantity;
    end

    % The reference is one value of whichever field is compared, so
    % the field is set first and its values offered before the
    % reference is picked out of them. A field this dataset does not
    % have leaves the comparison off rather than half set.
    if isfield(s, "Compare")
        obj.CompareDropDown.Value = obj.oneOf(s.Compare, obj.CompareOps);

        if ismember(s.CompareField, string(obj.CompareFieldDropDown.Items))
            obj.CompareFieldDropDown.Value = s.CompareField;
        else
            obj.CompareFieldDropDown.Value = obj.NoField;
        end

        obj.onCompareFieldChanged(false);

        if ismember(s.CompareRef, string(obj.CompareRefDropDown.Items))
            obj.CompareRefDropDown.Value = s.CompareRef;
        end

        paired = s.PairWithin(ismember(s.PairWithin, string(obj.PairListBox.Items)));

        if isempty(paired)
            paired = obj.NoField;
        end

        obj.PairListBox.Value = cellstr(paired);
    end

    obj.refresh();

end
