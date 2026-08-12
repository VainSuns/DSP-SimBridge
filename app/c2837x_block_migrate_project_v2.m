function project = c2837x_block_migrate_project_v2(source)
%C2837X_BLOCK_MIGRATE_PROJECT_V2 Convert a persisted V2 project to V3.

validate_v2_structure(source);

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

function validate_v2_structure(project)
if ~isstruct(project) || ~isscalar(project)
    invalid_project('project must be a scalar struct.');
end
require_fields(project, {'format_version', 'common', 'instances', 'output'}, ...
    'project');
validate_version(project.format_version, uint16(2), 'format_version');

common = project.common;
if ~isstruct(common) || ~isscalar(common)
    invalid_project('project.common must be a scalar struct.');
end
require_fields(common, {'dsp_model', 'protocol_version', 'abi', 'network'}, ...
    'project.common');
if ~isstruct(common.network) || ~isscalar(common.network)
    invalid_project('project.common.network must be a scalar struct.');
end
require_fields(common.network, {'mac', 'ip', 'gateway', 'subnet'}, ...
    'project.common.network');

if ~isstruct(project.instances)
    invalid_project('project.instances must be a struct array.');
end
require_fields(project.instances, {'display_name', 'internal_name', ...
    'iodevice', 'sample_time_sec', 'max_payload_size_bytes', 'inputs', ...
    'outputs', 'algorithm', 'interface_hash'}, 'project.instances');
for index = 1:numel(project.instances)
    validate_instance_fields(project.instances(index));
end
if ~isstruct(project.output) || ~isscalar(project.output)
    invalid_project('project.output must be a scalar struct.');
end
require_fields(project.output, {'dsp_root', 'sfun_root'}, 'project.output');

candidate = project;
candidate.format_version = uint16(3);
candidate.common.package = 'PTP';
c2837x_block_validate_project_structure(candidate);
end

function validate_instance_fields(instance)
iodevice = instance.iodevice;
if ~isstruct(iodevice) || ~isscalar(iodevice)
    invalid_project('instance.iodevice must be a scalar struct.');
end
require_fields(iodevice, {'type', 'settings'}, 'instance.iodevice');
require_text(iodevice.type, 'instance.iodevice.type');
if ~strcmp(char(iodevice.type), 'w5300_tcp')
    invalid_project('V2 instance.iodevice.type must be w5300_tcp.');
end
if ~isstruct(iodevice.settings) || ~isscalar(iodevice.settings)
    invalid_project('instance.iodevice.settings must be a scalar struct.');
end
require_fields(iodevice.settings, {'socket_number', 'tcp_port'}, ...
    'instance.iodevice.settings');

require_variable_fields(instance.inputs, 'instance.inputs');
require_variable_fields(instance.outputs, 'instance.outputs');
algorithm = instance.algorithm;
if ~isstruct(algorithm) || ~isscalar(algorithm)
    invalid_project('instance.algorithm must be a scalar struct.');
end
require_fields(algorithm, {'mode', 'source_path'}, 'instance.algorithm');
end

function require_variable_fields(variables, label)
if ~isstruct(variables)
    invalid_project('%s must be a struct array.', label);
end
require_fields(variables, {'name', 'type', 'dim'}, label);
end

function variables = canonical_variables(source)
variables = repmat(struct('name', '', 'type', '', 'dim', []), size(source));
for index = 1:numel(source)
    variables(index).name = source(index).name;
    variables(index).type = source(index).type;
    variables(index).dim = source(index).dim;
end
end

function validate_version(value, supported, name)
if ~isa(value, 'uint16') || ~isscalar(value) || value == 0
    error('C2837xBlock:Project:InvalidVersion', ...
        '%s must be a nonzero uint16 scalar.', name);
end
if value > supported
    error('C2837xBlock:Project:UnsupportedVersion', ...
        '%s %g is newer than supported version %g.', name, value, supported);
end
if value ~= supported
    error('C2837xBlock:Project:InvalidVersion', ...
        '%s must equal supported version %g.', name, supported);
end
end

function require_fields(value, names, label)
missing = names(~isfield(value, names));
if ~isempty(missing)
    invalid_project('%s is missing field %s.', label, missing{1});
end
end

function require_text(value, label)
if ~(ischar(value) && (isrow(value) || isempty(value))) && ...
        ~(isstring(value) && isscalar(value))
    invalid_project('%s must be text.', label);
end
end

function invalid_project(message, varargin)
error('C2837xBlock:Project:InvalidStructure', message, varargin{:});
end
