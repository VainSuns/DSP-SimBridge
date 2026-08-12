function result = c2837x_block_load_device_capability(sourcePath)
%C2837X_BLOCK_LOAD_DEVICE_CAPABILITY Load a normalized device capability.

if nargin == 0
    sourcePath = fullfile(fileparts(mfilename('fullpath')), 'capabilities', ...
        'TMS320F28377D_PTP.json');
elseif nargin ~= 1
    error('C2837xBlock:Capability:InvalidInput', ...
        'Provide at most one absolute capability file path.');
end
sourcePath = c2837x_block_normalize_absolute_path(sourcePath);
result = failure_result(sourcePath, '', '');
if exist(sourcePath, 'file') ~= 2
    result.identifier = 'C2837xBlock:Capability:Unavailable';
    result.message = sprintf('Device capability file is unavailable: %s', ...
        sourcePath);
    return;
end

try
    jsonText = fileread(sourcePath);
catch
    result.identifier = 'C2837xBlock:Capability:Unavailable';
    result.message = sprintf('Device capability file cannot be read: %s', ...
        sourcePath);
    return;
end
try
    raw = jsondecode(jsonText);
catch
    result.identifier = 'C2837xBlock:Capability:InvalidJson';
    result.message = sprintf('Device capability JSON is invalid: %s', ...
        sourcePath);
    return;
end

try
    validate_raw_capability(raw);
    capability = normalize_capability(raw);
catch cause
    if startsWith(cause.identifier, 'C2837xBlock:Capability:')
        result.identifier = cause.identifier;
        result.message = cause.message;
        return;
    end
    rethrow(cause);
end
result.available = true;
result.capability = capability;
end

function result = failure_result(sourcePath, identifier, message)
result = struct('available', false, 'capability', struct(), ...
    'identifier', identifier, 'message', message, ...
    'source_path', sourcePath);
end

function validate_raw_capability(raw)
require_object(raw, {'schema_version', 'target', 'provenance', ...
    'sci_modules', 'gpio_capabilities'}, 'capability');
if ~valid_integer(raw.schema_version, 0, double(intmax('uint16')))
    invalid_schema('capability.schema_version must be an integer scalar.');
end
if raw.schema_version ~= 1
    error('C2837xBlock:Capability:UnsupportedSchema', ...
        'Capability schema_version %g is not supported.', raw.schema_version);
end
validate_target(raw.target);
validate_provenance(raw.provenance);
gpioNumbers = validate_gpios(raw.gpio_capabilities);
validate_modules(raw.sci_modules, gpioNumbers);
end

function validate_target(target)
require_object(target, {'device', 'package'}, 'capability.target');
require_text(target.device, 'capability.target.device');
require_text(target.package, 'capability.target.package');
if ~strcmp(target.device, 'TMS320F28377D') || ~strcmp(target.package, 'PTP')
    invalid_schema(['capability.target must identify ' ...
        'TMS320F28377D with the PTP package.']);
end
end

function validate_provenance(provenance)
require_object(provenance, {'datasheet', 'pin_map', 'package_filter'}, ...
    'capability.provenance');
require_object(provenance.datasheet, {'title', 'document_number', ...
    'revision', 'tables', 'url'}, 'capability.provenance.datasheet');
require_object(provenance.pin_map, {'product', 'version', 'path', 'url'}, ...
    'capability.provenance.pin_map');
textFields = {'title', 'document_number', 'revision', 'url'};
for index = 1:numel(textFields)
    field = textFields{index};
    require_text(provenance.datasheet.(field), ...
        ['capability.provenance.datasheet.' field]);
end
textFields = {'product', 'version', 'path', 'url'};
for index = 1:numel(textFields)
    field = textFields{index};
    require_text(provenance.pin_map.(field), ...
        ['capability.provenance.pin_map.' field]);
end
require_text(provenance.package_filter, ...
    'capability.provenance.package_filter');
if ~strcmp(provenance.datasheet.document_number, 'SPRS880P') || ...
        ~strcmp(provenance.datasheet.revision, 'P') || ...
        ~strcmp(provenance.pin_map.product, 'C2000Ware') || ...
        isempty(strfind(provenance.pin_map.path, 'f2837xd'))
    invalid_schema('capability.provenance does not identify the required TI sources.');
end
tables = provenance.datasheet.tables;
if ~iscell(tables) || numel(tables) ~= 2 || ...
        ~all(cellfun(@(value) ischar(value) && isrow(value) && ...
        ~isempty(value), tables)) || ...
        ~any(strcmp(tables, 'Table 5-1 Signal Descriptions')) || ...
        ~any(strcmp(tables, 'Table 5-3 GPIO Muxed Pins'))
    invalid_schema('capability.provenance.datasheet.tables is invalid.');
