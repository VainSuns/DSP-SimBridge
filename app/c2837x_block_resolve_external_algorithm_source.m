function source = c2837x_block_resolve_external_algorithm_source(sourcePath)
%C2837X_BLOCK_RESOLVE_EXTERNAL_ALGORITHM_SOURCE Resolve and read a C source.

if ~((ischar(sourcePath) && isrow(sourcePath)) || ...
        (isstring(sourcePath) && isscalar(sourcePath) && ~ismissing(sourcePath)))
    fail('InvalidPath', 'External algorithm source path must be scalar text.');
end
sourcePath = char(sourcePath);
javaFile = java.io.File(sourcePath);
if ~javaFile.isAbsolute()
    fail('InvalidPath', 'External algorithm source path must be canonical absolute text.');
end
javaPath = javaFile.toPath();
try
    if java.nio.file.Files.isSymbolicLink(javaPath)
        fail('SymbolicLink', 'External algorithm source must not be a symbolic link.');
    end
catch cause
    if startsWith(cause.identifier, 'C2837xBlock:AlgorithmSource:')
        rethrow(cause);
    end
    fail('IdentityUnknown', 'External algorithm source identity could not be determined.');
end
try
    normalizedPath = c2837x_block_normalize_absolute_path(sourcePath);
catch
    fail('InvalidPath', 'External algorithm source path must be canonical absolute text.');
end
if isempty(normalizedPath) || ~strcmp(sourcePath, normalizedPath)
    fail('InvalidPath', 'External algorithm source path must be canonical absolute text.');
end

if isfolder(sourcePath)
    fail('IsDirectory', 'External algorithm source must not be a directory.');
end
try
    exists = java.nio.file.Files.exists(javaPath, ...
        javaArray('java.nio.file.LinkOption', 0));
catch
    fail('IdentityUnknown', 'External algorithm source identity could not be determined.');
end
if ~exists
    fail('Missing', 'External algorithm source does not exist.');
end
try
    if ~java.nio.file.Files.isRegularFile(javaPath, ...
            javaArray('java.nio.file.LinkOption', 0))
        fail('NotRegularFile', 'External algorithm source must be a regular file.');
    end
catch cause
    if startsWith(cause.identifier, 'C2837xBlock:AlgorithmSource:')
        rethrow(cause);
    end
    fail('IdentityUnknown', 'External algorithm source identity could not be determined.');
end

[folder, name, extension] = fileparts(sourcePath);
if ~strcmp(extension, '.c')
    if ~strcmpi(extension, '.c')
        fail('ExtensionInvalid', 'External algorithm source extension must be .c.');
    end
    literalPath = fullfile(folder, [name '.c']);
    if ~isfile(literalPath)
        fail('ExtensionInvalid', ...
            'External algorithm source extension is not .c under current filesystem semantics.');
    end
    try
        literalJavaPath = java.io.File(literalPath).toPath();
        if ~java.nio.file.Files.isSameFile(javaPath, literalJavaPath)
            fail('ExtensionInvalid', ...
                'External algorithm source extension is not .c under current filesystem semantics.');
        end
    catch cause
        if startsWith(cause.identifier, 'C2837xBlock:AlgorithmSource:')
            rethrow(cause);
        end
        fail('IdentityUnknown', 'External algorithm source identity could not be determined.');
    end
end
try
    readable = java.nio.file.Files.isReadable(javaPath);
catch
    readable = false;
end
if ~readable
    fail('Unreadable', 'External algorithm source is not readable.');
end

fileID = fopen(sourcePath, 'rb');
if fileID < 0
    fail('Unreadable', 'External algorithm source could not be opened for reading.');
end
cleanup = onCleanup(@() fclose(fileID));
try
    bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
    [~, errorNumber] = ferror(fileID);
    if errorNumber ~= 0 && errorNumber ~= -4
        fail('ReadFailed', 'External algorithm source could not be read completely.');
    end
catch cause
    if startsWith(cause.identifier, 'C2837xBlock:AlgorithmSource:')
        rethrow(cause);
    end
    fail('ReadFailed', 'External algorithm source could not be read completely.');
end
clear cleanup
source = struct('source_path', sourcePath, 'content_bytes', bytes);
end

function fail(code, message)
error(['C2837xBlock:AlgorithmSource:' code], '%s', message);
end
