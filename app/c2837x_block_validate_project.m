function issues = c2837x_block_validate_project(project, mode)
%C2837X_BLOCK_VALIDATE_PROJECT Return all independently discoverable issues.

if nargin < 2
    mode = 'full';
end
mode = char(string(mode));
if ~any(strcmp(mode, {'instant', 'full'}))
    error('C2837xBlock:Validation:InvalidMode', ...
        'Mode must be instant or full.');
end
issues = empty_issues();
try
    c2837x_block_validate_project_structure(project);
catch cause
    issues(end + 1) = make_issue('Error', 'PROJECT_STRUCTURE_INVALID', ...
        cause.message, 'project', 0, '');
    return;
end

if ~strcmp(project.common.dsp_model, 'TMS320F28377D')
    add('Error', 'DSP_MODEL_UNSUPPORTED', 'Unsupported DSP model.', ...
        'project.common.dsp_model', 0, '');
end
if ~any(strcmp(project.common.abi, {'eabi', 'coffabi'}))
    add('Error', 'ABI_UNSUPPORTED', 'ABI must be eabi or coffabi.', ...
        'project.common.abi', 0, '');
end

validate_network();
validate_output_strings();
if isempty(project.instances)
    add('Error', 'PROJECT_HAS_NO_INSTANCES', ...
        'A previewable project requires at least one instance.', ...
        'project.instances', 0, '');
end

validNames = false(1, numel(project.instances));
validSockets = false(1, numel(project.instances));
validPorts = false(1, numel(project.instances));
for instanceIndex = 1:numel(project.instances)
    validate_instance(project.instances(instanceIndex), instanceIndex);
end
validate_unique_resources();

if strcmp(mode, 'full')
    validate_output_filesystem();
    for instanceIndex = 1:numel(project.instances)
        validate_external_source(project.instances(instanceIndex), instanceIndex);
    end
