function [result, issues] = c2837x_block_commit_preview_snapshot( ...
        snapshot, project, candidates, dependencies, options)
%C2837X_BLOCK_COMMIT_PREVIEW_SNAPSHOT Commit an approved preview in order.

result = empty_result();
issues = empty_issues();
if nargin < 5
    optionsProvided = false;
else
    optionsProvided = true;
end

try
    [snapshotValid, snapshotIssues] = ...
        c2837x_block_validate_preview_snapshot( ...
        snapshot, project, candidates, dependencies);
catch
    snapshotValid = false;
    snapshotIssues = make_issue('SNAPSHOT_INVALID', ...
        'Snapshot validation could not inspect the supplied inputs.', ...
        'snapshot', 0, '');
end
issues = [issues snapshotIssues];
if ~snapshotValid || has_errors(snapshotIssues)
    if valid_target_models(snapshot, candidates)
        issues = [issues verify_targets(snapshot.target_states, candidates)];
    end
    return;
end

result = initialize_result(snapshot);
try
    actionIssues = c2837x_block_validate_candidate_actions( ...
        snapshot.comparison_baseline);
catch
    actionIssues = make_issue('CANDIDATE_ACTION_INVALID', ...
        'Candidate actions could not be validated.', ...
        'snapshot.comparison_baseline', 0, '');
end
issues = [issues actionIssues];
if has_errors(actionIssues)
    result = finalize_result(result);
    return;
end

targetIssues = verify_targets(snapshot.target_states, candidates);
issues = [issues targetIssues];
if has_errors(targetIssues)
    result = finalize_result(result);
    return;
end
if optionsProvided
    [optionsValid, fileWriter] = parse_options(options);
    if ~optionsValid
        issues(end + 1) = make_issue('COMMIT_OPTIONS_INVALID', ...
            'Options must contain only a scalar file_writer function handle.', ...
            'options', 0, '');
        result = finalize_result(result);
        return;
    end
else
    fileWriter = @c2837x_block_commit_file_bytes;
end

directories = required_directories(snapshot.comparison_baseline);
result.phase = 'directory_creation';
for index = 1:numel(directories)
    directory = directories{index};
    if isfolder(directory)
        continue;
    end
    missingDirectories = missing_directory_chain(directory);
    if isfile(directory)
        success = false;
    else
        try
            [success, ~, ~] = mkdir(directory);
        catch
            success = false;
        end
    end
    for createdIndex = 1:numel(missingDirectories)
        if isfolder(missingDirectories{createdIndex})
            result.created_directories{end + 1} = ...
                missingDirectories{createdIndex};
        end
    end
    if ~success || ~isfolder(directory)
        issues(end + 1) = make_issue( ...
            'COMMIT_DIRECTORY_CREATE_FAILED', ...
            'A required target directory could not be created.', ...
            'snapshot.candidates', 0, directory); %#ok<AGROW>
        result = failed_result(result, snapshot.target_states);
        return;
    end
end

try
    [finalSnapshotValid, finalSnapshotIssues] = ...
        c2837x_block_validate_preview_snapshot( ...
        snapshot, project, candidates, dependencies);
catch
    finalSnapshotValid = false;
    finalSnapshotIssues = make_issue('SNAPSHOT_INVALID', ...
        'Snapshot validation could not inspect the supplied inputs.', ...
        'snapshot', 0, '');
end
issues = append_new_errors(issues, finalSnapshotIssues);
finalTargetIssues = verify_targets(snapshot.target_states, candidates);
issues = [issues finalTargetIssues];
if ~finalSnapshotValid || has_errors(finalSnapshotIssues) || ...
        has_errors(finalTargetIssues)
    result = failed_result(result, snapshot.target_states);
    return;
end

