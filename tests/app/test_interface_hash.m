classdef test_interface_hash < matlab.unittest.TestCase
    properties (TestParameter)
        typeCase = struct( ...
            'int16', struct('type', 'int16', 'octets', 2), ...
            'uint16', struct('type', 'uint16', 'octets', 2), ...
            'int32', struct('type', 'int32', 'octets', 4), ...
            'uint32', struct('type', 'uint32', 'octets', 4), ...
            'single', struct('type', 'single', 'octets', 4), ...
            'double', struct('type', 'double', 'octets', 8))
        sensitiveCase = struct( ...
            'inputName', @change_input_name, ...
            'inputCase', @change_input_case, ...
            'inputType', @change_input_type, ...
            'inputDim', @change_input_dim, ...
            'inputOrder', @change_input_order, ...
            'outputName', @change_output_name, ...
            'outputType', @change_output_type, ...
            'outputDim', @change_output_dim, ...
            'outputOrder', @change_output_order, ...
            'maxPayload', @change_max_payload)
        excludedCase = struct( ...
            'formatVersion', @change_format_version, ...
            'displayName', @change_display_name, ...
            'internalName', @change_internal_name, ...
            'abi', @change_abi, ...
            'mac', @change_mac, ...
            'ip', @change_ip, ...
            'gateway', @change_gateway, ...
            'subnet', @change_subnet, ...
            'iodeviceType', @change_iodevice_type, ...
            'socket', @change_socket, ...
            'port', @change_port, ...
            'sampleTime', @change_sample_time, ...
            'dspRoot', @change_dsp_root, ...
            'sfunRoot', @change_sfun_root, ...
            'algorithmMode', @change_algorithm_mode, ...
            'algorithmPath', @change_algorithm_path, ...
            'savedHash', @change_saved_hash)
        invalidIndex = struct('zero', 0, 'negative', -1, 'fraction', 1.5, ...
            'nan', NaN, 'inf', Inf, 'outOfRange', 2)
        invalidDim = struct('zero', 0, 'negative', -1, 'fraction', 1.5, ...
            'vector', [1 2], 'nan', NaN, 'inf', Inf)
        invalidPayload = struct('zero', 0, 'odd', 7, 'tooLarge', 65536, ...
            'belowFixedMessage', 4)
    end

    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testGoldenVector(testCase)
            project = golden_project();
            expected = golden_text();

            [text, hash, metrics] = c2837x_block_build_interface_hash(project, 1);
            [secondText, secondHash, secondMetrics] = ...
                c2837x_block_build_interface_hash(project, 1);
            utf8 = unicode2native(text, 'UTF-8');

            testCase.verifyEqual(text, expected);
            testCase.verifyEqual(numel(utf8), 392);
            testCase.verifyEqual(metrics.canonical_utf8_octets, 392);
            testCase.verifyClass(hash, 'uint32');
            testCase.verifyEqual(hash, uint32(hex2dec('E45D900C')));
            testCase.verifyFalse(any(text == char(13)));
            testCase.verifyNotEqual(text(end), char(10)); %#ok<CHARTEN>
            testCase.verifyFalse(startsWithBytes(utf8, uint8([239 187 191])));
            testCase.verifyEqual({secondText, secondHash, secondMetrics}, ...
                {text, hash, metrics});
        end

        function testFixedLineFormat(testCase)
            text = c2837x_block_build_interface_hash(golden_project(), 1);
            lines = strsplit(text, char(10)); %#ok<CHARTEN>

            testCase.verifyEqual(numel(lines), 18);
            testCase.verifyEqual(lines(1:6), { ...
                'protocol_version=1', 'wire_endianness=little', ...
                'step_index_type=uint32', 'step_index_octets=4', ...
                'step_index_offset_octets=0', 'input_count=1'});
            testCase.verifyEqual(lines(7:10), { ...
                'input[0].name=input_value', 'input[0].type=single', ...
                'input[0].dim=1', 'input[0].element_octets=4'});
            testCase.verifyEqual(lines(11:15), { ...
                'output_count=1', 'output[0].name=output_value', ...
                'output[0].type=single', 'output[0].dim=1', ...
                'output[0].element_octets=4'});
            testCase.verifyEmpty(regexp(text, '=0\d|=\d+[eE][+-]?\d+', 'once'));
        end

        function testTypeMappingAndPayload(testCase, typeCase)
            project = golden_project();
            project.instances.inputs.type = typeCase.type;

            [text, ~, metrics] = c2837x_block_build_interface_hash(project, 1);

            testCase.verifyEqual(metrics.input_data_octets, typeCase.octets);
            testCase.verifyEqual(metrics.input_payload_octets, 4 + typeCase.octets);
            testCase.verifyTrue(contains(text, sprintf( ...
                'input[0].element_octets=%u', typeCase.octets)));
        end

        function testParticipatingFieldsChangeHash(testCase, sensitiveCase)
            project = ordered_project();
            [~, baseline] = c2837x_block_build_interface_hash(project, 1);
            changed = sensitiveCase(project);

            [~, actual] = c2837x_block_build_interface_hash(changed, 1);

            testCase.verifyNotEqual(actual, baseline);
        end

        function testExcludedFieldsDoNotChangeHash(testCase, excludedCase)
            project = ordered_project();
            [baselineText, baselineHash] = c2837x_block_build_interface_hash(project, 1);
            changed = excludedCase(project);

            [actualText, actualHash] = c2837x_block_build_interface_hash(changed, 1);

            testCase.verifyEqual(actualText, baselineText);
            testCase.verifyEqual(actualHash, baselineHash);
        end

        function testInputOrderChangesTextAndHash(testCase)
            project = ordered_project();
            changed = change_input_order(project);

            [firstText, firstHash] = c2837x_block_build_interface_hash(project, 1);
            [secondText, secondHash] = c2837x_block_build_interface_hash(changed, 1);

            testCase.verifyNotEqual(firstText, secondText);
            testCase.verifyNotEqual(firstHash, secondHash);
        end

        function testOutputOrderChangesTextAndHash(testCase)
            project = ordered_project();
            changed = change_output_order(project);

            [firstText, firstHash] = c2837x_block_build_interface_hash(project, 1);
            [secondText, secondHash] = c2837x_block_build_interface_hash(changed, 1);

            testCase.verifyNotEqual(firstText, secondText);
            testCase.verifyNotEqual(firstHash, secondHash);
        end

        function testLegacyWrapperDelegatesExclusively(testCase)
            config = legacy_config();
            project = golden_project();

            [legacyText, legacyHash] = c2837x_block_build_hash_string(config);
            [newText, newHash] = c2837x_block_build_interface_hash(project, 1);

            testCase.verifyEqual({legacyText, legacyHash}, {newText, newHash});
            testCase.verifyFalse(any(contains(legacyText, { ...
                'protocol=0x', 'abi=', 'dsp_ip=', 'gateway=', 'subnet=', ...
                'tcp_port=', 'socket_num=', 'sample_time_sec=', 'double_mode=', ...
                'input_data_size_bytes=', 'output_data_size_bytes=', ...
                'input_payload_size_bytes=', 'output_payload_size_bytes='})));
        end

        function testLegacyExcludedFieldsDoNotMatter(testCase)
            config = legacy_config();
            [baselineText, baselineHash] = c2837x_block_build_hash_string(config);
            config.abi = 'coffabi';
            config.dsp_ip = '10.0.0.2';
            config.gateway = '10.0.0.1';
            config.subnet = '255.0.0.0';
            config.socket_num = 7;
            config.tcp_port = 6000;
            config.sample_time_sec = 1;
            config.double_mode = 'disabled';

            [actualText, actualHash] = c2837x_block_build_hash_string(config);

            testCase.verifyEqual({actualText, actualHash}, {baselineText, baselineHash});
        end

        function testLegacyMissingRequiredInputFails(testCase)
            config = rmfield(legacy_config(), 'inputs');

            testCase.verifyError(@() c2837x_block_build_hash_string(config), ...
                'C2837xBlock:InterfaceHash:InvalidProject');
        end

        function testProjectAndIndexValidation(testCase, invalidIndex)
            project = golden_project();

            testCase.verifyError( ...
                @() c2837x_block_build_interface_hash(project, invalidIndex), ...
                'C2837xBlock:InterfaceHash:InvalidInstanceIndex');
        end

        function testInvalidProjectShapes(testCase)
            project = golden_project();
            noInstances = rmfield(project, 'instances');

            testCase.verifyError(@() c2837x_block_build_interface_hash([], 1), ...
                'C2837xBlock:InterfaceHash:InvalidProject');
            testCase.verifyError(@() c2837x_block_build_interface_hash(noInstances, 1), ...
                'C2837xBlock:InterfaceHash:InvalidProject');
        end

        function testEmptyInstancesFailsIndex(testCase)
            project = golden_project();
            project.instances = project.instances([]);

            testCase.verifyError(@() c2837x_block_build_interface_hash(project, 1), ...
                'C2837xBlock:InterfaceHash:InvalidInstanceIndex');
        end

        function testProtocolVersionMustBeOne(testCase)
            project = golden_project();
            project.common.protocol_version = uint16(2);

            testCase.verifyError(@() c2837x_block_build_interface_hash(project, 1), ...
                'C2837xBlock:InterfaceHash:InvalidProtocolVersion');
        end

        function testInputAndOutputRequired(testCase)
            project = golden_project();
            noInputs = project;
            noInputs.instances.inputs = noInputs.instances.inputs([]);
            noOutputs = project;
            noOutputs.instances.outputs = noOutputs.instances.outputs([]);

            testCase.verifyError(@() c2837x_block_build_interface_hash(noInputs, 1), ...
                'C2837xBlock:InterfaceHash:InvalidVariable');
            testCase.verifyError(@() c2837x_block_build_interface_hash(noOutputs, 1), ...
                'C2837xBlock:InterfaceHash:InvalidVariable');
        end

        function testSharedNameScopeAndInvalidName(testCase)
            project = golden_project();
            conflict = project;
            conflict.instances.outputs.name = 'INPUT_VALUE';
            invalid = project;
            invalid.instances.inputs.name = '_bad';

            testCase.verifyError(@() c2837x_block_build_interface_hash(conflict, 1), ...
                'C2837xBlock:InterfaceHash:InvalidVariable');
            testCase.verifyError(@() c2837x_block_build_interface_hash(invalid, 1), ...
                'C2837xBlock:InterfaceHash:InvalidVariable');
        end

        function testUnsupportedAndMisCasedTypes(testCase)
            project = golden_project();
            unsupported = project;
            unsupported.instances.inputs.type = 'int8';
            misCased = project;
            misCased.instances.inputs.type = 'Single';

            testCase.verifyError(@() c2837x_block_build_interface_hash(unsupported, 1), ...
                'C2837xBlock:InterfaceHash:InvalidVariable');
            testCase.verifyError(@() c2837x_block_build_interface_hash(misCased, 1), ...
                'C2837xBlock:InterfaceHash:InvalidVariable');
        end

        function testInvalidDimensions(testCase, invalidDim)
            project = golden_project();
            project.instances.inputs.dim = invalidDim;

            testCase.verifyError(@() c2837x_block_build_interface_hash(project, 1), ...
                'C2837xBlock:InterfaceHash:InvalidVariable');
        end

        function testInvalidPayloadLimits(testCase, invalidPayload)
            project = golden_project();
            project.instances.max_payload_size_bytes = invalidPayload;

            testCase.verifyError(@() c2837x_block_build_interface_hash(project, 1), ...
                'C2837xBlock:InterfaceHash:InvalidPayload');
        end

        function testPayloadBelowInputAndOutput(testCase)
            project = golden_project();
            inputTooLarge = project;
            inputTooLarge.instances.inputs.dim = 2;
            inputTooLarge.instances.max_payload_size_bytes = 8;
            outputTooLarge = project;
            outputTooLarge.instances.outputs.dim = 2;
            outputTooLarge.instances.max_payload_size_bytes = 8;

            testCase.verifyError(@() c2837x_block_build_interface_hash(inputTooLarge, 1), ...
                'C2837xBlock:InterfaceHash:InvalidPayload');
            testCase.verifyError(@() c2837x_block_build_interface_hash(outputTooLarge, 1), ...
                'C2837xBlock:InterfaceHash:InvalidPayload');
        end

        function testHugeDimensionFailsSafely(testCase)
            project = golden_project();
            project.instances.inputs.dim = realmax;
            project.instances.max_payload_size_bytes = 65534;

            testCase.verifyError(@() c2837x_block_build_interface_hash(project, 1), ...
                'C2837xBlock:InterfaceHash:InvalidPayload');
        end

        function testPureFunctionDoesNotMutateOrWrite(testCase)
            project = golden_project();
            beforeProject = project;
            beforePwd = pwd;
            folder = tempname;
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            beforeTree = dir(folder);

            c2837x_block_build_interface_hash(project, 1);

            testCase.verifyEqual(project, beforeProject);
            testCase.verifyEqual(pwd, beforePwd);
            testCase.verifyEqual(dir(folder), beforeTree);
        end
    end