end

    function add(severity, code, message, fieldPath, instanceIndex, filePath)
        issues(end + 1) = make_issue(severity, code, message, ...
            fieldPath, instanceIndex, filePath);
    end

    function validate_network()
        network = project.common.network;
        mac = network.mac;
        if ~isnumeric(mac) || ~isreal(mac) || numel(mac) ~= 6 || ...
                any(~isfinite(mac)) || any(mac ~= fix(mac)) || ...
                any(mac < 0 | mac > 255)
            add('Error', 'MAC_INVALID', 'MAC must contain exactly six octets.', ...
                'project.common.network.mac', 0, '');
        elseif all(mac == 0)
            add('Error', 'MAC_ALL_ZERO', 'MAC must not be all zero.', ...
                'project.common.network.mac', 0, '');
        elseif all(mac == 255)
            add('Error', 'MAC_BROADCAST', 'Broadcast MAC is not allowed.', ...
                'project.common.network.mac', 0, '');
        elseif bitand(uint16(mac(1)), uint16(1)) ~= 0
            add('Error', 'MAC_MULTICAST', 'MAC must be unicast.', ...
                'project.common.network.mac', 0, '');
        end

        [valid, octets] = parse_ipv4(network.ip);
        if ~valid
            add('Error', 'IP_INVALID', 'IP must be dotted decimal IPv4.', ...
                'project.common.network.ip', 0, '');
        elseif all(octets == 0)
            add('Error', 'IP_ALL_ZERO', 'Project IP must not be 0.0.0.0.', ...
                'project.common.network.ip', 0, '');
        elseif all(octets == 255)
            add('Error', 'IP_BROADCAST', 'Project IP must not be broadcast.', ...
                'project.common.network.ip', 0, '');
        end

        [valid, ~] = parse_ipv4(network.gateway);
        if ~valid
            add('Error', 'GATEWAY_INVALID', 'Gateway must be dotted decimal IPv4.', ...
                'project.common.network.gateway', 0, '');
        end

        [valid, octets] = parse_ipv4(network.subnet);
        if ~valid
            add('Error', 'SUBNET_INVALID', 'Subnet must be dotted decimal IPv4.', ...
                'project.common.network.subnet', 0, '');
        elseif all(octets == 0) || ~is_contiguous_mask(octets)
            add('Error', 'SUBNET_NONCONTIGUOUS', ...
                'Subnet must be a nonzero contiguous mask.', ...
                'project.common.network.subnet', 0, '');
        end
    end

    function validate_output_strings()
        dspRoot = project.output.dsp_root;
        sfunRoot = project.output.sfun_root;
        if isempty(dspRoot)
            add('Error', 'DSP_ROOT_REQUIRED', 'DSP output root is required.', ...
                'project.output.dsp_root', 0, '');
        end
        if isempty(sfunRoot)
            add('Error', 'SFUN_ROOT_REQUIRED', 'S-Function output root is required.', ...
                'project.output.sfun_root', 0, '');
        end
        if ~isempty(dspRoot) && ~isempty(sfunRoot)
            if paths_equal(dspRoot, sfunRoot)
                add('Error', 'OUTPUT_ROOTS_EQUAL', ...
                    'Output roots must be different.', 'project.output', 0, '');
            elseif is_descendant(dspRoot, sfunRoot)
                add('Error', 'DSP_ROOT_CONTAINS_SFUN_ROOT', ...
                    'DSP output root must not contain the S-Function root.', ...
                    'project.output', 0, '');
            elseif is_descendant(sfunRoot, dspRoot)
                add('Error', 'SFUN_ROOT_CONTAINS_DSP_ROOT', ...
                    'S-Function output root must not contain the DSP root.', ...
                    'project.output', 0, '');
            end
        end
    end

    function validate_instance(instance, index)
        prefix = sprintf('project.instances(%u)', index);
        if ~is_nonempty_text(instance.display_name)
            add('Error', 'DISPLAY_NAME_REQUIRED', 'Display name is required.', ...
                [prefix '.display_name'], index, '');
        end
        [validNames(index), message] = c2837x_block_validate_name( ...
            instance.internal_name, {});
        if ~validNames(index)
            add('Error', 'INTERNAL_NAME_INVALID', message, ...
                [prefix '.internal_name'], index, '');
        end
        if ~strcmp(instance.iodevice.type, 'w5300_tcp')
            add('Error', 'IODEVICE_UNSUPPORTED', ...
                'IoDevice type must be w5300_tcp.', [prefix '.iodevice.type'], index, '');
        end
        socket = instance.iodevice.settings.socket_number;
        validSockets(index) = is_integer_in_range(socket, 0, 7);
        if ~validSockets(index)
            add('Error', 'SOCKET_INVALID', 'Socket number must be an integer from 0 to 7.', ...
                [prefix '.iodevice.settings.socket_number'], index, '');
        end
        port = instance.iodevice.settings.tcp_port;
        validPorts(index) = is_integer_in_range(port, 1, 65535);
        if ~validPorts(index)
            add('Error', 'TCP_PORT_INVALID', 'TCP port must be an integer from 1 to 65535.', ...
                [prefix '.iodevice.settings.tcp_port'], index, '');
        end
        if ~is_positive_finite_scalar(instance.sample_time_sec)
            add('Error', 'SAMPLE_TIME_INVALID', 'Sample time must be finite and positive.', ...
                [prefix '.sample_time_sec'], index, '');
        end

        inputOctets = validate_variables(instance.inputs, 'inputs', prefix, index);
        outputOctets = validate_variables(instance.outputs, 'outputs', prefix, index);
        validate_payload(instance.max_payload_size_bytes, inputOctets, ...
            outputOctets, prefix, index);
        validate_algorithm(instance.algorithm, prefix, index);
    end

    function octets = validate_variables(variables, label, prefix, index)
        octets = 0;
        if isempty(variables)
            add('Error', ['NO_' upper(label)], ...
                ['At least one ' label(1:end-1) ' is required.'], ...
                [prefix '.' label], index, '');
            octets = NaN;
            return;
        end
        names = {};
        sizes = struct('int16', 2, 'uint16', 2, 'int32', 4, ...
            'uint32', 4, 'single', 4, 'double', 8);
        for variableIndex = 1:numel(variables)
            variable = variables(variableIndex);
            variablePath = sprintf('%s.%s(%u)', prefix, label, variableIndex);
            [valid, message] = c2837x_block_validate_name(variable.name, names);
            if ~valid
                add('Error', 'VARIABLE_NAME_INVALID', message, ...
                    [variablePath '.name'], index, '');
            else
                names{end + 1} = char(variable.name); %#ok<AGROW>
            end
            type = char(variable.type);
            if ~isfield(sizes, type)
                add('Error', 'VARIABLE_TYPE_UNSUPPORTED', ...
                    'Variable type is unsupported or has incorrect case.', ...
                    [variablePath '.type'], index, '');
                continue;
            end
            dim = variable.dim;
            if ~is_positive_integer_scalar(dim)
                add('Error', 'VARIABLE_DIM_INVALID', ...
                    'Variable dim must be a finite positive integer scalar.', ...
                    [variablePath '.dim'], index, '');
                continue;
            end
            if dim > (realmax - octets) / sizes.(type)
                add('Error', 'VARIABLE_SIZE_OVERFLOW', ...
                    'Variable size is too large to calculate safely.', ...
                    [variablePath '.dim'], index, '');
                octets = NaN;
            elseif ~isnan(octets)
                octets = octets + double(dim) * sizes.(type);
            end
        end
        % Inputs and outputs share one name scope; outputs recheck against inputs.
        if strcmp(label, 'outputs')
            inputNames = {project.instances(index).inputs.name};
            for variableIndex = 1:numel(variables)
                [valid, message] = c2837x_block_validate_name( ...
                    variables(variableIndex).name, inputNames);
                if ~valid
                    add('Error', 'VARIABLE_NAME_CONFLICT', message, ...
                        sprintf('%s.outputs(%u).name', prefix, variableIndex), index, '');
                end
            end
        end
    end

    function validate_payload(limit, inputOctets, outputOctets, prefix, index)
        fieldPath = [prefix '.max_payload_size_bytes'];
        if ~is_positive_integer_scalar(limit)
            add('Error', 'MAX_PAYLOAD_INVALID', ...
                'Maximum payload must be a finite positive integer.', fieldPath, index, '');
            return;
        end
        if mod(double(limit), 2) ~= 0
            add('Error', 'MAX_PAYLOAD_ODD', 'Maximum payload must be even.', fieldPath, index, '');
        end
        if limit > 65534
            add('Error', 'MAX_PAYLOAD_TOO_LARGE', ...
                'Maximum payload must not exceed 65534 wire octets.', fieldPath, index, '');
        end
        required = max([6, 4 + inputOctets, 4 + outputOctets]);
        if ~isnan(required) && double(limit) < required
            add('Error', 'MAX_PAYLOAD_TOO_SMALL', ...
                sprintf('Maximum payload must be at least %.0f wire octets.', required), ...
                fieldPath, index, '');
        end
    end

    function validate_algorithm(algorithm, prefix, index)
        path = algorithm.source_path;
        fieldPath = [prefix '.algorithm.source_path'];
        if ~any(strcmp(algorithm.mode, ...
                {'generated_example', 'external_copy', 'external_reference'}))
            add('Error', 'ALGORITHM_MODE_INVALID', 'Algorithm mode is invalid.', ...
                [prefix '.algorithm.mode'], index, '');
        elseif strcmp(algorithm.mode, 'generated_example') && ~isempty(path)
            add('Error', 'GENERATED_ALGORITHM_HAS_SOURCE', ...
                'generated_example requires an empty source path.', fieldPath, index, path);
        elseif ~strcmp(algorithm.mode, 'generated_example') && isempty(path)
            add('Error', 'EXTERNAL_ALGORITHM_SOURCE_REQUIRED', ...
                'External algorithm mode requires a source path.', fieldPath, index, '');
        end
        if strcmp(algorithm.mode, 'external_reference')
            add('Information', 'EXTERNAL_REFERENCE_NOT_COPIED', ...
                'The file is not copied to DSP output; add it to the CCS project.', ...
                fieldPath, index, path);
        end
    end

    function validate_unique_resources()
        for later = 2:numel(project.instances)
            for earlier = 1:later - 1
                if validNames(later) && validNames(earlier) && strcmpi( ...
                        project.instances(later).internal_name, ...
                        project.instances(earlier).internal_name)
                    add('Error', 'INTERNAL_NAME_DUPLICATE', ...
                        'Internal name is already used.', ...
                        sprintf('project.instances(%u).internal_name', later), later, '');
                    validNames(later) = false;
                end
                if validSockets(later) && validSockets(earlier) && isequal( ...
                        project.instances(later).iodevice.settings.socket_number, ...
                        project.instances(earlier).iodevice.settings.socket_number)
                    add('Error', 'SOCKET_DUPLICATE', 'Socket number is already used.', ...
                        sprintf('project.instances(%u).iodevice.settings.socket_number', later), later, '');
                    validSockets(later) = false;
                end
                if validPorts(later) && validPorts(earlier) && isequal( ...
                        project.instances(later).iodevice.settings.tcp_port, ...
                        project.instances(earlier).iodevice.settings.tcp_port)
                    add('Error', 'TCP_PORT_DUPLICATE', 'TCP port is already used.', ...
                        sprintf('project.instances(%u).iodevice.settings.tcp_port', later), later, '');
                    validPorts(later) = false;
                end
            end
        end
    end

    function validate_output_filesystem()
        check_root(project.output.dsp_root, 'project.output.dsp_root', ...
            {'inc', 'src'}, 0);
        instanceFolders = {project.instances.internal_name};
        check_root(project.output.sfun_root, 'project.output.sfun_root', ...
            instanceFolders, 0);
    end

    function check_root(root, fieldPath, requiredChildren, index)
        if isempty(root)
            return;
        end
        if isfile(root)
            add('Error', 'OUTPUT_ROOT_IS_FILE', ...
                'Output root is occupied by a file.', fieldPath, index, root);
            return;
        end
        if isfolder(root)
            readable = path_is_readable(root);
            writable = path_is_writable(root);
            if ~readable
                add('Error', 'OUTPUT_ROOT_NOT_READABLE', ...
                    'Output root is not readable.', fieldPath, index, root);
            end
            if ~writable
                add('Error', 'OUTPUT_ROOT_NOT_WRITABLE', ...
                    'Output root is not writable.', fieldPath, index, root);
            end
            if readable
                try
                    entries = dir(root);
                    if any(~ismember({entries.name}, {'.', '..'}))
                        add('Warning', 'OUTPUT_ROOT_NONEMPTY', ...
                            'Directory may contain another project or old generated files; ownership is not inferred.', ...
                            fieldPath, index, root);
                    end
                catch
                    add('Error', 'OUTPUT_ROOT_ENUMERATION_FAILED', ...
                        'Output root contents could not be enumerated.', ...
                        fieldPath, index, root);
                end
            end
        else
            ancestor = nearest_existing_parent(root);
            if isempty(ancestor) || ~isfolder(ancestor)
                add('Error', 'OUTPUT_PARENT_INVALID', ...
                    'Nearest existing output parent must be a directory.', ...
                    fieldPath, index, root);
            else
                readable = path_is_readable(ancestor);
                writable = path_is_writable(ancestor);
                if ~readable
                    add('Error', 'OUTPUT_PARENT_NOT_READABLE', ...
                        'Nearest existing output parent is not readable.', ...
                        fieldPath, index, root);
                end
                if ~writable
                    add('Error', 'OUTPUT_PARENT_NOT_WRITABLE', ...
                        'Nearest existing output parent is not writable.', ...
                        fieldPath, index, root);
                end
                if readable && writable
                    add('Information', 'OUTPUT_ROOT_WILL_CREATE', ...
                        'Output root does not exist and will be created during generation.', ...
                        fieldPath, index, root);
                end
            end
        end
        for childIndex = 1:numel(requiredChildren)
            child = fullfile(root, requiredChildren{childIndex});
            if isfile(child)
                add('Error', 'REQUIRED_DIRECTORY_IS_FILE', ...
                    'A file occupies a required output directory.', fieldPath, index, child);
            end
        end
    end

    function validate_external_source(instance, index)
        if ~any(strcmp(instance.algorithm.mode, {'external_copy', 'external_reference'})) || ...
                isempty(instance.algorithm.source_path)
            return;
        end
        path = instance.algorithm.source_path;
        fieldPath = sprintf('project.instances(%u).algorithm.source_path', index);
        if ~isfile(path)
            if isfolder(path)
                code = 'ALGORITHM_SOURCE_IS_DIRECTORY';
                message = 'External algorithm source must be a regular file.';
            else
                code = 'ALGORITHM_SOURCE_MISSING';
                message = 'External algorithm source does not exist.';
            end
            add('Error', code, message, fieldPath, index, path);
            return;
        end
        [validExtension, reliable] = has_c_extension_identity(path);
        if ~reliable
            add('Error', 'ALGORITHM_SOURCE_IDENTITY_UNKNOWN', ...
                'Could not reliably determine .c file identity.', fieldPath, index, path);
        elseif ~validExtension
            add('Error', 'ALGORITHM_SOURCE_EXTENSION_INVALID', ...
                'External algorithm source extension must be .c under current filesystem semantics.', ...
                fieldPath, index, path);
        end
        fileID = fopen(path, 'r');
        if fileID < 0
            add('Error', 'ALGORITHM_SOURCE_UNREADABLE', ...
                'External algorithm source is not readable.', fieldPath, index, path);
        else
            cleanup = onCleanup(@() fclose(fileID));
        end
    end
