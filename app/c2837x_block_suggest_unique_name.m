function name = c2837x_block_suggest_unique_name(prefix, existingNames)
%C2837X_BLOCK_SUGGEST_UNIQUE_NAME Return the first unused numbered name.

if ~valid_prefix(prefix) || ~valid_existing_names(existingNames)
    error('C2837xBlock:App:InvalidNameSuggestionInput', ...
        'Prefix and existing names must use the supported text models.');
end
prefix = char(prefix);
existingNames = cellstr(existingNames);
index = 1;
while true
    name = sprintf('%s_%u', prefix, index);
    if ~any(strcmpi(name, existingNames))
        return;
    end
    index = index + 1;
end
end

function valid = valid_prefix(value)
valid = ((ischar(value) && isrow(value)) || ...
    (isstring(value) && isscalar(value) && ~ismissing(value))) && ...
    ~isempty(regexp(char(value), '^[A-Za-z][A-Za-z0-9_]*$', 'once'));
end

function valid = valid_existing_names(values)
valid = iscellstr(values) || isstring(values);
if valid && isstring(values)
    valid = ~any(ismissing(values), 'all');
end
end