end
end

function gpioNumbers = validate_gpios(gpios)
if ~isstruct(gpios) || isempty(gpios)
    invalid_schema('capability.gpio_capabilities must be a nonempty object array.');
end
gpioNumbers = zeros(1, numel(gpios));
packagePins = zeros(1, numel(gpios));
for index = 1:numel(gpios)
    require_object(gpios(index), {'gpio', 'package_pin'}, ...
        'capability.gpio_capabilities');
    if ~valid_integer(gpios(index).gpio, 0, 168) || ...
            ~valid_integer(gpios(index).package_pin, 1, 176)
        invalid_schema(['Each GPIO capability must contain an integer GPIO ' ...
            'number and PTP package pin.']);
    end
    gpioNumbers(index) = gpios(index).gpio;
    packagePins(index) = gpios(index).package_pin;
end
if numel(unique(gpioNumbers)) ~= numel(gpioNumbers) || ...
        numel(unique(packagePins)) ~= numel(packagePins)
    invalid_schema('GPIO and PTP package pin entries must be unique.');
end
end

function validate_modules(modules, gpioNumbers)
if ~isstruct(modules) || numel(modules) ~= 4
    invalid_schema('capability.sci_modules must contain exactly four modules.');
end
for index = 1:numel(modules)
    require_object(modules(index), {'id', 'display_name', ...
        'rx_endpoints', 'tx_endpoints'}, ...
        'capability.sci_modules');
    require_text(modules(index).id, 'SCI module id');
    require_text(modules(index).display_name, 'SCI module display_name');
end
expectedIds = {'SCI-A', 'SCI-B', 'SCI-C', 'SCI-D'};
moduleIds = {modules.id};
if numel(unique(moduleIds)) ~= 4 || ...
        ~all(ismember(expectedIds, moduleIds))
    invalid_schema('SCI module IDs must be SCI-A, SCI-B, SCI-C, and SCI-D.');
end
for index = 1:numel(modules)
    validate_endpoint_set(modules(index).rx_endpoints, ...
        modules(index).id, 'RX', gpioNumbers);
    validate_endpoint_set(modules(index).tx_endpoints, ...
        modules(index).id, 'TX', gpioNumbers);
end
end

function validate_endpoint_set(endpoints, moduleId, direction, gpioNumbers)
if ~isstruct(endpoints) || isempty(endpoints)
    invalid_schema('Each SCI module must contain RX and TX endpoints.');
end
for index = 1:numel(endpoints)
    validate_endpoint(endpoints(index), moduleId, direction, gpioNumbers);
end
if numel(unique([endpoints.gpio])) ~= numel(endpoints) || ...
        numel(unique({endpoints.driverlib_macro})) ~= numel(endpoints) || ...
        numel(unique({endpoints.driverlib_value})) ~= numel(endpoints)
    invalid_schema('SCI endpoints must be unique within each direction.');
end
end

function validate_endpoint(endpoint, moduleId, direction, gpioNumbers)
require_object(endpoint, {'gpio', 'signal', 'mux_selection', ...
    'driverlib_macro', 'driverlib_value'}, 'SCI pin endpoint');
if ~valid_integer(endpoint.gpio, 0, 168) || ...
        ~ismember(endpoint.gpio, gpioNumbers) || ...
        ~valid_integer(endpoint.mux_selection, 0, 15)
    invalid_schema('SCI endpoint GPIO or mux selection is invalid for PTP.');
end
require_text(endpoint.signal, 'SCI endpoint signal');
require_text(endpoint.driverlib_macro, 'SCI endpoint DriverLib macro');
require_text(endpoint.driverlib_value, 'SCI endpoint DriverLib value');
moduleLetter = moduleId(end);
expectedSignal = sprintf('SCI%sXD%s', direction(1), moduleLetter);
expectedMacro = sprintf('GPIO_%u_%s', endpoint.gpio, expectedSignal);
if ~strcmp(endpoint.signal, expectedSignal) || ...
        ~strcmp(endpoint.driverlib_macro, expectedMacro) || ...
        isempty(regexp(endpoint.driverlib_value, '^0x[0-9A-F]{8}U$', 'once'))
    invalid_schema('SCI endpoint signal or DriverLib macro is inconsistent.');
end
encoded = hex2dec(endpoint.driverlib_value(3:10));
if encoded ~= expected_driverlib_value(endpoint.gpio, ...
        endpoint.mux_selection)
    invalid_schema('SCI endpoint DriverLib value is inconsistent with GPIO and mux.');
