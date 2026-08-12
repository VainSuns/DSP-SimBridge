classdef test_transport_summary < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testW5300Summary(testCase)
            instance = c2837x_block_create_default_instance();
            instance.iodevice.settings.socket_number = uint16(0);
            instance.iodevice.settings.tcp_port = uint16(5000);

            actual = c2837x_block_build_transport_summary(instance);

            expected = struct('type_label', 'W5300 TCP', ...
                'resource', 'Socket 0', 'link', 'TCP 5000', ...
                'summary', 'Socket 0 / TCP 5000');
            testCase.verifyEqual(actual, expected);
        end

        function testConfiguredSciSummary(testCase)
            instance = c2837x_block_create_default_instance();
            instance.iodevice = c2837x_block_create_iodevice('sci');
            instance.iodevice.settings.module = 'SCI-A';

            actual = c2837x_block_build_transport_summary(instance);

            expected = struct('type_label', 'SCI', ...
                'resource', 'SCI-A', 'link', '57600 baud', ...
                'summary', 'SCI-A / 57600 baud');
            testCase.verifyEqual(actual, expected);
        end

        function testUnconfiguredSciSummary(testCase)
            instance = c2837x_block_create_default_instance();
            instance.iodevice = c2837x_block_create_iodevice('sci');

            actual = c2837x_block_build_transport_summary(instance);

            testCase.verifyEqual(actual.resource, 'Not Selected');
            testCase.verifyEqual(actual.summary, ...
                'Not Selected / 57600 baud');
        end
    end
end
