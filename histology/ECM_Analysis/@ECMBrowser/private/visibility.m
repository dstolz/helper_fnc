function state = visibility(tf)
%VISIBILITY Turn a condition into a HandleVisibility setting.

if tf
    state = "on";
else
    state = "off";
end

end