end

function [valid, octets] = parse_ipv4(value)
octets = [];
if ~(ischar(value) && (isrow(value) || isempty(value))) && ...
        ~(isstring(value) && isscalar(value))
    valid = false;
    return;
end
tokens = regexp(char(value), '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$', 'tokens', 'once');
if isempty(tokens)
    valid = false;
    return;
end
octets = cellfun(@(token) sscanf(token, '%u'), tokens);
valid = all(octets <= 255);
end

function tf = is_contiguous_mask(octets)
bits = dec2bin(octets, 8).';
bits = bits(:).';
tf = isempty(strfind(bits, '01')); %#ok<STREMP>
end

function [tf, reliable] = has_c_extension_identity(path)
[folder, name, extension] = fileparts(path);
if strcmp(extension, '.c')
    tf = true;
    reliable = true;
    return;
end
if ~strcmp(extension, '.C')
    tf = false;
    reliable = true;
    return;
end
literalPath = fullfile(folder, [name '.c']);
try
    selected = java.io.File(path);
    literal = java.io.File(literalPath);
    tf = java.nio.file.Files.isSameFile(selected.toPath(), literal.toPath());
    reliable = true;
catch
    tf = false;
    reliable = false;
end
end

function ancestor = nearest_existing_parent(path)
ancestor = path;
while ~isempty(ancestor) && ~isfolder(ancestor) && ~isfile(ancestor)
    parent = fileparts(ancestor);
    if strcmp(parent, ancestor)
        ancestor = '';
        return;
    end
    ancestor = parent;
