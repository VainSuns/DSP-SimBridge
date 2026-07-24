function issues = c2837x_block_validate_candidate_actions(comparisons)
%C2837X_BLOCK_VALIDATE_CANDIDATE_ACTIONS Enforce candidate action policy.

required = {'target_path', 'category', 'instance_index', 'target_state', ...
    'selected_action'};
if ~isstruct(comparisons) || ~all(isfield(comparisons, required))
    issues = make_issue('CANDIDATE_ACTION_INVALID', ...
        'Comparisons must use the fixed comparison model.', '', 0, 'comparisons');
    return;
end
issues = empty_issues();
for index = 1:numel(comparisons)
    comparison = comparisons(index);
    [pathValid, filePath] = text_value(comparison.target_path);
    instanceValid = valid_nonnegative_integer(comparison.instance_index);
    [categoryValid, category] = text_value(comparison.category);
    [stateValid, state] = text_value(comparison.target_state);
    [actionValid, action] = text_value(comparison.selected_action);
    instanceIndex = 0;
    if instanceValid
        instanceIndex = double(comparison.instance_index);
    end

    if ~pathValid || ~instanceValid
        add_invalid('The comparison model is invalid.', '');
    elseif ~categoryValid
        add_invalid('Category must be scalar text.', 'category');
    elseif ~stateValid
        add_invalid('Target state must be scalar text.', 'target_state');
    elseif ~actionValid
        add_invalid('Selected action must be scalar text.', 'selected_action');
    elseif ~any(strcmp(category, {'auto_generated', 'core', 'user'}))
        add_invalid('Candidate category is invalid.', 'category');
    elseif ~any(strcmp(state, {'missing', 'same', 'different', 'blocked'}))
        add_invalid('Candidate target state is invalid.', 'target_state');
    elseif ~any(strcmp(action, {'create', 'skip', 'replace', 'keep', 'blocked'}))
        add_invalid('Selected candidate action is invalid.', 'selected_action');
    else
        code = matrix_issue(category, state, action);
        if ~isempty(code)
            issues(end + 1) = make_issue(code, action_message(code), ...
                filePath, instanceIndex, ...
                sprintf('comparisons(%u).selected_action', index)); %#ok<AGROW>
        end
    end
end

    function add_invalid(message, fieldName)
        if isempty(fieldName)
            fieldPath = sprintf('comparisons(%u)', index);
        else
            fieldPath = sprintf('comparisons(%u).%s', index, fieldName);
        end
        issues(end + 1) = make_issue('CANDIDATE_ACTION_INVALID', ... %#ok<AGROW>
            message, filePath, instanceIndex, fieldPath);
    end
end

function code = matrix_issue(category, state, action)
if strcmp(state, 'blocked')
    code = 'CANDIDATE_COMPARISON_BLOCKED';
elseif strcmp(state, 'missing') && ~strcmp(action, 'create')
    code = 'CANDIDATE_CREATE_REQUIRED';
elseif strcmp(state, 'same') && ~strcmp(action, 'skip')
    code = 'CANDIDATE_SKIP_REQUIRED';
elseif strcmp(state, 'different') && ...
        any(strcmp(category, {'auto_generated', 'core'})) && ...
        ~strcmp(action, 'replace')
    code = 'CANDIDATE_REPLACE_REQUIRED';
elseif strcmp(state, 'different') && strcmp(category, 'user') && ...
        ~any(strcmp(action, {'keep', 'replace'}))
    code = 'CANDIDATE_ACTION_INVALID';
else
    code = '';
end
end

function [valid, value] = text_value(rawValue)
valid = (ischar(rawValue) && isrow(rawValue) && ~isempty(rawValue)) || ...
    (isstring(rawValue) && isscalar(rawValue) && ~ismissing(rawValue) && ...
    strlength(rawValue) > 0);
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

function value = make_issue(code, message, filePath, instanceIndex, fieldPath)
value = struct('severity', 'Error', 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', instanceIndex, ...
    'file_path', filePath);
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end
