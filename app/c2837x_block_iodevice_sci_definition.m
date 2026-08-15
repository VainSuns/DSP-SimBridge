function definition = c2837x_block_iodevice_sci_definition()
%C2837X_BLOCK_IODEVICE_SCI_DEFINITION Describe SCI validation resources.

definition = struct('type', 'sci', 'max_instance_count', 4, ...
    'validate_settings', @validate_settings, ...
    'collect_resource_claims', @collect_resource_claims, ...
    'render_project_support', @render_project_support, ...
    'render_instance_config_support', @render_instance_config_support, ...
    'render_instance_io_support', @render_instance_io_support);
end

function support = render_project_support(project)
% Render the project-level descriptor collection used by PlatformInit.
descriptors = build_project_descriptors(project);
if isempty(descriptors)
    support = struct('includes', {{}}, 'source', '');
    return;
end

literals = cell(1, numel(descriptors));
for index = 1:numel(descriptors)
    literals{index} = descriptor_literal(descriptors(index), '    ');
end
support = struct('includes', {{}}, 'source', sprintf([ ...
    'const C2837xBlock_SciDescriptor\n' ...
    '    c2837x_block_project_sci_descriptors[] =\n' ...
    '{\n%s\n};\n'], strjoin(literals, [',' newline])));
end

function support = render_instance_config_support(project, instanceIndex)
instance = project.instances(instanceIndex);
name = char(instance.internal_name);
descriptor = build_descriptor(project, instanceIndex);
support = struct( ...
    'header_definitions', ...
    '/* SCI hardware descriptor is emitted in the generated Config source. */', ...
    'header_checks', ...
    '/* SCI endpoint values are capability-derived. */', ...
    'source_includes', {{'c2837x_block_sci.h'}}, ...
    'source_declarations', sprintf([ ...
    'const C2837xBlock_SciDescriptor\n' ...
    '    c2837x_block_%s_sci_descriptor =\n%s;\n\n' ...
    'extern C2837xBlock_SciChannel\n' ...
    '    c2837x_block_%s_iodevice_channel;\n'], ...
    name, descriptor_literal(descriptor, '    '), name), ...
    'iodevice_ops_expression', '&c2837x_block_sci_iodevice_ops', ...
    'iodevice_channel_expression', ...
    ['&c2837x_block_' name '_iodevice_channel']);
end

function support = render_instance_io_support(project, instanceIndex)
instance = project.instances(instanceIndex);
name = char(instance.internal_name);
build_descriptor(project, instanceIndex);
support = struct( ...
    'source_includes', {{'c2837x_block_sci.h'}}, ...
    'source_definitions', sprintf([ ...
    'extern const C2837xBlock_SciDescriptor\n' ...
    '    c2837x_block_%s_sci_descriptor;\n\n' ...
    'C2837xBlock_SciChannel\n' ...
    '    c2837x_block_%s_iodevice_channel =\n' ...
    'C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(\n' ...
    '    &c2837x_block_%s_sci_descriptor);\n'], name, name, name));
end

function issues = validate_settings(settings, instanceIndex)
issues = empty_issues();
prefix = sprintf('project.instances(%u).iodevice.settings.', instanceIndex);
module = field_text(settings, 'module');
rxGpio = field_text(settings, 'rx_gpio');
txGpio = field_text(settings, 'tx_gpio');
moduleValid = false;

if isempty(module)
    append('SCI_MODULE_REQUIRED', 'SCI Module must be selected.', 'module');
elseif ~any(strcmp(module, {'SCI-A', 'SCI-B', 'SCI-C', 'SCI-D'}))
    append('SCI_MODULE_INVALID', ...
        'SCI Module must be SCI-A, SCI-B, SCI-C, or SCI-D.', 'module');
else
    moduleValid = true;
end
if ~valid_numeric_choice(settings, 'baud', [9600 19200 38400 57600 115200])
    append('SCI_BAUD_INVALID', ...
        'SCI Baud must be 9600, 19200, 38400, 57600, or 115200.', 'baud');
