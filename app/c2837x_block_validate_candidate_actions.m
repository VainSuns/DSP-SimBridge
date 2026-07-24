function issues = c2837x_block_validate_candidate_actions(comparisons)
%C2837X_BLOCK_VALIDATE_CANDIDATE_ACTIONS Enforce candidate action policy.

required = {'target_path', 'category', 'instance_index', 'target_state', ...
    'selected_action'};
if ~isstruct(comparisons) || ~all(isfield(comparisons, required))
    issues = make_issue('CANDIDATE_ACTION_INVALID', ...
        'Comparisons must use the fixed comparison model.', '', 0, 0);
    return;
end
issues = empty_issues();
for index = 1:numel(comparisons)
    comparison = comparisons(index);
    code = invalid_action_code(comparison);
    if ~isempty(code)
        issues(end + 1) = make_issue(code, action_message(code), ...
            comparison.target_path, comparison.instance_index, index); %#ok<AGROW>
    end
end
end

function code = invalid_action_code(comparison)
state = comparison.target_state;
action = comparison.selected_action;
if strcmp(state, 'blocked')
    code = 'CANDIDATE_COMPARISON_BLOCKED';
elseif strcmp(state, 'missing') && ~strcmp(action, 'create')
    code = 'CANDIDATE_CREATE_REQUIRED';
elseif strcmp(state, 'same') && ~strcmp(action, 'skip')
    code = 'CANDIDATE_SKIP_REQUIRED';
elseif strcmp(state, 'different') && ...
        any(strcmp(comparison.category, {'auto_generated', 'core'})) && ...
        ~strcmp(action, 'replace')
    code = 'CANDIDATE_REPLACE_REQUIRED';
elseif strcmp(state, 'different') && strcmp(comparison.category, 'user') && ...
        ~any(strcmp(action, {'keep', 'replace'}))
    code = 'CANDIDATE_ACTION_INVALID';
elseif ~any(strcmp(state, {'missing', 'same', 'different'}))
    code = 'CANDIDATE_ACTION_INVALID';
else
    code = '';
end
end

function message = action_message(code)
switch code
    case 'CANDIDATE_CREATE_REQUIRED'
        message = 'A missing target must use create.';
    case 'CANDIDATE_SKIP_REQUIRED'
        message = 'An identical target must use skip.';
    case 'CANDIDATE_REPLACE_REQUIRED'
        message = 'A changed automatic or core target must use replace.';
    case 'CANDIDATE_COMPARISON_BLOCKED'
        message = 'A blocked comparison cannot be executed.';
    otherwise
        message = 'The selected candidate action is invalid.';
end
end

function value = make_issue(code, message, filePath, instanceIndex, index)
if index == 0
    fieldPath = 'comparisons';
else
    fieldPath = sprintf('comparisons(%u).selected_action', index);
end
value = struct('severity', 'Error', 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', instanceIndex, ...
    'file_path', filePath);
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end
