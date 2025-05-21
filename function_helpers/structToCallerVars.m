function structToCallerVars(S)
% structToCallerVars assigns fields of structure S as variables in the caller's workspace
fields = fieldnames(S);
for i = 1:numel(fields)
    assignin('caller', fields{i}, S.(fields{i}));
end
