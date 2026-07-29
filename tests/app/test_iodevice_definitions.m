classdef test_iodevice_definitions < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
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
        function testResolverAndContract(testCase)
            [definition, found, sourcePath] = ...
                c2837x_block_get_iodevice_definition('w5300_tcp');
            [stringDefinition, stringFound, stringSourcePath] = ...
                c2837x_block_get_iodevice_definition("w5300_tcp");

            testCase.verifyTrue(found);
            testCase.verifyTrue(stringFound);
            testCase.verifyEqual(stringDefinition, definition);
            testCase.verifyEqual(stringSourcePath, sourcePath);
            testCase.verifyTrue(isfile(sourcePath));
            testCase.verifyEqual(sourcePath, ...
                c2837x_block_normalize_absolute_path(sourcePath));
            testCase.verifyEqual(definition.type, 'w5300_tcp');
            testCase.verifyEqual(definition.max_instance_count, 8);
            testCase.verifyTrue(all(isfield(definition, {'validate_settings', ...
                'collect_resource_claims', 'render_project_support', ...
                'render_instance_config_support', ...
                'render_instance_io_support'})));
            resolver = fileread(which('c2837x_block_get_iodevice_definition'));
            testCase.verifyEmpty(strfind(resolver, 'w5300_tcp'));
        end

        function testUnknownAndUnsafeNamesAreNotExecuted(testCase)
            names = {'not_registered', '../system', 'system('};
            for index = 1:numel(names)
                [definition, found, sourcePath] = ...
                    c2837x_block_get_iodevice_definition(names{index});
                testCase.verifyFalse(found);
                testCase.verifyEqual(definition, struct());
                testCase.verifyEmpty(sourcePath);
            end
        end

        function testSettingsAndNormalizedClaims(testCase)
            definition = c2837x_block_get_iodevice_definition('w5300_tcp');
            valid = struct('socket_number', uint16(1), 'tcp_port', uint16(5000));
            testCase.verifyEmpty(definition.validate_settings(valid, 1));
            invalid = struct('socket_number', 8, 'tcp_port', 0);
            testCase.verifyEqual({definition.validate_settings(invalid, 2).code}, ...
                {'SOCKET_INVALID', 'TCP_PORT_INVALID'});

            first = definition.collect_resource_claims(valid, 1);
            valid.socket_number = double(1);
            valid.tcp_port = double(5000);
            second = definition.collect_resource_claims(valid, 2);
            testCase.verifyEqual({second.key}, {first.key});
            testCase.verifyEqual({first.kind}, {'socket', 'tcp_listen_port'});
            testCase.verifyTrue(all([first.exclusive]));
        end

        function testMissingW5300FieldsAreIndependent(testCase)
            definition = c2837x_block_get_iodevice_definition('w5300_tcp');

            socketMissing = struct('tcp_port', 5000);
            portMissing = struct('socket_number', 1);
            bothMissing = struct();

            testCase.verifyEqual({definition.validate_settings(socketMissing, 1).code}, ...
                {'SOCKET_INVALID'});
            testCase.verifyEqual({definition.validate_settings(portMissing, 1).code}, ...
                {'TCP_PORT_INVALID'});
            testCase.verifyEqual({definition.validate_settings(bothMissing, 1).code}, ...
                {'SOCKET_INVALID', 'TCP_PORT_INVALID'});
            testCase.verifyEqual({definition.collect_resource_claims(socketMissing, 1).kind}, ...
                {'tcp_listen_port'});
            testCase.verifyEqual({definition.collect_resource_claims(portMissing, 1).kind}, ...
                {'socket'});
            testCase.verifyEmpty(definition.collect_resource_claims(bothMissing, 1));
        end

        function testRejectsEveryInvalidInstanceLimit(testCase)
            addpath(testCase.WorkFolder, '-begin');
            testCase.addTeardown(@() rmpath(testCase.WorkFolder));
            expressions = {'-Inf', 'NaN', '0', '-1', '1.5', ...
                '1+2i', '[1 2]', '''many'''};
            for index = 1:numel(expressions)
                type = sprintf('invalid_limit_%u', index);
                write_definition(testCase.WorkFolder, type, expressions{index});
                rehash;
                testCase.verifyError( ...
                    @() c2837x_block_get_iodevice_definition(type), ...
                    'C2837xBlock:IoDevice:InvalidDefinition');
            end
        end

        function testProjectSupportUsesNetwork(testCase)
            project = c2837x_block_create_default_project();
            project.common.network.mac = uint8([0 8 220 1 2 3]);
            project.common.network.ip = '192.168.1.100';
            project.common.network.gateway = '192.168.1.1';
            project.common.network.subnet = '255.255.255.0';
            definition = c2837x_block_get_iodevice_definition('w5300_tcp');

            support = definition.render_project_support(project);

            testCase.verifyEqual(support.includes, {'c2837x_w5300_hal.h'});
            testCase.verifyNotEmpty(strfind(support.source, '0xC0A80164UL'));
            testCase.verifyNotEmpty(strfind(support.source, '0xFFFFFF00UL'));
        end

        function testW5300InstanceIoSupport(testCase)
            project = c2837x_block_create_default_project();
            instance = c2837x_block_create_default_instance();
            instance.internal_name = 'axis_x';
            project.instances = instance;
            definition = c2837x_block_get_iodevice_definition('w5300_tcp');

            support = definition.render_instance_io_support(project, 1);
            repeated = definition.render_instance_io_support(project, 1);

            testCase.verifyEqual(repeated, support);
            testCase.verifyEqual(support.source_includes, ...
                {'c2837x_block_platform.h', 'c2837x_w5300_channel.h'});
            testCase.verifyNotEmpty(strfind(support.source_definitions, ...
                'C2837X_W5300_CHANNEL_INITIALIZER'));
            testCase.verifyNotEmpty(strfind(support.source_definitions, ...
                'AXIS_X_W5300_SOCKET_NUMBER'));
            testCase.verifyEqual(numel(strfind( ...
                support.source_definitions, '8192u')), 2);
        end
    end
end

function write_definition(folder, type, maxExpression)
path = fullfile(folder, ['c2837x_block_iodevice_' type '_definition.m']);
text = sprintf([ ...
    'function definition = c2837x_block_iodevice_%s_definition()\n' ...
    'definition = struct(''type'', ''%s'', ''max_instance_count'', %s, ...\n' ...
    '    ''validate_settings'', @(varargin) [], ...\n' ...
    '    ''collect_resource_claims'', @(varargin) [], ...\n' ...
    '    ''render_project_support'', @(varargin) [], ...\n' ...
    '    ''render_instance_config_support'', @(varargin) [], ...\n' ...
    '    ''render_instance_io_support'', @(varargin) []);\n' ...
    'end\n'], type, type, maxExpression);
fileID = fopen(path, 'w'); assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fprintf(fileID, '%s', text);
clear cleanup
end
