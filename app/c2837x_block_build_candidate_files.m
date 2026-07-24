function candidates = c2837x_block_build_candidate_files(definitions)
%C2837X_BLOCK_BUILD_CANDIDATE_FILES Validate in-memory file candidates.

required = {'target_path', 'category', 'owner', 'instance_index', 'content_bytes'};
if ~isstruct(definitions) || ~all(isfield(definitions, required))
    error('C2837xBlock:Candidate:InvalidDefinitions', ...
        'Definitions must be a struct array with all required fields.');
end

prototype = struct('target_path', '', 'category', '', 'owner', '', ...
    'instance_index', 0, 'content_bytes', zeros(1, 0, 'uint8'), ...
    'content_size_octets', 0);
candidates = repmat(prototype, 1, numel(definitions));
for index = 1:numel(definitions)
    definition = definitions(index);
    path = text_value(definition.target_path, ...
        'C2837xBlock:Candidate:InvalidPath', 'Target path');
    try
        normalized = c2837x_block_normalize_absolute_path(path);
    catch
        error('C2837xBlock:Candidate:InvalidPath', ...
            'Target path must be a canonical absolute path.');
    end
    if isempty(normalized) || ~strcmp(path, normalized)
        error('C2837xBlock:Candidate:InvalidPath', ...
            'Target path must be a canonical absolute path.');
    end

    category = text_value(definition.category, ...
        'C2837xBlock:Candidate:InvalidCategory', 'Category');
    if ~any(strcmp(category, {'auto_generated', 'core', 'user'}))
        error('C2837xBlock:Candidate:InvalidCategory', ...
            'Category must be auto_generated, core, or user.');
    end
    owner = text_value(definition.owner, ...
        'C2837xBlock:Candidate:InvalidOwner', 'Owner');
    if isempty(owner)
        error('C2837xBlock:Candidate:InvalidOwner', ...
            'Owner must be nonempty text.');
    end
    instanceIndex = definition.instance_index;
    if ~isnumeric(instanceIndex) || ~isreal(instanceIndex) || ...
            ~isscalar(instanceIndex) || ~isfinite(instanceIndex) || ...
            instanceIndex < 0 || instanceIndex ~= fix(instanceIndex)
        error('C2837xBlock:Candidate:InvalidInstanceIndex', ...
            'Instance index must be a nonnegative finite integer.');
    end
    bytes = definition.content_bytes;
    if ~isa(bytes, 'uint8') || ~(isrow(bytes) || ...
            (isempty(bytes) && size(bytes, 1) == 1))
        error('C2837xBlock:Candidate:InvalidContent', ...
            'Content must be a uint8 row vector.');
    end

    candidates(index) = struct('target_path', path, 'category', category, ...
        'owner', owner, 'instance_index', double(instanceIndex), ...
        'content_bytes', bytes, 'content_size_octets', double(numel(bytes)));
end
end

function value = text_value(value, identifier, label)
if (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))
    value = char(value);
else
    error(identifier, '%s must be scalar text.', label);
end
end
