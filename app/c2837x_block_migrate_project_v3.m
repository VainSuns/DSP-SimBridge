function project = c2837x_block_migrate_project_v3(source)
%C2837X_BLOCK_MIGRATE_PROJECT_V3 Convert a persisted V3 project to V4.

validate_v3_header(source);
project = source;
project.format_version = uint16(4);
for index = 1:numel(project.instances)
    iodevice = project.instances(index).iodevice;
    if ~isstruct(iodevice) || ~isscalar(iodevice) || ...
            ~all(isfield(iodevice, {'type', 'settings'}))
        invalid_project('V3 instance.iodevice is incomplete or malformed.');
    end
    if strcmp(char(string(iodevice.type)), 'sci')
        project.instances(index).iodevice.settings = ...
            migrate_sci_settings(iodevice.settings);
    end
end
c2837x_block_validate_project_structure(project);
end

function validate_v3_header(project)
if ~isstruct(project) || ~isscalar(project) || ...
        ~isfield(project, 'format_version')
    invalid_project('V3 project must be a scalar struct with format_version.');
end
version = project.format_version;
if ~isa(version, 'uint16') || ~isscalar(version) || version ~= uint16(3)
    error('C2837xBlock:Project:InvalidVersion', ...
        'V3 migration requires format_version uint16(3).');
end
if ~isfield(project, 'instances') || ~isstruct(project.instances)
    invalid_project('V3 project.instances must be a struct array.');
end
end

function settings = migrate_sci_settings(source)
expected = {'module'; 'baud'; 'pin_group'; 'rx_pin_type'; ...
    'rx_qualification'; 'tx_pin_type'; 'ctrl_gpio'; ...
    'ctrl_pin_type'; 'ctrl_tx_active_level'};
if ~isstruct(source) || ~isscalar(source) || ...
        ~isequal(sort(fieldnames(source)), sort(expected))
    invalid_project('V3 SCI settings have an invalid field set.');
end
[rxGpio, txGpio] = migrate_pin_group(source.pin_group);
settings = struct( ...
    'module', source.module, ...
    'baud', source.baud, ...
    'rx_gpio', rxGpio, ...
    'tx_gpio', txGpio, ...
    'rx_pin_type', source.rx_pin_type, ...
    'rx_qualification', source.rx_qualification, ...
    'tx_pin_type', source.tx_pin_type, ...
    'ctrl_gpio', source.ctrl_gpio, ...
    'ctrl_pin_type', source.ctrl_pin_type, ...
    'ctrl_tx_active_level', source.ctrl_tx_active_level);
end

function [rxGpio, txGpio] = migrate_pin_group(value)
rxGpio = '';
txGpio = '';
if isstring(value) && isscalar(value) && ~ismissing(value)
    value = char(value);
end
if ~(ischar(value) && isrow(value))
    return;
end
tokens = regexp(value, '^SCI-[ABCD]_TX([0-9]+)_RX([0-9]+)$', ...
    'tokens', 'once');
if isempty(tokens)
    return;
end
txGpio = ['GPIO' tokens{1}];
rxGpio = ['GPIO' tokens{2}];
end

function invalid_project(message, varargin)
error('C2837xBlock:Project:InvalidStructure', message, varargin{:});
end