result.phase = 'file_commit';
for index = 1:numel(snapshot.candidates)
    comparison = snapshot.comparison_baseline(index);
    action = comparison.selected_action;
    if strcmp(action, 'skip')
        result.files(index).outcome = 'skipped';
        continue;
    elseif strcmp(action, 'keep')
        result.files(index).outcome = 'kept';
        continue;
    end

    targetPath = snapshot.candidates(index).target_path;
    try
        writeResult = fileWriter(targetPath, ...
            snapshot.candidates(index).content_bytes, action, ...
            snapshot.target_states(index));
    catch
        writeResult = [];
        failureCode = 'COMMIT_FILE_WRITER_FAILED';
        failureMessage = 'The file writer failed.';
    end
    if exist('failureCode', 'var')
        [result, issues] = record_failure(result, issues, index, ...
            failureCode, failureMessage, snapshot.target_states);
        clear failureCode failureMessage
        return;
    end
    if ~valid_write_result(writeResult)
        [result, issues] = record_failure(result, issues, index, ...
            'COMMIT_FILE_WRITER_RESULT_INVALID', ...
            'The file writer returned an invalid result.', ...
            snapshot.target_states);
        return;
    end
    if ~isempty(writeResult.temporary_path) && ...
            isfile(writeResult.temporary_path)
        result.temporary_files_remaining{end + 1} = ...
            writeResult.temporary_path;
    end
    if ~writeResult.success
        [result, issues] = record_failure(result, issues, index, ...
            writeResult.code, stable_writer_message(writeResult.code), ...
            snapshot.target_states);
        return;
    end
    [finalBytes, finalCode] = read_bytes(targetPath);
    if ~isempty(finalCode) || ...
            ~isequal(finalBytes, snapshot.candidates(index).content_bytes)
        [result, issues] = record_failure(result, issues, index, ...
            'COMMIT_POST_WRITE_VERIFY_FAILED', ...
            'The final target did not match the candidate bytes.', ...
            snapshot.target_states);
        return;
    end
    if strcmp(action, 'create')
        result.files(index).outcome = 'created';
    else
        result.files(index).outcome = 'replaced';
    end
end

result.success = true;
result.status = 'completed';
result.phase = 'complete';
result = finalize_result(result);
end

function result = initialize_result(snapshot)
result = empty_result();
prototype = empty_file_result();
result.files = repmat(prototype, 1, numel(snapshot.candidates));
for index = 1:numel(snapshot.candidates)
    candidate = snapshot.candidates(index);
    result.files(index) = struct( ...
        'target_path', candidate.target_path, ...
        'category', candidate.category, ...
        'owner', candidate.owner, ...
        'instance_index', candidate.instance_index, ...
        'selected_action', snapshot.comparison_baseline(index).selected_action, ...
        'outcome', 'not_attempted', 'code', '', 'message', '');
end
result.not_attempted_count = double(numel(result.files));
result.dsp_root = snapshot.output_paths.dsp_root;
result.sfun_root = snapshot.output_paths.sfun_root;
end

function [result, issues] = record_failure(result, issues, index, ...
        code, message, targetStates)
result.files(index).outcome = 'failed';
result.files(index).code = code;
result.files(index).message = message;
issues(end + 1) = make_issue(code, message, ...
    sprintf('snapshot.candidates(%u)', index), ...
    result.files(index).instance_index, result.files(index).target_path);
result = failed_result(result, targetStates);
end

function result = failed_result(result, targetStates)
result.success = false;
if has_side_effects(result, targetStates)
    result.status = 'partial_failure';
else
    result.status = 'failed';
end
result = finalize_result(result);
end

function tf = has_side_effects(result, targetStates)
tf = ~isempty(result.created_directories) || ...
    ~isempty(result.temporary_files_remaining);
for index = 1:numel(targetStates)
    if tf
        return;
    end
    [matches, ~] = target_matches(targetStates(index));
    tf = ~matches;
end
end

