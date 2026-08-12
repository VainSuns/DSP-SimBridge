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

            testCase.verifyEqual(project.format_version, uint16(3));
            testCase.verifyEqual(project.common.dsp_model, 'TMS320F28377D');
            testCase.verifyEqual(project.common.package, 'PTP');
            testCase.verifyEqual(project.common.protocol_version, uint16(1));
            testCase.verifyEqual(project.common.abi, 'eabi');
            testCase.verifyEqual(project.common.network.mac, ...
                uint8([0 8 220 1 2 3]));
            testCase.verifyEqual(project.common.network.ip, '192.168.1.100');
            testCase.verifyEqual(project.common.network.gateway, '192.168.1.1');
            testCase.verifyEqual(project.common.network.subnet, '255.255.255.0');
            testCase.verifyEmpty(project.instances);
            testCase.verifyEqual(project.output.dsp_root, '');
            testCase.verifyEqual(project.output.sfun_root, '');
            testCase.verifyFalse(isfield(project, 'abi'));
            testCase.verifyFalse(isfield(project, 'core_api_version'));
            testCase.verifyFalse(isfield(project.common, 'dsp_root'));
            testCase.verifyFalse(isfield(project.common, 'sfun_root'));
            testCase.verifyEqual(sort(fieldnames(project.common.network)), ...
                sort({'mac'; 'ip'; 'gateway'; 'subnet'}));
        end

        function testNetworkValuesRoundTripWithoutBeingOverwritten(testCase)
            folder = tempname;
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            filePath = fullfile(folder, 'project.mat');
            project = c2837x_block_create_default_project();
            source = c2837x_block_project_session(project);
            source.saveProject(filePath);
            loaded = c2837x_block_project_session();
            loaded.loadProject(filePath);
            testCase.verifyEqual(loaded.Project.common.network, ...
                project.common.network);

            custom = struct('mac', uint8([2 4 6 8 10 12]), ...
                'ip', '10.20.30.40', 'gateway', '10.20.30.1', ...
                'subnet', '255.255.0.0');
            project.common.network = custom;
            source.updateProject(project);
            source.saveProject(filePath);
            loaded.loadProject(filePath);
            testCase.verifyEqual(loaded.Project.common.network, custom);
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
