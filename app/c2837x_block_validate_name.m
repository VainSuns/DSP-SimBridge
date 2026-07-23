function [valid, msg] = c2837x_block_validate_name(name, existing_names)
%C2837X_BLOCK_VALIDATE_NAME Validate an internal or I/O C identifier.
%
%   [valid, msg] = c2837x_block_validate_name(name, existing_names)
%
%   Checks:
%     1. Non-empty
%     2. ASCII letter start, then ASCII letters, digits, or underscores
%     3. Not a C keyword
%     4. Not an implementation-reserved identifier
%     5. Not a generated-code internal symbol
%     6. Not duplicate of existing_names

    valid = true;
    msg = '';

    if ~(ischar(name) && isrow(name)) && ...
            ~(isstring(name) && isscalar(name))
        valid = false;
        msg = 'Name must be a character row vector or scalar string.';
        return;
    end
    name = char(name);
    if isempty(name)
        valid = false;
        msg = 'Name is empty.';
        return;
    end

    % --- Valid C identifier ---
    if isempty(regexp(name, '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
        valid = false;
        msg = sprintf('"%s" is not a valid C identifier.', name);
        return;
    end

    % --- C keywords (C99/C11) ---
    c_keywords = { ...
        'auto', 'break', 'case', 'char', 'const', 'continue', 'default', ...
        'do', 'double', 'else', 'enum', 'extern', 'float', 'for', 'goto', ...
        'if', 'inline', 'int', 'long', 'register', 'restrict', 'return', ...
        'short', 'signed', 'sizeof', 'static', 'struct', 'switch', ...
        'typedef', 'union', 'unsigned', 'void', 'volatile', 'while', ...
        '_Bool', '_Complex', '_Imaginary' ...
    };
    if any(strcmpi(name, c_keywords))
        valid = false;
        msg = sprintf('"%s" is a C keyword.', name);
        return;
    end

    % --- Generated-code and public API symbols ---
    reserved_symbols = { ...
        'c2837x_block_input', 'c2837x_block_output', ...
        'C2837xBlock_InputData', 'C2837xBlock_OutputData', ...
        'C2837xBlock_OnSimStart', 'C2837xBlock_OnStep', ...
        'C2837xBlock_OnSimStop', 'c2837x_block_unpack_input_payload', ...
        'c2837x_block_pack_output_payload', 'step_index', ...
        'payload_words', 'offset', 'C2837xBlock', 'C2837xBlock_Error', ...
        'C2837xBlock_PlatformResult', ...
        'C2837xBlock_PlatformInit', 'C2837xBlock_Init', ...
        'C2837xBlock_Run', 'C2837xBlock_GetLastError' ...
    };
    if any(strcmpi(name, reserved_symbols))
        valid = false;
        msg = sprintf('"%s" conflicts with generated code internal symbol.', name);
        return;
    end

    % --- C2837X_ prefix reserved ---
    if numel(name) >= 7 && strncmpi(name, 'C2837X_', 7)
        valid = false;
        msg = sprintf('"%s" uses reserved prefix C2837X_.', name);
        return;
    end

    % --- Duplicate check ---
    if nargin >= 2 && ~isempty(existing_names)
        if any(strcmpi(name, existing_names))
            valid = false;
            msg = sprintf('"%s" is duplicate.', name);
            return;
        end
    end
end
