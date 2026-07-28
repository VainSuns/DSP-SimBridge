classdef test_iodevice_definitions < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppPath(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testResolverAndContract(testCase)
            [definition, found] = c2837x_block_get_iodevice_definition('w5300_tcp');
            [stringDefinition, stringFound] = ...
                c2837x_block_get_iodevice_definition("w5300_tcp");

            testCase.verifyTrue(found);
            testCase.verifyTrue(stringFound);
            testCase.verifyEqual(stringDefinition, definition);
            testCase.verifyEqual(definition.type, 'w5300_tcp');
            testCase.verifyEqual(definition.max_instance_count, 8);
            testCase.verifyTrue(all(isfield(definition, {'validate_settings', ...
                'collect_resource_claims', 'render_project_support'})));
            resolver = fileread(which('c2837x_block_get_iodevice_definition'));
            testCase.verifyEmpty(strfind(resolver, 'w5300_tcp'));
        end

        function testUnknownAndUnsafeNamesAreNotExecuted(testCase)
            names = {'not_registered', '../system', 'system('};
            for index = 1:numel(names)
                [definition, found] = c2837x_block_get_iodevice_definition(names{index});
                testCase.verifyFalse(found);
                testCase.verifyEqual(definition, struct());
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
    end
end
