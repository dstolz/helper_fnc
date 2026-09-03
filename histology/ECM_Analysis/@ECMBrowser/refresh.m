function refresh(obj)
    %REFRESH Redraw the panel from the current control state.
    % Public, so a control can be set from the command line or a test
    % and the view brought up to date without reaching inside.

    if obj.IsRefreshing
        % See the comment on IsREFRESHING: this call was fired by a
        % DRAWNOW nested inside the refresh already running, and must
        % wait for that one to finish rather than delete the panel
        % out from under it.
        obj.RefreshPending = true;
        return
    end

    obj.IsRefreshing = true;
    finishGuard = onCleanup(@() obj.setNotRefreshing());

    keepGoing = true;

    while keepGoing
        obj.RefreshPending = false;

        % A control that cannot affect the current view is grayed out
        % rather than left to be tried: the peak summary is one point per
        % section taken from A.peaks, so neither the signal nor the depth
        % window reaches it.
        show = string(obj.ShowDropDown.Value);

        obj.ErrorDropDown.Enable = matlab.lang.OnOffSwitchState(show == "group mean");
        obj.SectionsCheckBox.Enable = obj.ErrorDropDown.Enable;

        onProfiles = matlab.lang.OnOffSwitchState(show ~= "peak summary");
        obj.SignalDropDown.Enable = onProfiles;
        obj.DepthMinField.Enable = onProfiles;
        obj.DepthMaxField.Enable = onProfiles;

        % The scope and the reference window belong to the normalization
        % rather than to the view, so they stay live in the peak summary the
        % depth controls above cannot reach, and go quiet only when there is
        % nothing being rescaled.
        normalized = matlab.lang.OnOffSwitchState( ...
            string(obj.NormalizeDropDown.Value) ~= "none");
        obj.ScopeDropDown.Enable = normalized;
        obj.RefMinField.Enable = normalized;
        obj.RefMaxField.Enable = normalized;

        % What a comparison is taken between, and where the pairs are
        % looked for, mean nothing until there is a comparison to take.
        comparing = matlab.lang.OnOffSwitchState( ...
            string(obj.CompareDropDown.Value) ~= "none");
        obj.CompareFieldDropDown.Enable = comparing;
        obj.CompareRefDropDown.Enable = comparing;
        obj.PairListBox.Enable = comparing;

        delete(obj.PlotPanel.Children);
        obj.draw(obj.PlotPanel);

        % A callback that fired while the draw above was settling did
        % not delete anything itself -- it only asked to run again --
        % so its request is honored here, once, rather than dropped.
        keepGoing = obj.RefreshPending;
    end

end