end
end

function tf = path_is_readable(path)
try
    file = java.io.File(path);
    tf = java.nio.file.Files.isReadable(file.toPath());
catch
    tf = false;
end
end

function tf = path_is_writable(path)
try
    file = java.io.File(path);
    tf = java.nio.file.Files.isWritable(file.toPath());
catch
    tf = false;
end
end

function tf = paths_equal(left, right)
if ispc
    tf = strcmpi(left, right);
else
    tf = strcmp(left, right);
end
end

function tf = is_descendant(parent, child)
if paths_equal(parent, child)
    tf = false;
    return;
end
if endsWith(parent, filesep)
    prefix = parent;
else
    prefix = [parent filesep];
end
if ispc
    tf = startsWith(child, prefix, 'IgnoreCase', true);
else
    tf = startsWith(child, prefix);
end
end

function tf = is_nonempty_text(value)
tf = ((ischar(value) && isrow(value)) || ...
    (isstring(value) && isscalar(value))) && ~isempty(char(value));
end

function tf = is_positive_finite_scalar(value)
tf = isnumeric(value) && isscalar(value) && isreal(value) && ...
    isfinite(value) && value > 0;
end

function tf = is_positive_integer_scalar(value)
tf = is_positive_finite_scalar(value) && value == fix(value);
end

function tf = is_integer_in_range(value, minimum, maximum)
tf = isnumeric(value) && isscalar(value) && isreal(value) && ...
    isfinite(value) && value == fix(value) && value >= minimum && value <= maximum;
end

function value = make_issue(severity, code, message, fieldPath, instanceIndex, filePath)
value = struct('severity', severity, 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', instanceIndex, 'file_path', filePath);
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end
