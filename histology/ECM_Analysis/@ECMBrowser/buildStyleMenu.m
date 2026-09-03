function cm = buildStyleMenu(obj, fig, groupField, groups, clicked)
    %BUILDSTYLEMENU The menu behind one right-click.
    % A curve's menu leads with its own group, because that is the one
    % the click was about, and keeps the rest a level down so that a
    % click landing on the wrong curve is still one menu away from the
    % right group.

    cm = uicontextmenu(fig, Tag = char(obj.MenuTag), ...
        ContextMenuOpeningFcn = @(src, ~) obj.syncStyleMenu(src));

    others = groups;

    if clicked ~= ""
        obj.addStyleItems(cm, groupField, clicked, clicked + ": ");
        others = groups(groups ~= clicked);
    end

    if ~isempty(others)
        parent = cm;

        if clicked ~= ""
            parent = uimenu(cm, Text = "Other groups", Separator = "on");
        end

        for k = 1:numel(others)
            obj.addStyleItems(uimenu(parent, Text = others(k)), ...
                groupField, others(k), "");
        end
    end

    uimenu(cm, Text = "Reset all groups", Separator = "on", ...
        MenuSelectedFcn = @(~, ~) obj.resetGroupStyles(groupField));

end
