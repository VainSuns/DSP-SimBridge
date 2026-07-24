function issues = c2837x_block_validate_candidate_files(candidates)
%C2837X_BLOCK_VALIDATE_CANDIDATE_FILES Validate candidate target paths.

required = {'target_path', 'category', 'owner', 'instance_index', ...
    'content_bytes', 'content_size_octets'};
if ~isstruct(candidates) || ~all(isfield(candidates, required))
    issues = make_issue('Error', 'CANDIDATES_INVALID', ...
        'Candidates must use the fixed candidate model.', 'candidates', 0, '');
    return;
end

targets = repmat(struct('path', '', 'kind', 'file', 'owner', ''), ...
    1, numel(candidates));
for index = 1:numel(candidates)
    targets(index).path = candidates(index).target_path;
    targets(index).owner = candidates(index).owner;
end
issues = c2837x_block_validate_path_targets(targets);
for issueIndex = 1:numel(issues)
    token = regexp(issues(issueIndex).field_path, ...
        '^targets\((\d+)\)\.(.*)$', 'tokens', 'once');
    if ~isempty(token)
        candidateIndex = str2double(token{1});
        fieldName = token{2};
        if strcmp(fieldName, 'path')
            fieldName = 'target_path';
        end
        issues(issueIndex).field_path = sprintf('candidates(%u).%s', ...
            candidateIndex, fieldName);
        issues(issueIndex).instance_index = ...
            candidates(candidateIndex).instance_index;
    end
    if strcmp(issues(issueIndex).code, 'TARGET_FILE_OCCUPIED_BY_DIRECTORY')
        issues(issueIndex).code = 'CANDIDATE_TARGET_IS_DIRECTORY';
        issues(issueIndex).message = ...
            'A directory occupies the candidate target path.';
    end
end
end

function value = make_issue(severity, code, message, fieldPath, instanceIndex, filePath)
value = struct('severity', severity, 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', instanceIndex, ...
    'file_path', filePath);
end
