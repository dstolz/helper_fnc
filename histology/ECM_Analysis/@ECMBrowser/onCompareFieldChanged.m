function onCompareFieldChanged(obj, redraw)
    %ONCOMPAREFIELDCHANGED Offer the new field's values as references.
    % The reference is one value of whichever field is being compared,
    % so the list of them is rebuilt whenever that field changes. The
    % value showing is kept if the new field also holds it, which it
    % will not usually, and otherwise falls to the first -- a choice
    % worth checking rather than one worth refusing to make.

    arguments
        obj
        redraw (1,1) logical = true
    end

    field = string(obj.CompareFieldDropDown.Value);

    if field == obj.NoField
        obj.CompareRefDropDown.Items = cellstr(obj.NoField);
    else
        levels = obj.levelsOf(field);
        showing = string(obj.CompareRefDropDown.Value);

        % The two references that are not a value of the field lead
        % the list, where a field with a great many values does not
        % bury them, but a value of the field is still what the list
        % opens on: it is the answer for the fields that have one, and
        % the fields that do not are the ones worth a second look.
        offered = [obj.RestOfMatch; obj.EachPair; levels];

        obj.CompareRefDropDown.Items = cellstr(offered);
        obj.CompareRefDropDown.Value = levels(1);

        if ismember(showing, offered)
            obj.CompareRefDropDown.Value = showing;
        end
    end

    if redraw
        obj.refresh();
    end

end
