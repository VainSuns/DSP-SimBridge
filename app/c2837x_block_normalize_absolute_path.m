function normalized = c2837x_block_normalize_absolute_path(rawPath)
%C2837X_BLOCK_NORMALIZE_ABSOLUTE_PATH Canonicalize an absolute path.

if ~(ischar(rawPath) && (isrow(rawPath) || isempty(rawPath))) && ...
        ~(isstring(rawPath) && isscalar(rawPath))
    error('C2837xBlock:Path:InvalidText', ...
        'Path must be a character row vector or scalar string.');
end
rawPath = char(rawPath);
if isempty(rawPath)
    normalized = '';
    return;
end
if rawPath(1) == '~' || ~isempty(regexp(rawPath, ...
        '(%[^%]+%|\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*)', 'once'))
    error('C2837xBlock:Path:PlaceholderNotAllowed', ...
        'Environment variables, placeholders, and ~ are not allowed.');
end

try
    file = java.io.File(rawPath);
    if ~file.isAbsolute()
        error('C2837xBlock:Path:RelativeNotAllowed', ...
            'Path must be absolute.');
    end
    normalized = char(file.getCanonicalPath());
catch cause
    if startsWith(cause.identifier, 'C2837xBlock:Path:')
        rethrow(cause);
    end
    failure = MException('C2837xBlock:Path:NormalizationFailed', ...
        'Path could not be reliably canonicalized: %s', rawPath);
    throwAsCaller(addCause(failure, cause));
end
end
