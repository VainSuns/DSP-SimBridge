function result = c2837x_block_commit_file_bytes( ...
        targetPath, contentBytes, action, expectedTargetState)
%C2837X_BLOCK_COMMIT_FILE_BYTES Safely commit one candidate byte vector.

result = write_result(false, 'COMMIT_WRITE_INPUT_INVALID', ...
    'Commit writer inputs do not use the fixed model.', '');
[valid, targetPath, action] = valid_inputs( ...
    targetPath, contentBytes, action, expectedTargetState);
if ~valid
    return;
end

parentPath = fileparts(targetPath);
if ~isfolder(parentPath)
    result = write_result(false, 'COMMIT_PARENT_DIRECTORY_MISSING', ...
        'The target parent directory does not exist.', '');
    return;
end
[matches, code] = target_matches(expectedTargetState);
if ~matches
    result = target_failure(code);
    return;
end

try
    temporaryPath = tempname(parentPath);
catch
    result = write_result(false, 'COMMIT_TEMP_PATH_FAILED', ...
        'A same-directory temporary path could not be created.', '');
    return;
end
if ~strcmp(fileparts(temporaryPath), parentPath)
    result = write_result(false, 'COMMIT_TEMP_PATH_FAILED', ...
        'A same-directory temporary path could not be created.', '');
    return;
end

[written, code] = write_temporary(temporaryPath, contentBytes);
if ~written
    result = fail_and_cleanup(code, temporaryPath);
    return;
end
[temporaryBytes, code] = read_bytes(temporaryPath, ...
    'COMMIT_TEMP_VERIFY_FAILED', 'COMMIT_TEMP_VERIFY_FAILED');
if ~isempty(code) || ~isequal(temporaryBytes, contentBytes)
    result = fail_and_cleanup('COMMIT_TEMP_VERIFY_FAILED', temporaryPath);
    return;
end
[matches, code] = target_matches(expectedTargetState);
if ~matches
    result = fail_and_cleanup(code, temporaryPath);
    return;
end

try
    if strcmp(action, 'create')
        [moved, ~] = movefile(temporaryPath, targetPath);
        moveCode = 'COMMIT_TARGET_CREATE_FAILED';
    else
        [moved, ~] = movefile(temporaryPath, targetPath, 'f');
        moveCode = 'COMMIT_TARGET_REPLACE_FAILED';
    end
catch
    moved = false;
end
if ~moved
    [stillMatches, stateCode] = target_matches(expectedTargetState);
    if ~stillMatches && strcmp(stateCode, 'COMMIT_TARGET_CHANGED')
        moveCode = stateCode;
    end
    result = fail_and_cleanup(moveCode, temporaryPath);
    return;
end

[finalBytes, code] = read_bytes(targetPath, ...
    'COMMIT_POST_WRITE_VERIFY_FAILED', 'COMMIT_POST_WRITE_VERIFY_FAILED');
if ~isempty(code) || ~isequal(finalBytes, contentBytes)
    result = write_result(false, 'COMMIT_POST_WRITE_VERIFY_FAILED', ...
        error_message('COMMIT_POST_WRITE_VERIFY_FAILED'), '');
    return;
end
result = write_result(true, '', '', '');
end

function [valid, targetPath, action] = valid_inputs( ...
        targetPath, contentBytes, action, expected)
[pathValid, targetPath] = text_value(targetPath, false);
[actionValid, action] = text_value(action, false);
required = {'target_path', 'state', 'content_bytes', 'content_size_octets'};
valid = pathValid && canonical_path(targetPath) && ...
    isa(contentBytes, 'uint8') && ismatrix(contentBytes) && ...
    size(contentBytes, 1) == 1 && actionValid && ...
    any(strcmp(action, {'create', 'replace'})) && ...
    isstruct(expected) && isscalar(expected) && ...
    isequal(sort(fieldnames(expected)), sort(required(:)));
if ~valid
    return;
end
[expectedPathValid, expectedPath] = text_value(expected.target_path, false);
[stateValid, state] = text_value(expected.state, false);
bytesValid = isa(expected.content_bytes, 'uint8') && ...
    ismatrix(expected.content_bytes) && size(expected.content_bytes, 1) == 1;
