classdef test_project_validation < matlab.unittest.TestCase
    properties (TestParameter)
        supportedType = {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'}
        invalidIPv4 = struct('fields', '1.2.3', 'text', '1.a.3.4', ...
            'fraction', '1.2.3.4.5', 'scientific', '1.2.3.1e2', 'range', '1.2.3.256')
        invalidDim = struct('zero', 0, 'negative', -1, 'fraction', 1.5, ...
            'vector', [1 2], 'nan', NaN, 'inf', Inf)
    end

    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'app', 'fixtures')));
        end
    end

    methods (TestMethodSetup)
        function createWorkFolder(testCase)
            testCase.WorkFolder = c2837x_block_normalize_absolute_path(tempname);
            mkdir(testCase.WorkFolder);
            testCase.addTeardown(@() rmdir(testCase.WorkFolder, 's'));
        end
    end

    methods (Test)
        function testIssueShapeOrderAndNoMutation(testCase)
            project = valid_project(testCase.WorkFolder);
            project.common.dsp_model = 'bad';
            project.common.abi = 'bad';
            before = project;
            first = c2837x_block_validate_project(project, 'instant');
            second = c2837x_block_validate_project(project, 'instant');
            testCase.verifyEqual(first, second);
            testCase.verifyEqual(project, before);
            testCase.verifyEqual(fieldnames(first), ...
                {'severity'; 'code'; 'message'; 'field_path'; 'instance_index'; 'file_path'});
            testCase.verifyEqual({first(1:2).code}, {'DSP_MODEL_UNSUPPORTED', 'ABI_UNSUPPORTED'});
        end

        function testMalformedParentReturnsOneIssue(testCase)
            project = struct('format_version', uint16(2));
            issues = c2837x_block_validate_project(project);
            testCase.verifyNumElements(issues, 1);
            testCase.verifyEqual(issues.code, 'PROJECT_STRUCTURE_INVALID');
        end

        function testEmptyProjectFailsFullValidation(testCase)
            project = c2837x_block_create_default_project();
            issues = c2837x_block_validate_project(project, 'instant');
            testCase.verifyTrue(any(strcmp({issues.code}, 'PROJECT_HAS_NO_INSTANCES')));
        end

        function testUnknownIoDeviceDoesNotUseW5300Validation(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances.iodevice.type = 'other';
            project.instances.iodevice.settings.socket_number = 8.5;
            project.instances.iodevice.settings.tcp_port = 0;
            codes = {c2837x_block_validate_project(project, 'instant').code};
            testCase.verifyTrue(any(strcmp(codes, 'IODEVICE_UNSUPPORTED')));
            testCase.verifyFalse(any(ismember(codes, ...
                {'SOCKET_INVALID', 'TCP_PORT_INVALID'})));
        end

        function testInvalidW5300ResourcesAndSampleTime(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances.iodevice.settings.socket_number = 8.5;
            project.instances.iodevice.settings.tcp_port = 0;
            project.instances.sample_time_sec = -1;
            codes = {c2837x_block_validate_project(project, 'instant').code};
            testCase.verifyTrue(all(ismember({'SOCKET_INVALID', ...
                'TCP_PORT_INVALID', 'SAMPLE_TIME_INVALID'}, codes)));
        end

        function testProviderOwnsItsSettingsStructure(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances.iodevice.type = 'test_provider';
            project.instances.iodevice.settings = struct('channel_id', 0);

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyTrue(any(strcmp({issues.code}, 'TEST_CHANNEL_INVALID')));
            testCase.verifyFalse(any(strcmp({issues.code}, 'PROJECT_STRUCTURE_INVALID')));
        end

        function testMissingW5300SocketUsesProviderValidation(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances.iodevice.settings = struct('tcp_port', 5000);

            issues = c2837x_block_validate_project(project, 'instant');
            codes = {issues.code};

            testCase.verifyEqual(codes(strcmp(codes, 'SOCKET_INVALID')), ...
                {'SOCKET_INVALID'});
            testCase.verifyFalse(any(strcmp(codes, 'PROJECT_STRUCTURE_INVALID')));
        end

        function testMissingW5300PortUsesProviderValidation(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances.iodevice.settings = struct('socket_number', 1);

            issues = c2837x_block_validate_project(project, 'instant');
            codes = {issues.code};

            testCase.verifyEqual(codes(strcmp(codes, 'TCP_PORT_INVALID')), ...
                {'TCP_PORT_INVALID'});
            testCase.verifyFalse(any(strcmp(codes, 'PROJECT_STRUCTURE_INVALID')));
        end

        function testMissingBothW5300FieldsUsesProviderValidation(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances.iodevice.settings = struct();

            issues = c2837x_block_validate_project(project, 'instant');
            codes = {issues.code};

            testCase.verifyEqual(codes(ismember(codes, ...
                {'SOCKET_INVALID', 'TCP_PORT_INVALID'})), ...
                {'SOCKET_INVALID', 'TCP_PORT_INVALID'});
            testCase.verifyFalse(any(strcmp(codes, 'PROJECT_STRUCTURE_INVALID')));
        end

        function testW5300InstanceLimitPreservesResourceIssues(testCase)
            project = valid_project(testCase.WorkFolder);
            template = project.instances;
            instances = repmat(template, 1, 9);
            for index = 1:9
                instances(index).display_name = sprintf('Motor %u', index);
                instances(index).internal_name = sprintf('motor_%u', index);
                instances(index).iodevice.settings.socket_number = mod(index - 1, 8);
                instances(index).iodevice.settings.tcp_port = 4999 + index;
            end
            project.instances = instances(1:8);
            testCase.verifyFalse(has_code(project, ...
                'IODEVICE_INSTANCE_LIMIT_EXCEEDED'));

            project.instances = instances;
            issues = c2837x_block_validate_project(project, 'instant');
            limit = issues(strcmp({issues.code}, ...
                'IODEVICE_INSTANCE_LIMIT_EXCEEDED'));
            testCase.verifyNumElements(limit, 1);
            testCase.verifyEqual(limit.instance_index, 0);
            testCase.verifyNotEmpty(strfind(limit.message, 'w5300_tcp'));
            testCase.verifyNotEmpty(strfind(limit.message, '9'));
            testCase.verifyNotEmpty(strfind(limit.message, '8'));
            testCase.verifyTrue(any(strcmp({issues.code}, 'SOCKET_DUPLICATE')));
        end

        function testDuplicateResourcesLocateLaterInstance(testCase)
            project = valid_project(testCase.WorkFolder);
            second = project.instances;
            second.display_name = 'Second';
            second.internal_name = upper(second.internal_name);
            project.instances(2) = second;
            issues = c2837x_block_validate_project(project, 'instant');
            duplicate = issues(ismember({issues.code}, ...
                {'INTERNAL_NAME_DUPLICATE', 'SOCKET_DUPLICATE', 'TCP_PORT_DUPLICATE'}));
            testCase.verifyNumElements(duplicate, 3);
            testCase.verifyEqual([duplicate.instance_index], [2 2 2]);
        end

        function testGeneratedCNameConflictLocatesLaterInstance(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances(1).internal_name = 'axis_x';
            second = project.instances(1);
            second.display_name = 'Second';
            second.internal_name = 'axisX';
            second.iodevice.settings.socket_number = uint16(1);
            second.iodevice.settings.tcp_port = uint16(5001);
            project.instances(2) = second;

            issues = c2837x_block_validate_project(project, 'instant');
            conflict = issues(strcmp({issues.code}, ...
                'GENERATED_C_NAME_CONFLICT'));

            testCase.verifyNumElements(conflict, 1);
            testCase.verifyEqual(conflict.severity, 'Error');
            testCase.verifyEqual(conflict.instance_index, 2);
            testCase.verifyEqual(conflict.field_path, ...
                'project.instances(2).internal_name');
            testCase.verifyTrue(contains(conflict.message, 'axis_x'));
            testCase.verifyTrue(contains(conflict.message, 'axisX'));
            testCase.verifyTrue(contains(conflict.message, 'AxisX'));
        end

        function testDuplicateSocketAcrossNumericClasses(testCase)
            project = valid_project(testCase.WorkFolder);
            second = project.instances;
            second.display_name = 'Second';
            second.internal_name = 'second';
            second.iodevice.settings.socket_number = double(0);
            second.iodevice.settings.tcp_port = double(5001);
            project.instances(2) = second;
            issues = c2837x_block_validate_project(project, 'instant');
            duplicate = issues(strcmp({issues.code}, 'SOCKET_DUPLICATE'));
            testCase.verifyNumElements(duplicate, 1);
            testCase.verifyEqual(duplicate.instance_index, 2);
            testCase.verifyEqual(duplicate.field_path, ...
                'project.instances(2).iodevice.settings.socket_number');
        end

        function testDuplicatePortAcrossNumericClasses(testCase)
            project = valid_project(testCase.WorkFolder);
            second = project.instances;
            second.display_name = 'Second';
            second.internal_name = 'second';
            second.iodevice.settings.socket_number = double(1);
            second.iodevice.settings.tcp_port = double(5000);
            project.instances(2) = second;
            issues = c2837x_block_validate_project(project, 'instant');
            duplicate = issues(strcmp({issues.code}, 'TCP_PORT_DUPLICATE'));
            testCase.verifyNumElements(duplicate, 1);
            testCase.verifyEqual(duplicate.instance_index, 2);
            testCase.verifyEqual(duplicate.field_path, ...
                'project.instances(2).iodevice.settings.tcp_port');
        end

        function testDifferentValuesAcrossNumericClassesAreNotDuplicates(testCase)
            project = valid_project(testCase.WorkFolder);
            second = project.instances;
            second.display_name = 'Second';
            second.internal_name = 'second';
            second.iodevice.settings.socket_number = double(1);
            second.iodevice.settings.tcp_port = double(5001);
            project.instances(2) = second;
            issues = c2837x_block_validate_project(project, 'instant');
            testCase.verifyFalse(any(ismember({issues.code}, ...
                {'SOCKET_DUPLICATE', 'TCP_PORT_DUPLICATE'})));
        end

        function testNetworkRules(testCase)
            project = valid_project(testCase.WorkFolder);
            project.common.network.mac = [0 0 0 0 0 0];
            project.common.network.ip = '0.0.0.0';
            project.common.network.gateway = '0.0.0.0';
            project.common.network.subnet = '255.0.255.0';
            codes = {c2837x_block_validate_project(project, 'instant').code};
            testCase.verifyTrue(all(ismember( ...
                {'MAC_ALL_ZERO', 'IP_ALL_ZERO', 'SUBNET_NONCONTIGUOUS'}, codes)));
            testCase.verifyFalse(any(strcmp(codes, 'GATEWAY_INVALID')));
        end

        function testBroadcastAndMulticastMac(testCase)
            project = valid_project(testCase.WorkFolder);
            project.common.network.mac = 255 * ones(1, 6);
            testCase.verifyTrue(has_code(project, 'MAC_BROADCAST'));
            project.common.network.mac = [1 2 3 4 5 6];
            testCase.verifyTrue(has_code(project, 'MAC_MULTICAST'));
        end

        function testInvalidIPv4Forms(testCase, invalidIPv4)
            project = valid_project(testCase.WorkFolder);
            project.common.network.ip = invalidIPv4;
            testCase.verifyTrue(has_code(project, 'IP_INVALID'));
        end

        function testSupportedWireSizes(testCase, supportedType)
            project = valid_project(testCase.WorkFolder);
            project.instances.inputs.type = supportedType;
            project.instances.max_payload_size_bytes = uint32(65534);
            issues = c2837x_block_validate_project(project, 'instant');
            testCase.verifyFalse(any(strcmp({issues.code}, 'VARIABLE_TYPE_UNSUPPORTED')));
        end

        function testTypeCaseAndDimensions(testCase, invalidDim)
            project = valid_project(testCase.WorkFolder);
            project.instances.inputs.type = 'Single';
            project.instances.outputs.dim = invalidDim;
            codes = {c2837x_block_validate_project(project, 'instant').code};
            testCase.verifyTrue(ismember('VARIABLE_TYPE_UNSUPPORTED', codes));
            testCase.verifyTrue(ismember('VARIABLE_DIM_INVALID', codes));
        end

        function testPayloadRulesAndHugeDimension(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances.max_payload_size_bytes = 5;
            project.instances.inputs.dim = realmax;
            codes = {c2837x_block_validate_project(project, 'instant').code};
            testCase.verifyTrue(all(ismember({'MAX_PAYLOAD_ODD', ...
                'VARIABLE_SIZE_OVERFLOW'}, codes)));
        end

        function testWireOctetMappingAndSharedNameScope(testCase)
            types = {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'};
            sizes = [2 2 4 4 4 8];
            for index = 1:numel(types)
                project = valid_project(testCase.WorkFolder);
                project.instances.inputs.type = types{index};
                project.instances.max_payload_size_bytes = uint32(max(6, 4 + sizes(index)) - 2);
                testCase.verifyTrue(has_code(project, 'MAX_PAYLOAD_TOO_SMALL'));
            end
            project = valid_project(testCase.WorkFolder);
            project.instances.outputs.name = upper(project.instances.inputs.name);
            testCase.verifyTrue(has_code(project, 'VARIABLE_NAME_CONFLICT'));
        end

        function testMissingIoAndAlgorithmPathConsistency(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances.inputs = project.instances.inputs([]);
            project.instances.outputs = project.instances.outputs([]);
            project.instances.algorithm.mode = 'external_copy';
            codes = {c2837x_block_validate_project(project, 'instant').code};
            testCase.verifyTrue(all(ismember({'NO_INPUTS', 'NO_OUTPUTS', ...
                'EXTERNAL_ALGORITHM_SOURCE_REQUIRED'}, codes)));
        end

        function testOutputRelationships(testCase)
            project = valid_project(testCase.WorkFolder);
            project.output.sfun_root = project.output.dsp_root;
            testCase.verifyTrue(has_code(project, 'OUTPUT_ROOTS_EQUAL'));
            project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
                fullfile(project.output.dsp_root, 'child'));
            testCase.verifyTrue(has_code(project, 'DSP_ROOT_CONTAINS_SFUN_ROOT'));
            project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
                [project.output.dsp_root '2']);
            testCase.verifyFalse(has_code(project, 'DSP_ROOT_CONTAINS_SFUN_ROOT'));
        end

        function testWindowsRootOutputRelationships(testCase)
            testCase.assumeTrue(ispc);
            driveRoot = filesystem_root(testCase.WorkFolder);
            project = valid_project(testCase.WorkFolder);
            project.output.dsp_root = driveRoot;
            project.output.sfun_root = fullfile(driveRoot, 'generated_sfun');
            testCase.verifyTrue(has_code(project, 'DSP_ROOT_CONTAINS_SFUN_ROOT'));
            project.output.sfun_root = driveRoot;
            project.output.dsp_root = fullfile(driveRoot, 'generated_dsp');
            testCase.verifyTrue(has_code(project, 'SFUN_ROOT_CONTAINS_DSP_ROOT'));
        end

        function testUnixRootOutputRelationships(testCase)
            testCase.assumeFalse(ispc);
            project = valid_project(testCase.WorkFolder);
            project.output.dsp_root = filesep;
            project.output.sfun_root = fullfile(filesep, 'generated_sfun');
            testCase.verifyTrue(has_code(project, 'DSP_ROOT_CONTAINS_SFUN_ROOT'));
            project.output.sfun_root = filesep;
            project.output.dsp_root = fullfile(filesep, 'generated_dsp');
            testCase.verifyTrue(has_code(project, 'SFUN_ROOT_CONTAINS_DSP_ROOT'));
        end

        function testFullOutputChecksDoNotCreate(testCase)
            project = valid_project(testCase.WorkFolder);
            before = tree(testCase.WorkFolder);
            issues = c2837x_block_validate_project(project, 'full');
            testCase.verifyEqual(tree(testCase.WorkFolder), before);
            testCase.verifyGreaterThanOrEqual(sum(strcmp({issues.code}, ...
                'OUTPUT_ROOT_WILL_CREATE')), 2);
        end

        function testExistingOutputWarningsAndRequiredDirectoryConflict(testCase)
            project = valid_project(testCase.WorkFolder);
            mkdir(project.output.dsp_root);
            fileID = fopen(fullfile(project.output.dsp_root, 'inc'), 'w'); fclose(fileID);
            issues = c2837x_block_validate_project(project, 'full');
            testCase.verifyTrue(any(strcmp({issues.code}, 'OUTPUT_ROOT_NONEMPTY')));
            testCase.verifyTrue(any(strcmp({issues.code}, 'REQUIRED_DIRECTORY_IS_FILE')));
            testCase.verifyTrue(any(strcmp({issues.severity}, 'Warning')));
            testCase.verifyTrue(any(strcmp({issues.severity}, 'Information')));
        end

        function testEmptyAndNonemptyRootsAreEnumeratedIndependently(testCase)
            project = valid_project(testCase.WorkFolder);
            mkdir(project.output.dsp_root);
            mkdir(project.output.sfun_root);
            fileID = fopen(fullfile(project.output.sfun_root, 'existing.txt'), 'w');
            fclose(fileID);
            before = tree(testCase.WorkFolder);
            issues = c2837x_block_validate_project(project, 'full');
            warnings = issues(strcmp({issues.code}, 'OUTPUT_ROOT_NONEMPTY'));
            testCase.verifyEqual({warnings.file_path}, {project.output.sfun_root});
            testCase.verifyEqual(tree(testCase.WorkFolder), before);
        end

        function testUnreadableOutputRootOnUnix(testCase)
            testCase.assumeFalse(ispc);
            project = valid_project(testCase.WorkFolder);
            mkdir(project.output.dsp_root);
            mkdir(project.output.sfun_root);
            fileID = fopen(fullfile(project.output.sfun_root, 'existing.txt'), 'w');
            fclose(fileID);
            restrict_permissions(testCase, project.output.dsp_root, 'a-r');
            testCase.assumeFalse(path_is_readable_for_test(project.output.dsp_root));
            issues = c2837x_block_validate_project(project, 'full');
            testCase.verifyTrue(any(strcmp({issues.code}, 'OUTPUT_ROOT_NOT_READABLE')));
            testCase.verifyTrue(any(strcmp({issues.code}, 'OUTPUT_ROOT_NONEMPTY')));
        end

        function testUnwritableOutputRootOnUnix(testCase)
            testCase.assumeFalse(ispc);
            project = valid_project(testCase.WorkFolder);
            mkdir(project.output.dsp_root);
            before = tree(testCase.WorkFolder);
            restrict_permissions(testCase, project.output.dsp_root, 'a-w');
            testCase.assumeFalse(path_is_writable_for_test(project.output.dsp_root));
            issues = c2837x_block_validate_project(project, 'full');
            testCase.verifyTrue(any(strcmp({issues.code}, 'OUTPUT_ROOT_NOT_WRITABLE')));
            testCase.verifyEqual(tree(testCase.WorkFolder), before);
        end

        function testOutputRootOccupiedByFile(testCase)
            project = valid_project(testCase.WorkFolder);
            fileID = fopen(project.output.dsp_root, 'w'); fclose(fileID);
            testCase.verifyTrue(has_code(project, 'OUTPUT_ROOT_IS_FILE', 'full'));
        end

        function testMissingOutputRootWithFileParent(testCase)
            project = valid_project(testCase.WorkFolder);
            parent = fullfile(testCase.WorkFolder, 'occupied');
            fileID = fopen(parent, 'w'); fclose(fileID);
            project.output.dsp_root = fullfile(parent, 'generated');
            issues = c2837x_block_validate_project(project, 'full');
            testCase.verifyTrue(any(strcmp({issues.code}, 'OUTPUT_PARENT_INVALID')));
            testCase.verifyTrue(any(strcmp({issues.code}, 'OUTPUT_ROOT_WILL_CREATE')));
        end

        function testAlgorithmModesAndReadableCFile(testCase)
            project = valid_project(testCase.WorkFolder);
            source = fullfile(testCase.WorkFolder, 'algorithm.c');
            fileID = fopen(source, 'w'); fprintf(fileID, 'void f(void) {}\n'); fclose(fileID);
            project.instances.algorithm.mode = 'external_reference';
            project.instances.algorithm.source_path = source;
            issues = c2837x_block_validate_project(project, 'full');
            testCase.verifyFalse(any(strcmp({issues.code}, 'ALGORITHM_SOURCE_EXTENSION_INVALID')));
            testCase.verifyTrue(any(strcmp({issues.code}, 'EXTERNAL_REFERENCE_NOT_COPIED')));
        end

        function testAlgorithmMissingDirectoryAndWrongExtension(testCase)
            project = valid_project(testCase.WorkFolder);
            project.instances.algorithm.mode = 'external_copy';
            project.instances.algorithm.source_path = fullfile(testCase.WorkFolder, 'missing.c');
            testCase.verifyTrue(has_code(project, 'ALGORITHM_SOURCE_MISSING', 'full'));
            project.instances.algorithm.source_path = testCase.WorkFolder;
            testCase.verifyTrue(has_code(project, 'ALGORITHM_SOURCE_IS_DIRECTORY', 'full'));
            header = fullfile(testCase.WorkFolder, 'algorithm.h');
            fileID = fopen(header, 'w'); fclose(fileID);
            project.instances.algorithm.source_path = header;
            testCase.verifyTrue(has_code(project, 'ALGORITHM_SOURCE_EXTENSION_INVALID', 'full'));
        end

        function testUppercaseCExtensionUsesFilesystemIdentity(testCase)
            testCase.assumeTrue(ispc);
            project = valid_project(testCase.WorkFolder);
            source = fullfile(testCase.WorkFolder, 'algorithm.C');
            fileID = fopen(source, 'w'); fclose(fileID);
            project.instances.algorithm.mode = 'external_copy';
            project.instances.algorithm.source_path = source;
            issues = c2837x_block_validate_project(project, 'full');
            testCase.verifyFalse(any(ismember({issues.code}, ...
                {'ALGORITHM_SOURCE_EXTENSION_INVALID', 'ALGORITHM_SOURCE_IDENTITY_UNKNOWN'})));
        end
    end
end

function project = valid_project(folder)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.1.10';
project.common.network.gateway = '0.0.0.0';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(folder, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(folder, 'sfun'));
instance = c2837x_block_create_default_instance();
instance.display_name = 'Motor';
instance.internal_name = 'motor';
instance.inputs = variable('command', 'int16', 1);
instance.outputs = variable('status', 'uint16', 1);
project.instances = instance;
end

function value = variable(name, type, dim)
value = struct('name', name, 'type', type, 'dim', dim);
end

function tf = has_code(project, code, mode)
if nargin < 3
    mode = 'instant';
end
tf = any(strcmp({c2837x_block_validate_project(project, mode).code}, code));
end

function value = tree(folder)
entries = dir(fullfile(folder, '**', '*'));
value = sort({entries.name});
end

function root = filesystem_root(path)
root = path;
while ~strcmp(fileparts(root), root)
    root = fileparts(root);
end
end

function restrict_permissions(testCase, path, mode)
testCase.addTeardown(@() system(sprintf('chmod u+rwx "%s"', path)));
[status, output] = system(sprintf('chmod %s "%s"', mode, path));
testCase.assertEqual(status, 0, output);
end

function tf = path_is_readable_for_test(path)
tf = java.nio.file.Files.isReadable(java.io.File(path).toPath());
end

function tf = path_is_writable_for_test(path)
tf = java.nio.file.Files.isWritable(java.io.File(path).toPath());
end
