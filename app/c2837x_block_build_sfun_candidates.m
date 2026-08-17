function [candidates, dependencies, issues] = ...
        c2837x_block_build_sfun_candidates(project)
%C2837X_BLOCK_BUILD_SFUN_CANDIDATES Build deterministic S4-05 candidates.

model = c2837x_block_build_sfun_output_model(project);
rendered = c2837x_block_render_sfun_files(project);
pcRendered = c2837x_block_render_pc_files(project);
buildRendered = c2837x_block_render_sfun_build_files(project);
prototype = struct('target_path', '', 'category', '', 'owner', '', ...
    'instance_index', 0, 'content_bytes', zeros(1, 0, 'uint8'));
definitions = repmat(prototype, 1, numel(model.files));
for index = 1:numel(model.files)
    file = model.files(index);
    result = rendered(file.instance_index);
    pcResult = pcRendered(file.instance_index);
    buildResult = buildRendered(file.instance_index);
    suffix = extractAfter(file.relative_path, '/');
    switch suffix
        case [result.internal_name '_sfun.c']
            bytes = result.sfun_source_bytes;
        case [result.internal_name '_sfun.h']
            bytes = result.sfun_header_bytes;
        case [result.internal_name '_sfun_io.c']
            bytes = result.io_source_bytes;
        case [result.internal_name '_sfun_config.h']
            bytes = result.config_header_bytes;
        case [result.internal_name '_sfun_user_config.h']
            bytes = buildResult.user_config_bytes;
        case [result.internal_name '_pc_error.h']
            bytes = pcResult.pc_error_header_bytes;
        case [result.internal_name '_pc_socket.c']
            bytes = pcResult.socket_source_bytes;
        case [result.internal_name '_pc_socket.h']
            bytes = pcResult.socket_header_bytes;
        case [result.internal_name '_protocol.c']
            bytes = pcResult.protocol_source_bytes;
        case [result.internal_name '_protocol.h']
            bytes = pcResult.protocol_header_bytes;
        case ['build_' result.internal_name '_sfun.m']
            bytes = buildResult.build_script_bytes;
        otherwise
            error('C2837xBlock:Generation:SfunRenderMismatch', ...
                'No rendered S-Function file matches "%s".', file.relative_path);
    end
    definitions(index) = struct('target_path', file.target_path, ...
        'category', file.category, 'owner', file.owner, ...
        'instance_index', file.instance_index, 'content_bytes', bytes);
end
candidates = c2837x_block_build_candidate_files(definitions);
dependencies = generator_dependencies();
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end

function dependencies = generator_dependencies()
appRoot = fileparts(mfilename('fullpath'));
files = {'c2837x_block_build_sfun_candidates.m', ...
    'c2837x_block_build_sfun_output_model.m', ...
    'c2837x_block_render_sfun_files.m', ...
    'c2837x_block_render_sfun_build_files.m', ...
    'c2837x_block_build_dsp_wire_layout.m', ...
    'c2837x_block_render_pc_files.m', ...
    fullfile('..', 'simulink', 'c2837x_block_pc_error.h'), ...
    fullfile('templates', 'pc_socket.c.in'), ...
    fullfile('templates', 'pc_socket.h.in'), ...
    fullfile('templates', 'protocol.c.in'), ...
    fullfile('templates', 'protocol.h.in'), ...
    'c2837x_block_build_instance_c_names.m'};
prototype = struct('role', '', 'identity', '', 'source_kind', 'file', ...
    'source_path', '', 'content_bytes', zeros(1, 0, 'uint8'));
dependencies = repmat(prototype, 1, numel(files));
for index = 1:numel(files)
    dependencies(index) = struct('role', 'generator_template', ...
        'identity', ['sfun-generator:' files{index}], 'source_kind', 'file', ...
        'source_path', c2837x_block_normalize_absolute_path( ...
        fullfile(appRoot, files{index})), ...
        'content_bytes', zeros(1, 0, 'uint8'));
end
end
