function [comparisons, issues] = c2837x_block_compare_candidate_files(candidates)
%C2837X_BLOCK_COMPARE_CANDIDATE_FILES Compare candidates with target octets.

prototype = struct('target_path', '', 'category', '', 'owner', '', ...
    'instance_index', 0, 'content_bytes', zeros(1, 0, 'uint8'), ...
    'content_size_octets', 0, 'target_state', 'blocked', ...
    'default_action', 'blocked', 'selected_action', 'blocked', ...
    'action_mandatory', true, 'existing_size_octets', 0);
comparisons = repmat(prototype, 1, numel(candidates));
issues = c2837x_block_validate_candidate_files(candidates);
if any(strcmp({issues.code}, 'CANDIDATES_INVALID'))
    return;
end
for index = 1:numel(candidates)
    for field = {'target_path', 'category', 'owner', 'instance_index', ...
            'content_bytes', 'content_size_octets'}
        comparisons(index).(field{1}) = candidates(index).(field{1});
    end
end

if any(strcmp({issues.severity}, 'Error'))
    return;
end

for index = 1:numel(candidates)
    path = candidates(index).target_path;
    if isfolder(path)
        issues(end + 1) = candidate_issue('CANDIDATE_TARGET_IS_DIRECTORY', ...
            'A directory occupies the candidate target path.', ...
            candidates(index), index); %#ok<AGROW>
        continue;
    end
    if ~isfile(path)
        comparisons(index) = choose(comparisons(index), 'missing', 'create', true, 0);
        continue;
    end
    [bytes, code] = read_bytes(path);
    if ~isempty(code)
        if strcmp(code, 'CANDIDATE_TARGET_UNREADABLE')
            message = 'The candidate target file could not be opened for reading.';
        else
            message = 'The candidate target file could not be read.';
        end
        issues(end + 1) = candidate_issue(code, message, ...
            candidates(index), index); %#ok<AGROW>
        continue;
    end

    comparisons(index).existing_size_octets = double(numel(bytes));
    if isequal(bytes, candidates(index).content_bytes)
        comparisons(index) = choose(comparisons(index), 'same', 'skip', true, numel(bytes));
    elseif strcmp(candidates(index).category, 'user')
        comparisons(index) = choose(comparisons(index), 'different', 'keep', false, numel(bytes));
    else
        comparisons(index) = choose(comparisons(index), 'different', 'replace', true, numel(bytes));
    end
end
end

function comparison = choose(comparison, state, action, mandatory, existingSize)
comparison.target_state = state;
comparison.default_action = action;
comparison.selected_action = action;
comparison.action_mandatory = mandatory;
comparison.existing_size_octets = double(existingSize);
end

function [bytes, code] = read_bytes(path)
bytes = zeros(1, 0, 'uint8');
code = '';
fileID = fopen(path, 'rb');
if fileID < 0
    code = 'CANDIDATE_TARGET_UNREADABLE';
    return;
end
cleanup = onCleanup(@() fclose(fileID));
try
    bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
    [~, errorNumber] = ferror(fileID);
    if errorNumber ~= 0 && errorNumber ~= -4
        code = 'CANDIDATE_TARGET_READ_FAILED';
        bytes = zeros(1, 0, 'uint8');
    end
catch
    code = 'CANDIDATE_TARGET_READ_FAILED';
    bytes = zeros(1, 0, 'uint8');
end
clear cleanup
end

function value = candidate_issue(code, message, candidate, index)
value = struct('severity', 'Error', 'code', code, 'message', message, ...
    'field_path', sprintf('candidates(%u).target_path', index), ...
    'instance_index', candidate.instance_index, ...
    'file_path', candidate.target_path);
end