end
if isempty(rxGpio)
    append('SCI_RX_GPIO_REQUIRED', 'SCI RX GPIO must be selected.', 'rx_gpio');
end
if isempty(txGpio)
    append('SCI_TX_GPIO_REQUIRED', 'SCI TX GPIO must be selected.', 'tx_gpio');
end
if ~valid_text_choice(settings, 'rx_pin_type', {'Standard', 'Pull-up'})
    append('SCI_RX_PIN_TYPE_INVALID', ...
        'SCI RX Pin Type must be Standard or Pull-up.', 'rx_pin_type');
end
if ~valid_text_choice(settings, 'tx_pin_type', {'Standard', 'Pull-up'})
    append('SCI_TX_PIN_TYPE_INVALID', ...
        'SCI TX Pin Type must be Standard or Pull-up.', 'tx_pin_type');
end
if ~valid_text_choice(settings, 'ctrl_pin_type', {'Standard', 'Pull-up'})
    append('SCI_CTRL_PIN_TYPE_INVALID', ...
        'SCI CTRL Pin Type must be Standard or Pull-up.', 'ctrl_pin_type');
end
if ~valid_text_choice(settings, 'rx_qualification', {'Sync', 'Async'})
    append('SCI_RX_QUALIFICATION_INVALID', ...
        'SCI RX Qualification must be Sync or Async.', 'rx_qualification');
end
if ~valid_text_choice(settings, 'ctrl_tx_active_level', {'High', 'Low'})
    append('SCI_CTRL_ACTIVE_LEVEL_INVALID', ...
        'SCI CTRL TX Active Level must be High or Low.', ...
        'ctrl_tx_active_level');
end

capabilityResult = load_capability();
if ~capabilityResult.available
    append('SCI_CAPABILITY_UNAVAILABLE', sprintf( ...
        'SCI device capability is unavailable (%s): %s', ...
        capabilityResult.identifier, capabilityResult.message), 'module');
    return;
end
capability = capabilityResult.capability;
moduleIndex = find(strcmp({capability.sci_modules.id}, module), 1);
if moduleValid && isempty(moduleIndex)
    append('SCI_MODULE_INVALID', ...
        'SCI Module does not exist in the normalized device capability.', 'module');
    moduleValid = false;
end
if moduleValid && ~isempty(rxGpio) && ...
        ~gpio_belongs_to_endpoints(rxGpio, ...
        capability.sci_modules(moduleIndex).rx_endpoints)
    append('SCI_RX_GPIO_INVALID', ...
        'SCI RX GPIO does not belong to the selected Module.', 'rx_gpio');
end
if moduleValid && ~isempty(txGpio) && ...
        ~gpio_belongs_to_endpoints(txGpio, ...
        capability.sci_modules(moduleIndex).tx_endpoints)
    append('SCI_TX_GPIO_INVALID', ...
        'SCI TX GPIO does not belong to the selected Module.', 'tx_gpio');
end
ctrlGpio = field_text(settings, 'ctrl_gpio');
if ~strcmp(ctrlGpio, 'None')
    [ctrlValid, ctrlNumber] = parse_gpio(ctrlGpio);
    if ~ctrlValid || ~any(double([capability.gpios.number]) == ctrlNumber)
        append('SCI_CTRL_GPIO_INVALID', ...
            'SCI CTRL GPIO must be None or a canonical GPIO in the device capability.', ...
            'ctrl_gpio');
    end
end

    function append(code, message, field)
        issues(end + 1) = issue(code, message, [prefix field], instanceIndex);
    end
end

function claims = collect_resource_claims(settings, instanceIndex)
prototype = claim_prototype();
claims = repmat(prototype, 1, 0);
capabilityResult = load_capability();
if ~capabilityResult.available
    return;