end
end

function value = expected_driverlib_value(gpio, muxSelection)
bank = floor(gpio / 32);
half = floor(mod(gpio, 32) / 16);
muxOffset = hex2dec('0006') + bank * hex2dec('0040') + half * 2;
shift = mod(gpio, 16) * 2;
value = muxOffset * 2^16 + shift * 2^8 + muxSelection;
end

function capability = normalize_capability(raw)
expectedIds = {'SCI-A', 'SCI-B', 'SCI-C', 'SCI-D'};
modulePrototype = struct('id', '', 'display_name', '', ...
    'rx_endpoints', [], 'tx_endpoints', [], 'pin_groups', []);
modules = repmat(modulePrototype, 1, numel(expectedIds));
for index = 1:numel(expectedIds)
    rawModule = raw.sci_modules(strcmp({raw.sci_modules.id}, expectedIds{index}));
    rxEndpoints = normalize_endpoints(rawModule.rx_endpoints);
    txEndpoints = normalize_endpoints(rawModule.tx_endpoints);
    modules(index).id = rawModule.id;
    modules(index).display_name = rawModule.display_name;
    modules(index).rx_endpoints = rxEndpoints;
    modules(index).tx_endpoints = txEndpoints;
    modules(index).pin_groups = normalize_groups(rawModule.id, ...
        rxEndpoints, txEndpoints);
end
[~, order] = sort([raw.gpio_capabilities.gpio]);
rawGpios = raw.gpio_capabilities(order);
gpioPrototype = struct('number', uint16(0), 'package_pin', uint16(0));
gpios = repmat(gpioPrototype, 1, numel(rawGpios));
for index = 1:numel(rawGpios)
    gpios(index).number = uint16(rawGpios(index).gpio);
    gpios(index).package_pin = uint16(rawGpios(index).package_pin);
end
capability = struct( ...
    'schema_version', uint16(raw.schema_version), ...
    'target', struct('device', raw.target.device, ...
        'package', raw.target.package), ...
    'sci_modules', modules, ...
    'gpios', gpios);
end

function endpoints = normalize_endpoints(rawEndpoints)
[~, order] = sort([rawEndpoints.gpio]);
rawEndpoints = rawEndpoints(order);
endpoint = struct('gpio', uint16(0), 'signal', '', ...
    'mux_selection', uint8(0), 'driverlib_macro', '', ...
    'driverlib_value', '');
endpoints = repmat(endpoint, 1, numel(rawEndpoints));
for index = 1:numel(rawEndpoints)
    endpoints(index) = normalize_endpoint(rawEndpoints(index));
end
end

function groups = normalize_groups(moduleId, rxEndpoints, txEndpoints)
prototype = struct('id', '', 'display_name', '', ...
    'rx', rxEndpoints(1), 'tx', txEndpoints(1));
groups = repmat(prototype, 1, numel(rxEndpoints) * numel(txEndpoints));
groupIndex = 0;
for txIndex = 1:numel(txEndpoints)
    for rxIndex = 1:numel(rxEndpoints)
        groupIndex = groupIndex + 1;
        rx = rxEndpoints(rxIndex);
        tx = txEndpoints(txIndex);
        groups(groupIndex).id = sprintf('%s_TX%u_RX%u', ...
            moduleId, tx.gpio, rx.gpio);
        groups(groupIndex).display_name = sprintf( ...
            'GPIO%u TX / GPIO%u RX', tx.gpio, rx.gpio);
        groups(groupIndex).rx = rx;
        groups(groupIndex).tx = tx;
    end
end
end

function endpoint = normalize_endpoint(raw)
endpoint = struct( ...
    'gpio', uint16(raw.gpio), ...
    'signal', raw.signal, ...
    'mux_selection', uint8(raw.mux_selection), ...
    'driverlib_macro', raw.driverlib_macro, ...
    'driverlib_value', raw.driverlib_value);
end

function require_object(value, fields, location)
if ~isstruct(value) || ~isscalar(value) || ...
        ~isequal(sort(fieldnames(value)), sort(fields(:)))
    invalid_schema('%s has an invalid object structure.', location);
end
end

function require_text(value, location)
if ~(ischar(value) && isrow(value) && ~isempty(value))
    invalid_schema('%s must be nonempty text.', location);
end
end

function valid = valid_integer(value, lowerBound, upperBound)
valid = isnumeric(value) && isscalar(value) && isreal(value) && ...
    isfinite(value) && value == fix(value) && ...
    value >= lowerBound && value <= upperBound;
end

function invalid_schema(message, varargin)
error('C2837xBlock:Capability:InvalidSchema', message, varargin{:});
end