function issues = verify_targets(states, candidates)
issues = empty_issues();
for index = 1:numel(states)
    [matches, code] = target_matches(states(index));
    if matches
        continue;
    end
    if strcmp(code, 'COMMIT_TARGET_UNREADABLE')
        message = 'The target file could not be opened for reading.';
    elseif strcmp(code, 'COMMIT_TARGET_READ_FAILED')
        message = 'The target file could not be read completely.';
    else
        message = 'The target no longer matches the preview state.';
    end
    issues(end + 1) = make_issue(code, message, ...
        sprintf('snapshot.target_states(%u)', index), ...
        candidates(index).instance_index, states(index).target_path); %#ok<AGROW>
end
end

function [matches, code] = target_matches(state)
matches = false;
code = 'COMMIT_TARGET_CHANGED';
if strcmp(state.state, 'missing')
    matches = ~isfile(state.target_path) && ~isfolder(state.target_path);
    return;
end
if isfolder(state.target_path) || ~isfile(state.target_path)
    return;
end
[bytes, code] = read_bytes(state.target_path);
if ~isempty(code)
    return;
end
matches = numel(bytes) == state.content_size_octets && ...
    isequal(bytes, state.content_bytes);
if ~matches
    code = 'COMMIT_TARGET_CHANGED';
end
end

function [bytes, code] = read_bytes(path)
bytes = zeros(1, 0, 'uint8');
code = '';
fileID = -1;
try
    fileID = fopen(path, 'rb');
catch
end
if fileID < 0
    code = 'COMMIT_TARGET_UNREADABLE';
    return;
end
try
    bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
    [~, errorNumber] = ferror(fileID);
    closed = fclose(fileID) == 0;
    fileID = -1;
    if (errorNumber ~= 0 && errorNumber ~= -4) || ~closed
        bytes = zeros(1, 0, 'uint8');
        code = 'COMMIT_TARGET_READ_FAILED';
    end
catch
    if fileID >= 0
        try
            fclose(fileID);
        catch
        end
    end
    bytes = zeros(1, 0, 'uint8');
    code = 'COMMIT_TARGET_READ_FAILED';
end
end

function directories = required_directories(comparisons)
directories = cell(1, 0);
for index = 1:numel(comparisons)
    if ~any(strcmp(comparisons(index).selected_action, {'create', 'replace'}))
        continue;
    end
    parent = fileparts(comparisons(index).target_path);
    if ~any(cellfun(@(value) paths_equal(value, parent), directories))
        directories{end + 1} = parent; %#ok<AGROW>
    end
end
end

function directories = missing_directory_chain(directory)
directories = cell(1, 0);
while ~isempty(directory) && ~isfolder(directory)
    directories = [{directory} directories]; %#ok<AGROW>
    parent = fileparts(directory);
    if paths_equal(parent, directory)
        break;
    end
    directory = parent;
end
end

function tf = paths_equal(first, second)
if ispc
    tf = strcmpi(first, second);
else
    tf = strcmp(first, second);
end
end

function [valid, writer] = parse_options(options)
writer = [];
valid = isstruct(options) && isscalar(options) && ...
    isequal(fieldnames(options), {'file_writer'}) && ...
    isa(options.file_writer, 'function_handle') && ...
    isscalar(options.file_writer);
if valid
    writer = options.file_writer;
end
end

function tf = valid_write_result(value)
required = {'success', 'code', 'message', 'temporary_path'};
tf = isstruct(value) && isscalar(value) && ...
    isequal(sort(fieldnames(value)), sort(required(:)));
if ~tf
    return;
end
[codeValid, code] = text_value(value.code, true);
[messageValid, message] = text_value(value.message, true);
[pathValid, temporaryPath] = text_value(value.temporary_path, true);
tf = islogical(value.success) && isscalar(value.success) && ...
    codeValid && messageValid && pathValid;
if tf && value.success
    tf = isempty(code) && isempty(message) && isempty(temporaryPath);
elseif tf
    tf = ~isempty(code) && ~isempty(message);
end
end