end
capability = capabilityResult.capability;
prefix = sprintf('project.instances(%u).iodevice.settings.', instanceIndex);
module = field_text(settings, 'module');
moduleIndex = find(strcmp({capability.sci_modules.id}, module), 1);
if ~isempty(moduleIndex) && any(strcmp(module, {'SCI-A', 'SCI-B', 'SCI-C', 'SCI-D'}))
    claims(end + 1) = claim('project:sci', 'module', module, ...
        'SCI_MODULE_DUPLICATE', ...
        sprintf('SCI Module %s is already used.', module), ...
        [prefix 'module'], instanceIndex);
    selectedModule = capability.sci_modules(moduleIndex);
    [rxValid, rxNumber] = endpoint_gpio( ...
        field_text(settings, 'rx_gpio'), selectedModule.rx_endpoints);
    if rxValid
        claims(end + 1) = gpio_claim(rxNumber, ...
            [prefix 'rx_gpio'], instanceIndex);
    end
    [txValid, txNumber] = endpoint_gpio( ...
        field_text(settings, 'tx_gpio'), selectedModule.tx_endpoints);
    if txValid
        claims(end + 1) = gpio_claim(txNumber, ...
            [prefix 'tx_gpio'], instanceIndex);
    end
end
ctrlGpio = field_text(settings, 'ctrl_gpio');
[ctrlValid, ctrlNumber] = parse_gpio(ctrlGpio);
if ctrlValid && any(double([capability.gpios.number]) == ctrlNumber)
    claims(end + 1) = gpio_claim(ctrlNumber, ...
        [prefix 'ctrl_gpio'], instanceIndex);
end
end

function value = gpio_claim(number, fieldPath, instanceIndex)
value = claim('project:gpio', 'gpio', sprintf('%.0f', double(number)), ...
    'SCI_GPIO_CONFLICT', ...
    sprintf(['GPIO%u is already used by another SCI setting or an active ' ...
    'platform resource.'], double(number)), fieldPath, instanceIndex);
end

function value = claim(scope, kind, key, code, message, fieldPath, instanceIndex)
value = claim_prototype();
value.scope = scope;
value.kind = kind;
value.key = key;
value.exclusive = true;
value.duplicate_code = code;
value.duplicate_message = message;
value.field_path = fieldPath;
value.instance_index = instanceIndex;
end

function value = claim_prototype()
value = struct('scope', '', 'kind', '', 'key', '', 'exclusive', false, ...
    'duplicate_code', '', 'duplicate_message', '', 'field_path', '', ...
    'instance_index', 0);
end

function result = load_capability()
try
    result = c2837x_block_load_device_capability();
catch cause
    result = struct('available', false, 'capability', struct(), ...
        'identifier', cause.identifier, 'message', cause.message, ...
        'source_path', '');
end
if isempty(result.identifier)
    result.identifier = 'C2837xBlock:Capability:Unavailable';
end
if isempty(result.message)
    result.message = 'The normalized device capability could not be loaded.';
end
end

function valid = gpio_belongs_to_endpoints(value, endpoints)
[valid, ~] = endpoint_gpio(value, endpoints);
end

function [valid, number] = endpoint_gpio(value, endpoints)
[valid, number] = parse_gpio(value);
valid = valid && any(double([endpoints.gpio]) == number);
end

function [valid, number] = parse_gpio(value)
tokens = regexp(value, '^GPIO(0|[1-9][0-9]*)$', 'tokens', 'once');
valid = ~isempty(tokens);
number = NaN;
if valid
    number = str2double(tokens{1});
    valid = isfinite(number) && number <= double(intmax('uint16'));
end
end

function valid = valid_numeric_choice(settings, name, choices)
valid = isstruct(settings) && isscalar(settings) && isfield(settings, name) && ...
    isnumeric(settings.(name)) && isscalar(settings.(name)) && ...
    isreal(settings.(name)) && isfinite(settings.(name)) && ...
    any(double(settings.(name)) == choices);
end

function valid = valid_text_choice(settings, name, choices)
value = field_text(settings, name);
valid = any(strcmp(value, choices));
end

function value = field_text(settings, name)
value = '';
if ~isstruct(settings) || ~isscalar(settings) || ~isfield(settings, name)
    return;