end

function project = golden_project()
project = c2837x_block_create_default_project();
instance = c2837x_block_create_default_instance();
instance.inputs = variable('input_value', 'single', 1);
instance.outputs = variable('output_value', 'single', 1);
project.instances = instance;
end

function project = ordered_project()
project = golden_project();
project.instances.inputs = [variable('InputA', 'int16', 1), ...
    variable('InputB', 'uint32', 2)];
project.instances.outputs = [variable('OutputA', 'single', 1), ...
    variable('OutputB', 'double', 2)];
end

function value = variable(name, type, dim)
value = struct('name', name, 'type', type, 'dim', dim);
end

function text = golden_text()
lines = { ...
    'protocol_version=1', ...
    'wire_endianness=little', ...
    'step_index_type=uint32', ...
    'step_index_octets=4', ...
    'step_index_offset_octets=0', ...
    'input_count=1', ...
    'input[0].name=input_value', ...
    'input[0].type=single', ...
    'input[0].dim=1', ...
    'input[0].element_octets=4', ...
    'output_count=1', ...
    'output[0].name=output_value', ...
    'output[0].type=single', ...
    'output[0].dim=1', ...
    'output[0].element_octets=4', ...
    'input_payload_octets=8', ...
    'output_payload_octets=8', ...
    'max_payload_octets=1024'};
