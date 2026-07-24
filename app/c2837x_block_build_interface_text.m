function [canonicalText, metrics] = c2837x_block_build_interface_text(protocolVersion, instance)
%C2837X_BLOCK_BUILD_INTERFACE_TEXT Build the V2 Interface Hash text.

if ~isnumeric(protocolVersion) || ~isreal(protocolVersion) || ...
        ~isscalar(protocolVersion) || ~isfinite(protocolVersion) || ...
        protocolVersion ~= fix(protocolVersion) || protocolVersion ~= 1
    error('C2837xBlock:InterfaceHash:InvalidProtocolVersion', ...
        'protocol_version must equal 1.');
end
if ~isstruct(instance) || ~isscalar(instance) || ...
        ~all(isfield(instance, {'inputs', 'outputs', 'max_payload_size_bytes'}))
    error('C2837xBlock:InterfaceHash:InvalidProject', ...
        'The instance must contain inputs, outputs, and max_payload_size_bytes.');
end

maxPayload = instance.max_payload_size_bytes;
if ~isnumeric(maxPayload) || ~isreal(maxPayload) || ~isscalar(maxPayload) || ...
        ~isfinite(maxPayload) || maxPayload ~= fix(maxPayload) || ...
        maxPayload < 6 || maxPayload > 65534 || mod(double(maxPayload), 2) ~= 0
    error('C2837xBlock:InterfaceHash:InvalidPayload', ...
        'max_payload_size_bytes must be an even integer from 6 through 65534.');
end
maxPayload = double(maxPayload);

[inputLines, inputData, names] = variable_lines(instance.inputs, 'input', {});
[outputLines, outputData] = variable_lines(instance.outputs, 'output', names);
inputPayload = 4 + inputData;
outputPayload = 4 + outputData;
if maxPayload < inputPayload || maxPayload < outputPayload
    error('C2837xBlock:InterfaceHash:InvalidPayload', ...
        'max_payload_size_bytes is smaller than an interface payload.');
end

lines = { ...
    'protocol_version=1', ...
    'wire_endianness=little', ...
    'step_index_type=uint32', ...
    'step_index_octets=4', ...
    'step_index_offset_octets=0', ...
    sprintf('input_count=%u', numel(instance.inputs))};
lines = [lines, inputLines, {sprintf('output_count=%u', numel(instance.outputs))}, ...
    outputLines, { ...
    sprintf('input_payload_octets=%u', inputPayload), ...
    sprintf('output_payload_octets=%u', outputPayload), ...
    sprintf('max_payload_octets=%u', maxPayload)}];
canonicalText = strjoin(lines, char(10)); %#ok<CHARTEN>

try
    utf8Data = unicode2native(canonicalText, 'UTF-8');
catch cause
    failure = MException('C2837xBlock:InterfaceHash:EncodingFailed', ...
        'Interface text could not be encoded as UTF-8.');
    throwAsCaller(addCause(failure, cause));
end
metrics = struct( ...
    'input_data_octets', inputData, ...
    'output_data_octets', outputData, ...
    'input_payload_octets', inputPayload, ...
    'output_payload_octets', outputPayload, ...
    'max_payload_octets', maxPayload, ...
    'canonical_utf8_octets', numel(utf8Data));
end

function [lines, dataOctets, names] = variable_lines(variables, label, existingNames)
if ~isstruct(variables) || isempty(variables) || ...
        ~all(isfield(variables, {'name', 'type', 'dim'}))
    error('C2837xBlock:InterfaceHash:InvalidVariable', ...
        '%ss must be a nonempty struct array with name, type, and dim.', label);
end

lines = {};
dataOctets = 0;
names = existingNames;
for index = 1:numel(variables)
    variable = variables(index);
    [valid, message] = c2837x_block_validate_name(variable.name, names);
    if ~valid
        error('C2837xBlock:InterfaceHash:InvalidVariable', '%s', message);
    end
    name = char(variable.name);
    names{end + 1} = name; %#ok<AGROW>

    if ~((ischar(variable.type) && isrow(variable.type)) || ...
            (isstring(variable.type) && isscalar(variable.type)))
        invalid_type();
    end
    type = char(variable.type);
    elementOctets = type_octets(type);
    dim = variable.dim;
    if ~isnumeric(dim) || ~isreal(dim) || ~isscalar(dim) || ...
            ~isfinite(dim) || dim <= 0 || dim ~= fix(dim)
        error('C2837xBlock:InterfaceHash:InvalidVariable', ...
            'Variable dim must be a finite positive integer scalar.');
    end
    dim = double(dim);
    if dim > floor((65530 - dataOctets) / elementOctets)
        error('C2837xBlock:InterfaceHash:InvalidPayload', ...
            'Interface data exceeds the supported payload range.');
    end
    dataOctets = dataOctets + dim * elementOctets;
    prefix = sprintf('%s[%u]', label, index - 1);
    lines(end + 1:end + 4) = { ...
        sprintf('%s.name=%s', prefix, name), ...
        sprintf('%s.type=%s', prefix, type), ...
        sprintf('%s.dim=%u', prefix, dim), ...
        sprintf('%s.element_octets=%u', prefix, elementOctets)};
end
end

function octets = type_octets(type)
switch type
    case {'int16', 'uint16'}
        octets = 2;
    case {'int32', 'uint32', 'single'}
        octets = 4;
    case 'double'
        octets = 8;
    otherwise
        invalid_type();
end
end

function invalid_type()
error('C2837xBlock:InterfaceHash:InvalidVariable', ...
    'Variable type must be int16, uint16, int32, uint32, single, or double.');
end
