function project = c2837x_block_migrate_project_v2(source)
%C2837X_BLOCK_MIGRATE_PROJECT_V2 Convert a persisted V2 project to V3.

if ~isstruct(source) || ~isscalar(source)
    invalid_project('project must be a scalar struct.');
end
if ~isfield(source, 'format_version') || ...
        ~isa(source.format_version, 'uint16') || ...
        ~isscalar(source.format_version) || source.format_version ~= uint16(2)
    error('C2837xBlock:Project:InvalidVersion', ...
        'V2 migration requires format_version uint16(2).');
end

try
    project = c2837x_block_create_default_project();
    project.common.protocol_version = source.common.protocol_version;
    project.common.abi = source.common.abi;
    project.common.network = source.common.network;
    project.output.dsp_root = source.output.dsp_root;
    project.output.sfun_root = source.output.sfun_root;

    instances = c2837x_block_create_default_instance();
    instances = instances([]);
    for index = 1:numel(source.instances)
        old = source.instances(index);
        instance = c2837x_block_create_default_instance();
        instance.display_name = old.display_name;
        instance.internal_name = old.internal_name;
        instance.iodevice.settings.socket_number = ...
            old.iodevice.settings.socket_number;
        instance.iodevice.settings.tcp_port = old.iodevice.settings.tcp_port;
        instance.sample_time_sec = old.sample_time_sec;
        instance.max_payload_size_bytes = old.max_payload_size_bytes;
        instance.inputs = canonical_variables(old.inputs);
        instance.outputs = canonical_variables(old.outputs);
        instance.algorithm = struct('mode', old.algorithm.mode, ...
            'source_path', old.algorithm.source_path);
        instance.interface_hash = old.interface_hash;
        instances(end + 1) = instance; %#ok<AGROW>
    end
    project.instances = instances;
catch cause
    if startsWith(cause.identifier, 'C2837xBlock:Project:')
        rethrow(cause);
    end
    failure = MException('C2837xBlock:Project:InvalidStructure', ...
        'V2 project structure is incomplete or malformed.');
    throwAsCaller(addCause(failure, cause));
end

c2837x_block_validate_project_structure(project);
end

function variables = canonical_variables(source)
variables = repmat(struct('name', '', 'type', '', 'dim', []), size(source));
for index = 1:numel(source)
    variables(index).name = source(index).name;
    variables(index).type = source(index).type;
    variables(index).dim = source(index).dim;
end
end

function invalid_project(message, varargin)
error('C2837xBlock:Project:InvalidStructure', message, varargin{:});
end
