function issues = c2837x_block_validate_path_targets(targets)
%C2837X_BLOCK_VALIDATE_PATH_TARGETS Find deterministic target path conflicts.

issues = empty_issues();
if ~isstruct(targets) || ~all(isfield(targets, {'path', 'kind', 'owner'}))
    issues = issue('Error', 'TARGETS_INVALID', ...
        'Targets must be a struct array containing path, kind, and owner.', '', '');
    return;
end

capacity = 2 * numel(targets) + numel(targets) * (numel(targets) - 1) / 2;
issues = repmat(issue('', '', '', '', ''), 1, capacity);
issueCount = 0;
paths = cell(1, numel(targets));
for index = 1:numel(targets)
    fieldPath = sprintf('targets(%u).path', index);
    try
        paths{index} = c2837x_block_normalize_absolute_path(targets(index).path);
        if isempty(paths{index}) || ~strcmp(paths{index}, char(targets(index).path))
            error('C2837xBlock:Path:NotCanonical', 'Target path is not canonical.');
        end
    catch
        add_issue(issue('Error', 'TARGET_PATH_INVALID', ...
            'Target path must be a canonical absolute path.', fieldPath, text_or_empty(targets(index).path)));
        paths{index} = '';
        continue;
    end
    kind = text_or_empty(targets(index).kind);
    if ~any(strcmp(kind, {'file', 'directory'}))
        add_issue(issue('Error', 'TARGET_KIND_INVALID', ...
            'Target kind must be file or directory.', sprintf('targets(%u).kind', index), paths{index}));
        continue;
    end
    if isfile(paths{index}) && strcmp(kind, 'directory')
        add_issue(issue('Error', 'TARGET_DIRECTORY_OCCUPIED_BY_FILE', ...
            'A file already occupies a target directory path.', fieldPath, paths{index}));
    elseif isfolder(paths{index}) && strcmp(kind, 'file')
        add_issue(issue('Error', 'TARGET_FILE_OCCUPIED_BY_DIRECTORY', ...
            'A directory already occupies a target file path.', fieldPath, paths{index}));
    end
end

for later = 2:numel(targets)
    if isempty(paths{later})
        continue;
    end
    for earlier = 1:later - 1
        if isempty(paths{earlier})
            continue;
        end
        if paths_equal(paths{earlier}, paths{later})
            if ~strcmp(paths{earlier}, paths{later})
                code = 'TARGET_CASE_CONFLICT';
                message = 'Targets differ only by path case.';
            elseif ~strcmp(text_or_empty(targets(earlier).kind), text_or_empty(targets(later).kind))
                code = 'TARGET_KIND_CONFLICT';
                message = 'The same path is declared as both file and directory.';
            else
                code = 'TARGET_DUPLICATE';
                message = 'Multiple targets map to the same path.';
            end
            add_issue(issue('Error', code, message, ...
                sprintf('targets(%u).path', later), paths{later}));
        elseif strcmpi(paths{earlier}, paths{later})
            add_issue(issue('Error', 'TARGET_CASE_CONFLICT', ...
                'Targets differ only by path case.', ...
                sprintf('targets(%u).path', later), paths{later}));
        elseif strcmp(text_or_empty(targets(earlier).kind), 'file') && ...
                is_descendant(paths{earlier}, paths{later})
            add_issue(issue('Error', 'TARGET_BELOW_FILE', ...
                'A target is located below another target file path.', ...
                sprintf('targets(%u).path', later), paths{later}));
        elseif strcmp(text_or_empty(targets(later).kind), 'file') && ...
                is_descendant(paths{later}, paths{earlier})
            add_issue(issue('Error', 'TARGET_FILE_IS_PARENT', ...
                'A target file path is the parent of another target.', ...
                sprintf('targets(%u).path', later), paths{later}));
        end
    end
end
issues = issues(1:issueCount);

    function add_issue(value)
        issueCount = issueCount + 1;
        issues(issueCount) = value;
    end
end

function tf = paths_equal(left, right)
if ispc
    tf = strcmpi(left, right);
else
    tf = strcmp(left, right);
end
end

function tf = is_descendant(parent, child)
if paths_equal(parent, child)
    tf = false;
    return;
end
if endsWith(parent, filesep)
    prefix = parent;
else
    prefix = [parent filesep];
end
if ispc
    tf = startsWith(child, prefix, 'IgnoreCase', true);
else
    tf = startsWith(child, prefix);
end
end

function value = text_or_empty(value)
if (ischar(value) && (isrow(value) || isempty(value))) || ...
        (isstring(value) && isscalar(value))
    value = char(value);
else
    value = '';
end
end

function value = issue(severity, code, message, fieldPath, filePath)
value = struct('severity', severity, 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', 0, 'file_path', filePath);
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end
