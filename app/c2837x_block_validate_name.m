function [valid, msg] = c2837x_block_validate_name(name, existing_names)
%C2837X_BLOCK_VALIDATE_NAME  Validate a variable name for generated C code.
%
%   [valid, msg] = c2837x_block_validate_name(name, existing_names)
%
%   Checks:
%     1. Non-empty
%     2. Valid C identifier (letter/underscore start, alphanumeric/underscore body)
%     3. Not a C keyword
%     4. Not a reserved identifier (starts with _ or double underscore)
%     5. Not a generated-code internal symbol
%     6. Not duplicate of existing_names

    valid = true;
    msg = '';

    % --- Non-empty ---
    if isempty(strtrim(name))
        valid = false;
        msg = 'Variable name is empty.';
        return;
    end

    name = strtrim(name);

    % --- Valid C identifier ---
    if isempty(regexp(name, '^[A-Za-z_][A-Za-z0-9_]*$', 'once'))
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

    % --- Reserved identifiers ---
    % Starts with underscore followed by uppercase or another underscore
    if numel(name) >= 2 && name(1) == '_' && (isupper(name(2)) || name(2) == '_')
        valid = false;
        msg = sprintf('"%s" is a reserved identifier (starts with _%s).', ...
                       name, name(2));
        return;
    end
    % Single underscore
    if strcmp(name, '_')
        valid = false;
        msg = '"_" is a reserved identifier.';
        return;
    end

    % --- Generated-code internal symbols ---
    internal_symbols = { ...
        'c2837x_block_input', 'c2837x_block_output', ...
        'C2837xBlock_InputData', 'C2837xBlock_OutputData', ...
        'C2837xBlock_OnSimStart', 'C2837xBlock_OnStep', ...
        'C2837xBlock_OnSimStop', 'c2837x_block_unpack_input_payload', ...
        'c2837x_block_pack_output_payload', 'step_index', ...
        'payload_words', 'offset' ...
    };
    if any(strcmp(name, internal_symbols))
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
        if any(strcmp(name, existing_names))
            valid = false;
            msg = sprintf('"%s" is duplicate.', name);
            return;
        end
    end
end

function tf = isupper(c)
    tf = (c >= 'A') && (c <= 'Z');
end
