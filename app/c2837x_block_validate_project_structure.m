function c2837x_block_validate_project_structure(project)
%C2837X_BLOCK_VALIDATE_PROJECT_STRUCTURE Validate persisted V4 structure.

if ~isstruct(project) || ~isscalar(project)
    invalid_project('project must be a scalar struct.');
end
require_fields(project, {'format_version', 'common', 'instances', 'output'}, 'project');
validate_version(project.format_version, uint16(4), 'format_version');

common = project.common;
if ~isstruct(common) || ~isscalar(common)
    invalid_project('project.common must be a scalar struct.');
end
require_fields(common, {'dsp_model', 'package', 'protocol_version', 'abi', 'network'}, ...
    'project.common');
validate_version(common.protocol_version, uint16(1), 'protocol_version');
require_text(common.dsp_model, 'project.common.dsp_model');
require_text(common.package, 'project.common.package');
require_text(common.abi, 'project.common.abi');

network = common.network;
if ~isstruct(network) || ~isscalar(network)
    invalid_project('project.common.network must be a scalar struct.');
end
require_fields(network, {'mac', 'ip', 'gateway', 'subnet'}, ...
    'project.common.network');
if ~isnumeric(network.mac) || ~isvector(network.mac)
    invalid_project('project.common.network.mac must be a numeric vector.');
end
require_text(network.ip, 'project.common.network.ip');
require_text(network.gateway, 'project.common.network.gateway');
require_text(network.subnet, 'project.common.network.subnet');

if ~isstruct(project.instances)
    invalid_project('project.instances must be a struct array.');
end
require_fields(project.instances, {'display_name', 'internal_name', ...
    'iodevice', 'sample_time_sec', 'max_payload_size_bytes', 'inputs', ...
    'outputs', 'algorithm', 'interface_hash'}, 'project.instances');
for index = 1:numel(project.instances)
    validate_instance(project.instances(index));
end

output = project.output;
if ~isstruct(output) || ~isscalar(output)
    invalid_project('project.output must be a scalar struct.');
end
require_fields(output, {'dsp_root', 'sfun_root'}, 'project.output');
require_path(output.dsp_root, 'project.output.dsp_root');
require_path(output.sfun_root, 'project.output.sfun_root');
end

function validate_instance(instance)
require_fields(instance, {'display_name', 'internal_name', 'iodevice', ...
    'sample_time_sec', 'max_payload_size_bytes', 'inputs', 'outputs', ...
    'algorithm', 'interface_hash'}, 'project.instances');
require_text(instance.display_name, 'instance.display_name');
require_text(instance.internal_name, 'instance.internal_name');
require_numeric_scalar(instance.sample_time_sec, 'instance.sample_time_sec');
require_numeric_scalar(instance.max_payload_size_bytes, 'instance.max_payload_size_bytes');
require_numeric_scalar(instance.interface_hash, 'instance.interface_hash');

iodevice = instance.iodevice;
if ~isstruct(iodevice) || ~isscalar(iodevice)
    invalid_project('instance.iodevice must be a scalar struct.');
end
require_fields(iodevice, {'type', 'settings'}, 'instance.iodevice');
require_text(iodevice.type, 'instance.iodevice.type');
if ~isstruct(iodevice.settings) || ~isscalar(iodevice.settings)
    invalid_project('instance.iodevice.settings must be a scalar struct.');
end
validate_known_iodevice_settings(char(iodevice.type), iodevice.settings);

validate_variables(instance.inputs, 'instance.inputs');
validate_variables(instance.outputs, 'instance.outputs');
algorithm = instance.algorithm;
if ~isstruct(algorithm) || ~isscalar(algorithm)
    invalid_project('instance.algorithm must be a scalar struct.');
end
require_fields(algorithm, {'mode', 'source_path'}, 'instance.algorithm');
require_text(algorithm.mode, 'instance.algorithm.mode');
require_path(algorithm.source_path, 'instance.algorithm.source_path');
end

function validate_known_iodevice_settings(type, settings)
switch type
    case 'sci'
        fields = {'module', 'baud', 'rx_gpio', 'tx_gpio', 'rx_pin_type', ...
            'rx_qualification', 'tx_pin_type', 'ctrl_gpio', ...
            'ctrl_pin_type', 'ctrl_tx_active_level'};
        require_exact_fields(settings, fields, 'SCI IoDevice settings');
        require_text(settings.module, 'instance.iodevice.settings.module');
        require_numeric_scalar(settings.baud, 'instance.iodevice.settings.baud');
        require_text(settings.rx_gpio, 'instance.iodevice.settings.rx_gpio');
        require_text(settings.tx_gpio, 'instance.iodevice.settings.tx_gpio');
        require_text(settings.rx_pin_type, 'instance.iodevice.settings.rx_pin_type');
        require_text(settings.rx_qualification, ...
            'instance.iodevice.settings.rx_qualification');
        require_text(settings.tx_pin_type, 'instance.iodevice.settings.tx_pin_type');
        require_text(settings.ctrl_gpio, 'instance.iodevice.settings.ctrl_gpio');
        require_text(settings.ctrl_pin_type, ...
            'instance.iodevice.settings.ctrl_pin_type');
        require_text(settings.ctrl_tx_active_level, ...
            'instance.iodevice.settings.ctrl_tx_active_level');
end
end

function require_exact_fields(value, names, label)
require_fields(value, names, label);
unexpected = setdiff(fieldnames(value), names);
if ~isempty(unexpected)
    invalid_project('%s contains unexpected field %s.', label, unexpected{1});
end
end

function validate_variables(variables, label)
if ~isstruct(variables)
    invalid_project('%s must be a struct array.', label);
end
require_fields(variables, {'name', 'type', 'dim'}, label);
for index = 1:numel(variables)
    require_text(variables(index).name, [label '.name']);
    require_text(variables(index).type, [label '.type']);
    if ~isnumeric(variables(index).dim) || isempty(variables(index).dim) || ...
            ~isvector(variables(index).dim)
        invalid_project('%s.dim must be a nonempty numeric vector.', label);
    end
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

function require_path(value, label)
require_text(value, label);
value = char(value);
if isempty(value)
    return;
end
try
    normalized = c2837x_block_normalize_absolute_path(value);
catch cause
    failure = MException('C2837xBlock:Project:InvalidPath', ...
        '%s must be a canonical absolute path.', label);
    throwAsCaller(addCause(failure, cause));
end
if ~strcmp(value, normalized)
    error('C2837xBlock:Project:InvalidPath', ...
        '%s must be stored in canonical form.', label);
end
end

function require_numeric_scalar(value, label)
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ~isfinite(value)
    invalid_project('%s must be a finite numeric scalar.', label);
end
end

function invalid_project(message, varargin)
error('C2837xBlock:Project:InvalidStructure', message, varargin{:});
end
