function project = c2837x_block_migrate_legacy_config(config)
%C2837X_BLOCK_MIGRATE_LEGACY_CONFIG Convert one legacy config to V4.

if ~isstruct(config) || ~isscalar(config)
    invalid_legacy('config must be a scalar struct.');
end
required = {'mac', 'dsp_ip', 'gateway', 'subnet', 'socket_num', ...
    'tcp_port', 'sample_time_sec', 'max_payload_size_bytes', 'inputs', ...
    'outputs'};
missing = required(~isfield(config, required));
if ~isempty(missing)
    invalid_legacy('config is missing field %s.', missing{1});
end

project = c2837x_block_create_default_project();
project.common.abi = migrate_abi(config);
project.common.protocol_version = migrate_protocol_version(config);
project.common.network.mac = config.mac;
project.common.network.ip = config.dsp_ip;
project.common.network.gateway = config.gateway;
project.common.network.subnet = config.subnet;

instance = c2837x_block_create_default_instance();
instance.display_name = 'C2837xBlock';
instance.internal_name = 'c2837x_block';
instance.iodevice.settings.socket_number = config.socket_num;
instance.iodevice.settings.tcp_port = config.tcp_port;
instance.sample_time_sec = config.sample_time_sec;
instance.max_payload_size_bytes = config.max_payload_size_bytes;
instance.inputs = migrate_variables(config.inputs, 'config.inputs');
instance.outputs = migrate_variables(config.outputs, 'config.outputs');
project.instances = instance;
end

function migrated = migrate_variables(variables, label)
if ~isstruct(variables)
    invalid_legacy('%s must be a struct array.', label);
end
required = {'name', 'type', 'dim'};
missing = required(~isfield(variables, required));
if ~isempty(missing)
    invalid_legacy('%s is missing field %s.', label, missing{1});
end
migrated = repmat(struct('name', '', 'type', '', 'dim', []), size(variables));
for index = 1:numel(variables)
    migrated(index).name = variables(index).name;
    migrated(index).type = variables(index).type;
    migrated(index).dim = variables(index).dim;
end
end

function abi = migrate_abi(config)
if ~isfield(config, 'abi')
    abi = 'eabi';
    return;
end
if ~(ischar(config.abi) && isrow(config.abi)) && ...
        ~(isstring(config.abi) && isscalar(config.abi))
    invalid_legacy('config.abi must be a supported lowercase value.');
end
switch char(config.abi)
    case 'eabi'
        abi = 'eabi';
    case {'coff', 'coffabi'}
        abi = 'coffabi';
    otherwise
        invalid_legacy('config.abi is not supported.');
end
end

function version = migrate_protocol_version(config)
if ~isfield(config, 'protocol_version')
    version = uint16(1);
    return;
end
value = config.protocol_version;
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
        ~isfinite(value) || value <= 0 || value ~= fix(value)
    error('C2837xBlock:Project:InvalidVersion', ...
        'config.protocol_version must be the positive integer 1.');
end
if value > 1
    error('C2837xBlock:Project:UnsupportedVersion', ...
        'config.protocol_version %g is newer than supported version 1.', value);
end
version = uint16(1);
end

function invalid_legacy(message, varargin)
error('C2837xBlock:Project:InvalidLegacyConfig', message, varargin{:});
end
