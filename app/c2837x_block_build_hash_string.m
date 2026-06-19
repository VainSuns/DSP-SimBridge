function [str, hash] = c2837x_block_build_hash_string(config)
%C2837X_BLOCK_BUILD_HASH_STRING  Build canonical string for config_hash.
%
%   [str, hash] = c2837x_block_build_hash_string(config)
%
%   Returns:
%     str  - canonical UTF-8 string (for display and CRC32 input)
%     hash - uint32 config_hash value
%
%   Canonical string format per spec §6.3:
%     protocol=0x0001
%     abi=eabi
%     endianness=little
%     dsp_ip=...
%     gateway=...
%     subnet=...
%     tcp_port=...
%     socket_num=...
%     sample_time_sec=...
%     input_count=N
%     input[i].name=...;type=...;dim=...
%     output_count=N
%     output[i].name=...;type=...;dim=...
%     input_data_size_bytes=...
%     output_data_size_bytes=...
%     input_payload_size_bytes=...
%     output_payload_size_bytes=...
%     double_mode=...

    lines = {};

    % Protocol
    lines{end+1} = sprintf('protocol=0x%04X', config.protocol_version);

    % ABI
    lines{end+1} = sprintf('abi=%s', lower(config.abi));

    % Endianness (fixed for this project)
    lines{end+1} = 'endianness=little';

    % Network
    lines{end+1} = sprintf('dsp_ip=%s', config.dsp_ip);
    lines{end+1} = sprintf('gateway=%s', config.gateway);
    lines{end+1} = sprintf('subnet=%s', config.subnet);
    lines{end+1} = sprintf('tcp_port=%d', config.tcp_port);
    lines{end+1} = sprintf('socket_num=%d', config.socket_num);

    % Sample time (locale-independent)
    lines{end+1} = sprintf('sample_time_sec=%.17g', config.sample_time_sec);

    % Inputs
    n_in = numel(config.inputs);
    lines{end+1} = sprintf('input_count=%d', n_in);
    for i = 1:n_in
        v = config.inputs(i);
        lines{end+1} = sprintf('input[%d].name=%s;type=%s;dim=%d', ...
                               i-1, v.name, v.type, v.dim);
    end

    % Outputs
    n_out = numel(config.outputs);
    lines{end+1} = sprintf('output_count=%d', n_out);
    for i = 1:n_out
        v = config.outputs(i);
        lines{end+1} = sprintf('output[%d].name=%s;type=%s;dim=%d', ...
                               i-1, v.name, v.type, v.dim);
    end

    % Sizes
    input_data_bytes = compute_data_size_bytes(config.inputs);
    output_data_bytes = compute_data_size_bytes(config.outputs);
    input_payload_bytes = 4 + input_data_bytes;
    output_payload_bytes = 4 + output_data_bytes;

    lines{end+1} = sprintf('input_data_size_bytes=%d', input_data_bytes);
    lines{end+1} = sprintf('output_data_size_bytes=%d', output_data_bytes);
    lines{end+1} = sprintf('input_payload_size_bytes=%d', input_payload_bytes);
    lines{end+1} = sprintf('output_payload_size_bytes=%d', output_payload_bytes);

    % Double mode
    if strcmpi(config.double_mode, 'eabi64')
        lines{end+1} = 'double_mode=eabi64';
    else
        lines{end+1} = 'double_mode=disabled';
    end

    str = strjoin(lines, '\n');
    hash = c2837x_block_crc32(uint8(str));
end

function bytes = compute_data_size_bytes(vars)
    bytes = 0;
    for i = 1:numel(vars)
        bytes = bytes + type_wire_bytes(vars(i).type) * vars(i).dim;
    end
end

function b = type_wire_bytes(t)
    switch t
        case {'int16', 'uint16'}
            b = 2;
        case {'int32', 'uint32', 'single'}
            b = 4;
        case 'double'
            b = 8;
        otherwise
            error('Unknown type: %s', t);
    end
end
