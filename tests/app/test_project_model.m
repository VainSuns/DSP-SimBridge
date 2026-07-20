classdef test_project_model < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testPublicConstructors(testCase)
            project = c2837x_block_create_default_project();
            instance = c2837x_block_create_default_instance();

            testCase.verifyTrue(isstruct(project) && isscalar(project));
            testCase.verifyTrue(isstruct(instance) && isscalar(instance));
        end

        function testDefaultProject(testCase)
            project = c2837x_block_create_default_project();

            testCase.verifyEqual(project.format_version, uint16(2));
            testCase.verifyEqual(project.common.dsp_model, 'TMS320F28377D');
            testCase.verifyEqual(project.common.protocol_version, uint16(1));
            testCase.verifyEqual(project.common.abi, 'eabi');
            testCase.verifyEqual(project.common.network.mac, zeros(1, 0, 'uint8'));
            testCase.verifyEqual(project.common.network.ip, '');
            testCase.verifyEqual(project.common.network.gateway, '');
            testCase.verifyEqual(project.common.network.subnet, '');
            testCase.verifyEqual(project.output.dsp_root, '');
            testCase.verifyEqual(project.output.sfun_root, '');
            testCase.verifyFalse(isfield(project, 'abi'));
            testCase.verifyFalse(isfield(project, 'core_api_version'));
            testCase.verifyFalse(isfield(project.common, 'dsp_root'));
            testCase.verifyFalse(isfield(project.common, 'sfun_root'));
        end

        function testTypedEmptyInstancesCanAppend(testCase)
            project = c2837x_block_create_default_project();
            instance = c2837x_block_create_default_instance();

            testCase.verifyEmpty(project.instances);
            testCase.verifyEqual(sort(fieldnames(project.instances)), ...
                sort(fieldnames(instance)));
            project.instances(end + 1) = instance;
            testCase.verifyEqual(project.instances, instance);
        end

        function testDefaultInstance(testCase)
            instance = c2837x_block_create_default_instance();

            testCase.verifyEqual(instance.display_name, '');
            testCase.verifyEqual(instance.internal_name, '');
            testCase.verifyEqual(instance.sample_time_sec, 1e-4, AbsTol=eps(1e-4));
            testCase.verifyEqual(instance.max_payload_size_bytes, uint32(1024));
            testCase.verifyEmpty(instance.inputs);
            testCase.verifyEqual(sort(fieldnames(instance.inputs)), ...
                sort({'name'; 'type'; 'dim'}));
            testCase.verifyEmpty(instance.outputs);
            testCase.verifyEqual(sort(fieldnames(instance.outputs)), ...
                sort({'name'; 'type'; 'dim'}));
            testCase.verifyEqual(instance.algorithm.mode, 'generated_example');
            testCase.verifyEqual(instance.algorithm.source_path, '');
            testCase.verifyEqual(instance.interface_hash, uint32(0));
            testCase.verifyFalse(isfield(instance, 'abi'));
            testCase.verifyFalse(isfield(instance, 'network'));
            testCase.verifyFalse(isfield(instance, 'output'));
            testCase.verifyFalse(isfield(instance, 'core_api_version'));
        end

        function testDefaultIoDeviceSettings(testCase)
            instance = c2837x_block_create_default_instance();

            testCase.verifyEqual(instance.iodevice.type, 'w5300_tcp');
            testCase.verifyEqual(instance.iodevice.settings.socket_number, uint16(0));
            testCase.verifyEqual(instance.iodevice.settings.tcp_port, uint16(5000));
            testCase.verifyFalse(isfield(instance, 'socket_number'));
            testCase.verifyFalse(isfield(instance, 'tcp_port'));
            testCase.verifyFalse(isfield(instance.iodevice, 'socket_number'));
            testCase.verifyFalse(isfield(instance.iodevice, 'tcp_port'));
            testCase.verifyFalse(isfield(instance.iodevice, 'network'));
        end
    end
end