text = strjoin(lines, char(10)); %#ok<CHARTEN>
end

function config = legacy_config()
project = golden_project();
config = struct( ...
    'protocol_version', project.common.protocol_version, ...
    'inputs', project.instances.inputs, ...
    'outputs', project.instances.outputs, ...
    'max_payload_size_bytes', project.instances.max_payload_size_bytes, ...
    'abi', 'eabi', 'dsp_ip', '192.168.1.10', 'gateway', '192.168.1.1', ...
    'subnet', '255.255.255.0', 'socket_num', 0, 'tcp_port', 5000, ...
    'sample_time_sec', 1e-4, 'double_mode', 'eabi64');
end

function tf = startsWithBytes(data, prefix)
tf = numel(data) >= numel(prefix) && isequal(data(1:numel(prefix)), prefix);
end

function project = change_input_name(project), project.instances.inputs(1).name = 'ChangedInput'; end
function project = change_input_case(project), project.instances.inputs(1).name = 'inputA'; end
function project = change_input_type(project), project.instances.inputs(1).type = 'uint16'; end
function project = change_input_dim(project), project.instances.inputs(1).dim = 3; end
function project = change_input_order(project), project.instances.inputs = project.instances.inputs([2 1]); end
function project = change_output_name(project), project.instances.outputs(1).name = 'ChangedOutput'; end
function project = change_output_type(project), project.instances.outputs(1).type = 'uint32'; end
function project = change_output_dim(project), project.instances.outputs(1).dim = 3; end
function project = change_output_order(project), project.instances.outputs = project.instances.outputs([2 1]); end
function project = change_max_payload(project), project.instances.max_payload_size_bytes = 2048; end
function project = change_format_version(project), project.format_version = uint16(99); end
function project = change_display_name(project), project.instances.display_name = 'Other'; end
function project = change_internal_name(project), project.instances.internal_name = 'other'; end
function project = change_abi(project), project.common.abi = 'coffabi'; end
function project = change_mac(project), project.common.network.mac = uint8([2 1 2 3 4 5]); end
function project = change_ip(project), project.common.network.ip = '10.0.0.2'; end
function project = change_gateway(project), project.common.network.gateway = '10.0.0.1'; end
function project = change_subnet(project), project.common.network.subnet = '255.0.0.0'; end
function project = change_iodevice_type(project), project.instances.iodevice.type = 'other'; end
function project = change_socket(project), project.instances.iodevice.settings.socket_number = 7; end
function project = change_port(project), project.instances.iodevice.settings.tcp_port = 6000; end
function project = change_sample_time(project), project.instances.sample_time_sec = 1; end
function project = change_dsp_root(project), project.output.dsp_root = canonical_path('hash_dsp'); end
function project = change_sfun_root(project), project.output.sfun_root = canonical_path('hash_sfun'); end
function project = change_algorithm_mode(project), project.instances.algorithm.mode = 'external_reference'; end
function project = change_algorithm_path(project), project.instances.algorithm.source_path = canonical_path('algorithm.c'); end
function project = change_saved_hash(project), project.instances.interface_hash = uint32(123); end

function path = canonical_path(name)
path = c2837x_block_normalize_absolute_path(fullfile(tempdir, name));
end