sizeValid = valid_integer(expected.content_size_octets) && ...
    expected.content_size_octets == numel(expected.content_bytes);
valid = expectedPathValid && canonical_path(expectedPath) && ...
    strcmp(targetPath, expectedPath) && stateValid && ...
    any(strcmp(state, {'missing', 'file'})) && bytesValid && sizeValid && ...
    ((strcmp(action, 'create') && strcmp(state, 'missing')) || ...
    (strcmp(action, 'replace') && strcmp(state, 'file')));
if valid && strcmp(state, 'missing')
    valid = isempty(expected.content_bytes) && expected.content_size_octets == 0;
end
end

function [matches, code] = target_matches(expected)
matches = false;
code = 'COMMIT_TARGET_CHANGED';
path = expected.target_path;
if strcmp(expected.state, 'missing')
    matches = ~isfile(path) && ~isfolder(path);
    return;
end
if isfolder(path) || ~isfile(path)
    return;
end
[bytes, code] = read_bytes(path, ...
    'COMMIT_TARGET_UNREADABLE', 'COMMIT_TARGET_READ_FAILED');
if ~isempty(code)
    return;
end
matches = numel(bytes) == expected.content_size_octets && ...
    isequal(bytes, expected.content_bytes);
if ~matches
    code = 'COMMIT_TARGET_CHANGED';
end
end

function [success, code] = write_temporary(path, bytes)
success = false;
code = 'COMMIT_TEMP_OPEN_FAILED';
fileID = -1;
try
    fileID = fopen(path, 'wb');
catch
end
if fileID < 0
    return;
end
code = 'COMMIT_TEMP_WRITE_FAILED';
try
    written = fwrite(fileID, bytes, 'uint8');
    [~, errorNumber] = ferror(fileID);
    closed = fclose(fileID) == 0;
    fileID = -1;
    success = written == numel(bytes) && ...
        (errorNumber == 0 || errorNumber == -4) && closed;
catch
    if fileID >= 0
        try
            fclose(fileID);
        catch
        end
    end
end
end

function result = fail_and_cleanup(code, temporaryPath)
remaining = temporaryPath;
if isfile(temporaryPath)
    try
        delete(temporaryPath);
    catch
    end
end
if ~isfile(temporaryPath)
    remaining = '';
elseif ~strcmp(code, 'COMMIT_TEMP_CLEANUP_FAILED')
    code = 'COMMIT_TEMP_CLEANUP_FAILED';
end
result = write_result(false, code, error_message(code), remaining);
end

function [bytes, code] = read_bytes(path, unreadableCode, readCode)
bytes = zeros(1, 0, 'uint8');
code = '';
fileID = -1;
try
    fileID = fopen(path, 'rb');
catch
end
if fileID < 0
    code = unreadableCode;
    return;
end
try
    bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
    [~, errorNumber] = ferror(fileID);
    closed = fclose(fileID) == 0;
    fileID = -1;
    if (errorNumber ~= 0 && errorNumber ~= -4) || ~closed
        bytes = zeros(1, 0, 'uint8');
        code = readCode;
    end
catch
    if fileID >= 0
        try
            fclose(fileID);
        catch
        end
    end
    bytes = zeros(1, 0, 'uint8');
    code = readCode;
end
end

function result = target_failure(code)
result = write_result(false, code, error_message(code), '');
end

function message = error_message(code)
switch code
    case 'COMMIT_TARGET_CHANGED'
        message = 'The target no longer matches the preview state.';
    case 'COMMIT_TARGET_UNREADABLE'
        message = 'The target file could not be opened for reading.';
    case 'COMMIT_TARGET_READ_FAILED'
        message = 'The target file could not be read completely.';
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
        message = 'The file commit failed.';
end
end

function result = write_result(success, code, message, temporaryPath)
result = struct('success', success, 'code', code, 'message', message, ...
    'temporary_path', temporaryPath);
end

function tf = canonical_path(path)
tf = false;
try
    tf = ~isempty(path) && ...
        strcmp(path, c2837x_block_normalize_absolute_path(path));
catch
end
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

function tf = valid_integer(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value == fix(value);
end
