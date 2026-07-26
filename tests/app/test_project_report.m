classdef test_project_report < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testSingleInstanceHash(testCase)
            project = report_project(1);
            [report, issues] = c2837x_block_build_project_report(project);
            [text, hash] = c2837x_block_build_interface_hash(project, 1);
            testCase.verifyEmpty(issues);
            testCase.verifyEqual(report.instances(1).interface_hash, hash);
            testCase.verifyEqual(report.instances(1).canonical_text, text);
        end

        function testTwoIndependentHashes(testCase)
            project = report_project(2);
            report = c2837x_block_build_project_report(project);
            testCase.verifyNotEqual(report.instances(1).interface_hash, ...
                report.instances(2).interface_hash);
        end

        function testDataAndPayloadOctets(testCase)
            report = c2837x_block_build_project_report(report_project(1));
            value = report.instances(1);
            testCase.verifyEqual([value.input_data_octets, ...
                value.output_data_octets], [6 8]);
            testCase.verifyEqual([value.input_payload_octets, ...
                value.output_payload_octets], [10 12]);
        end

        function testFrameWords(testCase)
            report = c2837x_block_build_project_report(report_project(1));
            testCase.verifyEqual([report.instances.rx_frame_words, ...
                report.instances.tx_frame_words], [7 8]);
        end

        function testProjectTotal(testCase)
            report = c2837x_block_build_project_report(report_project(2));
            testCase.verifyEqual(report.total_protocol_buffer_words, ...
                sum([report.instances.rx_frame_words] + ...
                [report.instances.tx_frame_words]));
        end

        function testCanonicalOctets(testCase)
            report = c2837x_block_build_project_report(report_project(1));
            testCase.verifyEqual(report.instances.canonical_utf8_octets, ...
                numel(unicode2native(report.instances.canonical_text, 'UTF-8')));
        end

        function testUnrelatedFieldsDoNotChangeHash(testCase)
            project = report_project(1);
            first = c2837x_block_build_project_report(project);
            project.common.abi = 'coffabi';
            project.common.network.ip = '10.0.0.2';
            project.instances(1).display_name = 'Renamed';
            project.instances(1).iodevice.settings.socket_number = uint16(7);
            project.instances(1).iodevice.settings.tcp_port = uint16(6000);
            project.instances(1).sample_time_sec = 0.5;
            project.output.dsp_root = 'changed';
            second = c2837x_block_build_project_report(project);
            testCase.verifyEqual(first.instances.interface_hash, ...
                second.instances.interface_hash);
        end

        function testInterfaceFieldsChangeHash(testCase)
            project = report_project(1);
            first = c2837x_block_build_project_report(project);
            project.instances(1).inputs(1).name = 'renamed_input';
            second = c2837x_block_build_project_report(project);
            testCase.verifyNotEqual(first.instances.interface_hash, ...
                second.instances.interface_hash);
        end

        function testOrderChangesHash(testCase)
            project = report_project(1);
            first = c2837x_block_build_project_report(project);
            project.instances(1).inputs = project.instances(1).inputs([2 1]);
            second = c2837x_block_build_project_report(project);
            testCase.verifyNotEqual(first.instances.interface_hash, ...
                second.instances.interface_hash);
        end

        function testMaxPayloadChangesHash(testCase)
            project = report_project(1);
            first = c2837x_block_build_project_report(project);
            project.instances(1).max_payload_size_bytes = uint32(2048);
            second = c2837x_block_build_project_report(project);
            testCase.verifyNotEqual(first.instances.interface_hash, ...
                second.instances.interface_hash);
        end

        function testProjectIsNotModified(testCase)
            project = report_project(2);
            original = project;
            c2837x_block_build_project_report(project);
            testCase.verifyEqual(project, original);
        end

        function testInvalidInstanceStableIssue(testCase)
            project = report_project(1);
            project.instances(1).inputs(1).type = 'bad';
            [~, issues] = c2837x_block_build_project_report(project);
            testCase.verifyEqual({issues.code}, {'APP_REPORT_BUILD_FAILED'});
            testCase.verifyFalse(contains(issues.message, 'bad'));
        end

        function testReportHasOnlyFixedFields(testCase)
            report = c2837x_block_build_project_report(report_project(1));
            testCase.verifyEqual(sort(fieldnames(report)), ...
                sort({'instances'; 'total_protocol_buffer_words'}));
            forbidden = {'w5300_ram', 'stack', 'padding', 'mex_size'};
            testCase.verifyFalse(any(ismember(forbidden, ...
                fieldnames(report.instances))));
        end
    end
end

function project = report_project(count)
project = c2837x_block_create_default_project();
instances = repmat(c2837x_block_create_default_instance(), 1, count);
for index = 1:count
    instances(index).display_name = sprintf('Instance %u', index);
    instances(index).internal_name = sprintf('instance_%u', index);
    instances(index).iodevice.settings.socket_number = uint16(index - 1);
    instances(index).iodevice.settings.tcp_port = uint16(4999 + index);
    instances(index).inputs = [struct('name', 'a', 'type', 'int16', 'dim', 1), ...
        struct('name', sprintf('b%u', index), 'type', 'single', 'dim', 1)];
    instances(index).outputs = struct('name', 'result', ...
        'type', 'double', 'dim', 1);
end
project.instances = instances;
end
