function issues = c2837x_block_validate_candidate_files(candidates)
%C2837X_BLOCK_VALIDATE_CANDIDATE_FILES Validate the fixed candidate model.

required = {'target_path', 'category', 'owner', 'instance_index', ...
    'content_bytes', 'content_size_octets'};
if ~isstruct(candidates) || ~all(isfield(candidates, required))
    issues = make_issue('CANDIDATES_INVALID', ...
        'Candidates must use the fixed candidate model.', 'candidates', 0, '');
    return;
end

issues = empty_issues();
paths = cell(1, numel(candidates));
owners = cell(1, numel(candidates));
instanceIndices = zeros(1, numel(candidates));
for index = 1:numel(candidates)
    candidate = candidates(index);
    [pathValid, paths{index}] = canonical_path(candidate.target_path);
    [categoryText, category] = text_value(candidate.category);
    [ownerText, owners{index}] = text_value(candidate.owner);
    instanceValid = valid_nonnegative_integer(candidate.instance_index);
    contentValid = isa(candidate.content_bytes, 'uint8') && ...
        ismatrix(candidate.content_bytes) && size(candidate.content_bytes, 1) == 1;
    sizeValid = valid_nonnegative_integer(candidate.content_size_octets) && ...
        candidate.content_size_octets == numel(candidate.content_bytes);
    if instanceValid
        instanceIndices(index) = double(candidate.instance_index);
    end
    filePath = paths{index};

    if ~pathValid
        add('CANDIDATE_PATH_INVALID', ...
            'Target path must be canonical absolute text.', 'target_path');
    end
    if ~categoryText || ...
            ~any(strcmp(category, {'auto_generated', 'core', 'user'}))
        add('CANDIDATE_CATEGORY_INVALID', ...
            'Category must be auto_generated, core, or user.', 'category');
    end
    if ~ownerText || isempty(owners{index})
        add('CANDIDATE_OWNER_INVALID', ...
            'Owner must be nonempty scalar text.', 'owner');
    end
    if ~instanceValid
        add('CANDIDATE_INSTANCE_INDEX_INVALID', ...
            'Instance index must be a nonnegative finite integer.', 'instance_index');
    end
    if ~contentValid
        add('CANDIDATE_CONTENT_INVALID', ...
            'Content must be a uint8 row vector.', 'content_bytes');
    end
    if ~sizeValid
        add('CANDIDATE_CONTENT_SIZE_INVALID', ...
            'Content size must equal the number of content octets.', ...
            'content_size_octets');
    end
end
if ~isempty(issues)
    return;
end

targets = repmat(struct('path', '', 'kind', 'file', 'owner', ''), ...
    1, numel(candidates));
for index = 1:numel(candidates)
    targets(index).path = paths{index};
    targets(index).owner = owners{index};
end
pathIssues = c2837x_block_validate_path_targets(targets);
for issueIndex = 1:numel(pathIssues)
    token = regexp(pathIssues(issueIndex).field_path, ...
        '^targets\((\d+)\)\.(.*)$', 'tokens', 'once');
    if ~isempty(token)
        candidateIndex = str2double(token{1});
        fieldName = token{2};
        if strcmp(fieldName, 'path')
            fieldName = 'target_path';
        end
        pathIssues(issueIndex).field_path = sprintf('candidates(%u).%s', ...
            candidateIndex, fieldName);
        pathIssues(issueIndex).instance_index = instanceIndices(candidateIndex);
    end
    if strcmp(pathIssues(issueIndex).code, 'TARGET_FILE_OCCUPIED_BY_DIRECTORY')
        pathIssues(issueIndex).code = 'CANDIDATE_TARGET_IS_DIRECTORY';
        pathIssues(issueIndex).message = ...
            'A directory occupies the candidate target path.';
    end
end
issues = pathIssues;

    function add(code, message, fieldName)
        issues(end + 1) = make_issue(code, message, ... %#ok<AGROW>
            sprintf('candidates(%u).%s', index, fieldName), ...
            instanceIndices(index), filePath);
    end
end

function [valid, value] = canonical_path(rawValue)
[valid, value] = text_value(rawValue);
if ~valid || isempty(value)
    valid = false;
    value = '';
    return;
end
try
    valid = strcmp(value, c2837x_block_normalize_absolute_path(value));
catch
    valid = false;
end
if ~valid
    value = '';
end
end

function [valid, value] = text_value(rawValue)
valid = (ischar(rawValue) && isrow(rawValue)) || ...
    (isstring(rawValue) && isscalar(rawValue) && ~ismissing(rawValue));
if valid
    value = char(rawValue);
else
    value = '';
end
end

function valid = valid_nonnegative_integer(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value == fix(value);
end

function value = make_issue(code, message, fieldPath, instanceIndex, filePath)
value = struct('severity', 'Error', 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', instanceIndex, ...
    'file_path', filePath);
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end