end
candidate = settings.(name);
if ischar(candidate) && isrow(candidate)
    value = candidate;
elseif isstring(candidate) && isscalar(candidate) && ~ismissing(candidate)
    value = char(candidate);
end
end

function descriptors = build_project_descriptors(project)
descriptors = repmat(empty_descriptor(), 1, 0);
for index = 1:numel(project.instances)
    if strcmp(char(project.instances(index).iodevice.type), 'sci')
        descriptors(end + 1) = build_descriptor(project, index); %#ok<AGROW>
    end
end
end

function descriptor = build_descriptor(project, instanceIndex)
instance = project.instances(instanceIndex);
settings = instance.iodevice.settings;
capabilityResult = load_capability();
if ~capabilityResult.available
    error('C2837xBlock:IoDevice:SciGenerationCapabilityUnavailable', ...
        'SCI generation requires device capability (%s): %s', ...
        capabilityResult.identifier, capabilityResult.message);
end

capability = capabilityResult.capability;
module = field_text(settings, 'module');
moduleIndex = find(strcmp({capability.sci_modules.id}, module), 1);
if isempty(moduleIndex)
    error('C2837xBlock:IoDevice:SciGenerationInvalidSettings', ...
        'SCI generation requires a valid selected SCI Module.');
end

selectedModule = capability.sci_modules(moduleIndex);
rx = selected_endpoint(settings.rx_gpio, selectedModule.rx_endpoints, ...
    'RX');
tx = selected_endpoint(settings.tx_gpio, selectedModule.tx_endpoints, ...
    'TX');
clock = c2837x_block_get_sci_clock_config();
baud = c2837x_block_calculate_sci_baud(clock.lspclk_hz, settings.baud);

ctrlText = field_text(settings, 'ctrl_gpio');
if strcmp(ctrlText, 'None')
    ctrlGpio = uint16(65535);
else
    [ctrlValid, ctrlNumber] = parse_gpio(ctrlText);
    if ~ctrlValid || ctrlNumber > 168 || ...
            ~any(double([capability.gpios.number]) == ctrlNumber)
        error('C2837xBlock:IoDevice:SciGenerationInvalidSettings', ...
            'SCI generation requires a valid CTRL GPIO or None.');
    end
    ctrlGpio = uint16(ctrlNumber);
end

descriptor = struct( ...
    'module_enum', module_enum(module), ...
    'brr', uint16(baud.brr), ...
    'rx_gpio', uint16(rx.gpio), ...
    'rx_mux', uint16(rx.mux_selection), ...
    'rx_pin_type_enum', pin_type_enum(settings.rx_pin_type), ...
    'rx_qualification_enum', qualification_enum(settings.rx_qualification), ...
    'tx_gpio', uint16(tx.gpio), ...
    'tx_mux', uint16(tx.mux_selection), ...
    'tx_pin_type_enum', pin_type_enum(settings.tx_pin_type), ...
    'ctrl_gpio', ctrlGpio, ...
    'ctrl_pin_type_enum', pin_type_enum(settings.ctrl_pin_type), ...
    'ctrl_active_level_enum', active_level_enum( ...
        settings.ctrl_tx_active_level));
end

function endpoint = selected_endpoint(value, endpoints, direction)
[valid, number] = endpoint_gpio(field_text_value(value), endpoints);
if ~valid
    error('C2837xBlock:IoDevice:SciGenerationInvalidSettings', ...
        'SCI generation requires a valid selected %s endpoint.', direction);
end
index = find(double([endpoints.gpio]) == number, 1);
endpoint = endpoints(index);
end

function value = field_text_value(candidate)
if ischar(candidate) && isrow(candidate)
    value = candidate;
elseif isstring(candidate) && isscalar(candidate) && ~ismissing(candidate)
    value = char(candidate);
else
    value = '';
end
end