function message = stable_writer_message(code)
switch code
    case 'COMMIT_TARGET_CHANGED'
        message = 'The target no longer matches the preview state.';
    case 'COMMIT_TARGET_UNREADABLE'
        message = 'The target file could not be opened for reading.';
    case 'COMMIT_TARGET_READ_FAILED'
        message = 'The target file could not be read completely.';
    case 'COMMIT_PARENT_DIRECTORY_MISSING'
        message = 'The target parent directory does not exist.';
    case 'COMMIT_TEMP_PATH_FAILED'
        message = 'A same-directory temporary path could not be created.';
    case 'COMMIT_TEMP_OPEN_FAILED'
        message = 'The same-directory temporary file could not be opened.';
    case 'COMMIT_TEMP_WRITE_FAILED'
        message = 'The temporary file could not be written completely.';
    case 'COMMIT_TEMP_VERIFY_FAILED'
        message = 'The temporary file did not match the candidate bytes.';
    case 'COMMIT_TARGET_CREATE_FAILED'
        message = 'The temporary file could not be moved to the new target.';
    case 'COMMIT_TARGET_REPLACE_FAILED'
        message = 'The temporary file could not replace the target.';
    case 'COMMIT_POST_WRITE_VERIFY_FAILED'
        message = 'The final target did not match the candidate bytes.';
    case 'COMMIT_TEMP_CLEANUP_FAILED'
        message = 'The temporary file could not be removed after failure.';
    otherwise
        message = 'The file writer reported a commit failure.';
end
end

function issues = append_new_errors(issues, additions)
for index = 1:numel(additions)
    if ~strcmp(additions(index).severity, 'Error')
        continue;
    end
    duplicate = false;
    for existing = 1:numel(issues)
        if isequaln(issues(existing), additions(index))
            duplicate = true;
            break;
        end
    end
    if ~duplicate
        issues(end + 1) = additions(index); %#ok<AGROW>
    end
end
end

function tf = valid_target_models(snapshot, candidates)
tf = isstruct(snapshot) && isscalar(snapshot) && ...
    isfield(snapshot, 'target_states') && isstruct(snapshot.target_states) && ...
    isstruct(candidates) && numel(snapshot.target_states) == numel(candidates) && ...
    all(isfield(snapshot.target_states, ...
    {'target_path', 'state', 'content_bytes', 'content_size_octets'})) && ...
    all(isfield(candidates, 'instance_index'));
end

function result = finalize_result(result)
outcomes = {result.files.outcome};
result.created_count = double(sum(strcmp(outcomes, 'created')));
result.replaced_count = double(sum(strcmp(outcomes, 'replaced')));
result.skipped_count = double(sum(strcmp(outcomes, 'skipped')));
result.kept_count = double(sum(strcmp(outcomes, 'kept')));
result.failed_count = double(sum(strcmp(outcomes, 'failed')));
result.not_attempted_count = double(sum(strcmp(outcomes, 'not_attempted')));
end

function result = empty_result()
result = struct('success', false, 'status', 'blocked', ...
    'phase', 'preflight', 'files', repmat(empty_file_result(), 1, 0), ...
    'created_count', 0, 'replaced_count', 0, 'skipped_count', 0, ...
    'kept_count', 0, 'failed_count', 0, 'not_attempted_count', 0, ...
    'created_directories', {{}}, 'temporary_files_remaining', {{}}, ...
    'dsp_root', '', 'sfun_root', '');
end

function value = empty_file_result()
value = struct('target_path', '', 'category', '', 'owner', '', ...
    'instance_index', 0, 'selected_action', '', ...
    'outcome', 'not_attempted', 'code', '', 'message', '');
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

function tf = has_errors(issues)
tf = any(strcmp({issues.severity}, 'Error'));
end

function [valid, value] = text_value(rawValue, allowEmpty)
valid = (ischar(rawValue) && (isrow(rawValue) || isempty(rawValue))) || ...
    (isstring(rawValue) && isscalar(rawValue) && ~ismissing(rawValue));
if valid
    value = char(rawValue);
    valid = allowEmpty || ~isempty(value);
else
    value = '';
end
end