function descriptor = empty_descriptor()
descriptor = struct( ...
    'module_enum', '', 'brr', uint16(0), ...
    'rx_gpio', uint16(0), 'rx_mux', uint16(0), ...
    'rx_pin_type_enum', '', 'rx_qualification_enum', '', ...
    'tx_gpio', uint16(0), 'tx_mux', uint16(0), ...
    'tx_pin_type_enum', '', 'ctrl_gpio', uint16(0), ...
    'ctrl_pin_type_enum', '', 'ctrl_active_level_enum', '');
end

function text = descriptor_literal(descriptor, indent)
text = sprintf([ ...
    '%s{\n' ...
    '%s    %s,\n' ...
    '%s    (Uint16)%uu,\n' ...
    '%s    {\n' ...
    '%s        { (Uint16)%uu, (Uint16)%uu },\n' ...
    '%s        %s,\n' ...
    '%s        %s\n' ...
    '%s    },\n' ...
    '%s    {\n' ...
    '%s        { (Uint16)%uu, (Uint16)%uu },\n' ...
    '%s        %s\n' ...
    '%s    },\n' ...
    '%s    {\n' ...
    '%s        %s,\n' ...
    '%s        %s,\n' ...
    '%s        %s\n' ...
    '%s    }\n' ...
    '%s}'], ...
    indent, indent, descriptor.module_enum, indent, descriptor.brr, ...
    indent, indent, descriptor.rx_gpio, descriptor.rx_mux, indent, ...
    descriptor.rx_pin_type_enum, indent, descriptor.rx_qualification_enum, ...
    indent, indent, indent, descriptor.tx_gpio, descriptor.tx_mux, indent, ...
    descriptor.tx_pin_type_enum, indent, indent, ...
    indent, ctrl_gpio_literal(descriptor.ctrl_gpio), indent, ...
    descriptor.ctrl_pin_type_enum, indent, descriptor.ctrl_active_level_enum, ...
    indent, indent);
end

function value = ctrl_gpio_literal(gpio)
if gpio == uint16(65535)
    value = 'C2837X_BLOCK_SCI_NO_CTRL_GPIO';
else
    value = sprintf('(Uint16)%uu', gpio);
end
end

function value = module_enum(module)
switch module
    case 'SCI-A'
        value = 'C2837X_BLOCK_SCI_MODULE_A';
    case 'SCI-B'
        value = 'C2837X_BLOCK_SCI_MODULE_B';
    case 'SCI-C'
        value = 'C2837X_BLOCK_SCI_MODULE_C';
    case 'SCI-D'
        value = 'C2837X_BLOCK_SCI_MODULE_D';
    otherwise
        error('C2837xBlock:IoDevice:SciGenerationInvalidSettings', ...
            'SCI generation received an unsupported SCI Module.');
end
end

function value = pin_type_enum(pinType)
switch field_text_value(pinType)
    case 'Standard'
        value = 'C2837X_BLOCK_SCI_PIN_STANDARD';
    case 'Pull-up'
        value = 'C2837X_BLOCK_SCI_PIN_PULLUP';
    otherwise
        error('C2837xBlock:IoDevice:SciGenerationInvalidSettings', ...
            'SCI generation received an unsupported Pin Type.');
end
end

function value = qualification_enum(qualification)
switch field_text_value(qualification)
    case 'Sync'
        value = 'C2837X_BLOCK_SCI_QUALIFICATION_SYNC';
    case 'Async'
        value = 'C2837X_BLOCK_SCI_QUALIFICATION_ASYNC';
    otherwise
        error('C2837xBlock:IoDevice:SciGenerationInvalidSettings', ...
            'SCI generation received an unsupported RX Qualification.');
end
end

function value = active_level_enum(activeLevel)
switch field_text_value(activeLevel)
    case 'Low'
        value = 'C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_LOW';
    case 'High'
        value = 'C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH';
    otherwise
        error('C2837xBlock:IoDevice:SciGenerationInvalidSettings', ...
            'SCI generation received an unsupported CTRL polarity.');
end
end

function value = issue(code, message, fieldPath, instanceIndex)
value = struct('severity', 'Error', 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', instanceIndex, 'file_path', '');
end

function values = empty_issues()
values = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end
