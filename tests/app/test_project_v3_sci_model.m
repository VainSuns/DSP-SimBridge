classdef test_project_v3_sci_model < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
        end
    end

    methods (TestMethodSetup)
        function createWorkFolder(testCase)
            testCase.WorkFolder = tempname;
            mkdir(testCase.WorkFolder);
            testCase.addTeardown(@() rmdir(testCase.WorkFolder, 's'));
        end
    end

    methods (Test)
        function testDefaultV3RoundTripStoresOnlyProject(testCase)
            project = c2837x_block_create_default_project();
            path = fullfile(testCase.WorkFolder, 'project-v3.mat');
            source = c2837x_block_project_session(project);

            source.saveProject(path);
            target = c2837x_block_project_session();
            target.loadProject(path);
            variables = whos('-file', path);

            testCase.verifyEqual(project.format_version, uint16(3));
            testCase.verifyEqual(project.common.package, 'PTP');
            testCase.verifyEqual(c2837x_block_create_default_instance().iodevice.type, ...
                'w5300_tcp');
            testCase.verifyEqual(target.Project, project);
            testCase.verifyEqual({variables.name}, {'project'});
        end

        function testSciDefaultsAreCanonicalProjectState(testCase)
            iodevice = c2837x_block_create_iodevice('sci');
            expectedFields = {'module'; 'baud'; 'pin_group'; 'rx_pin_type'; ...
                'rx_qualification'; 'tx_pin_type'; 'ctrl_gpio'; ...
                'ctrl_pin_type'; 'ctrl_tx_active_level'};

            testCase.verifyEqual(iodevice.type, 'sci');
            testCase.verifyEqual(sort(fieldnames(iodevice.settings)), ...
                sort(expectedFields));
            testCase.verifyEmpty(iodevice.settings.module);
            testCase.verifyEqual(iodevice.settings.baud, uint32(57600));
            testCase.verifyEmpty(iodevice.settings.pin_group);
            testCase.verifyEqual(iodevice.settings.rx_pin_type, 'Pull-up');
            testCase.verifyEqual(iodevice.settings.rx_qualification, 'Async');
            testCase.verifyEqual(iodevice.settings.tx_pin_type, 'Pull-up');
            testCase.verifyEqual(iodevice.settings.ctrl_gpio, 'None');
            testCase.verifyEqual(iodevice.settings.ctrl_pin_type, 'Standard');
            testCase.verifyEqual(iodevice.settings.ctrl_tx_active_level, 'High');
            testCase.verifyFalse(isfield(iodevice.settings, 'socket_number'));
            testCase.verifyFalse(isfield(iodevice.settings, 'tcp_port'));
            testCase.verifyFalse(isfield(iodevice.settings, 'com'));
            testCase.verifyFalse(isfield(iodevice.settings, 'com_port'));
        end

        function testSwitchReplacesTransportSettingsAndPreservesCommonFields(testCase)
            source = valid_instance('source', 2, 5200);
            source.sample_time_sec = 3e-4;
            source.max_payload_size_bytes = uint32(2048);
            project = c2837x_block_create_default_project();
            project.instances = source;
            session = c2837x_block_project_session(project);

            session.switchIoDevice(1, 'sci');
            sci = session.Project.instances;
            session.switchIoDevice(1, 'w5300_tcp');
            w5300 = session.Project.instances;

            testCase.verifyEqual(sci.iodevice, c2837x_block_create_iodevice('sci'));
            testCase.verifyEqual(sci.display_name, source.display_name);
            testCase.verifyEqual(sci.internal_name, source.internal_name);
            testCase.verifyEqual(sci.sample_time_sec, source.sample_time_sec, ...
                AbsTol=eps(source.sample_time_sec));
            testCase.verifyEqual(sci.max_payload_size_bytes, ...
                source.max_payload_size_bytes);
            testCase.verifyEqual(sci.inputs, source.inputs);
            testCase.verifyEqual(sci.outputs, source.outputs);
            testCase.verifyEqual(sci.algorithm, source.algorithm);
            testCase.verifyFalse(isfield(sci.iodevice.settings, 'socket_number'));
            testCase.verifyEqual(w5300.iodevice, ...
                c2837x_block_create_iodevice('w5300_tcp'));
            testCase.verifyFalse(isfield(w5300.iodevice.settings, 'module'));
            testCase.verifyTrue(session.Dirty);
        end

        function testTypeChangeCannotRetainOldTransportFields(testCase)
            project = c2837x_block_create_default_project();
            project.instances = valid_instance('source', 2, 5200);
            session = c2837x_block_project_session(project);
            changes = struct('iodevice', struct('type', 'sci', ...
                'settings', struct('socket_number', uint16(2))));

            testCase.verifyError(@() session.updateInstance(1, changes), ...
                'C2837xBlock:Instance:InvalidChanges');
        end

        function testExplicitV2ProjectMigratesDirtyWithoutOverwrite(testCase)
            project = v2_fixture(testCase.WorkFolder);
            sourcePath = fullfile(testCase.WorkFolder, 'source-v2.mat');
            save(sourcePath, 'project');
            before = file_bytes(sourcePath);
            session = c2837x_block_project_session();

            session.loadProject(sourcePath);
            migrated = session.Project;
            after = file_bytes(sourcePath);

            testCase.verifyEqual(migrated.format_version, uint16(3));
            testCase.verifyEqual(migrated.common.dsp_model, 'TMS320F28377D');
            testCase.verifyEqual(migrated.common.package, 'PTP');
            testCase.verifyEqual(migrated.common.protocol_version, ...
                project.common.protocol_version);
            testCase.verifyEqual(migrated.common.abi, project.common.abi);
            testCase.verifyEqual(migrated.common.network, project.common.network);
            testCase.verifyEqual(migrated.instances.iodevice.type, 'w5300_tcp');
            testCase.verifyEqual(migrated.instances.iodevice.settings, ...
                project.instances.iodevice.settings);
            testCase.verifyEqual(migrated.instances.sample_time_sec, ...
                project.instances.sample_time_sec, ...
                AbsTol=eps(project.instances.sample_time_sec));
            testCase.verifyEqual(migrated.instances.max_payload_size_bytes, ...
                project.instances.max_payload_size_bytes);
            testCase.verifyEqual(migrated.instances.inputs, project.instances.inputs);
            testCase.verifyEqual(migrated.instances.outputs, project.instances.outputs);
            testCase.verifyEqual(migrated.instances.algorithm, ...
                project.instances.algorithm);
            testCase.verifyEqual(migrated.output, project.output);
            testCase.verifyEmpty(session.FilePath);
            testCase.verifyTrue(session.Dirty);
            testCase.verifyEqual(after, before);
        end

        function testExplicitSaveAfterV2MigrationWritesV3(testCase)
            project = v2_fixture(testCase.WorkFolder);
            sourcePath = fullfile(testCase.WorkFolder, 'source-v2.mat');
            targetPath = fullfile(testCase.WorkFolder, 'saved-v3.mat');
            save(sourcePath, 'project');
            session = c2837x_block_project_session();

            session.loadProject(sourcePath);
            session.saveProject(targetPath);
            data = load(targetPath, 'project');
            variables = whos('-file', targetPath);

            testCase.verifyEqual(data.project.format_version, uint16(3));
            testCase.verifyEqual({variables.name}, {'project'});
            testCase.verifyEqual(session.FilePath, targetPath);
            testCase.verifyFalse(session.Dirty);
        end

        function testV2MissingDspModelIsRejectedAtomically(testCase)
            project = v2_fixture(testCase.WorkFolder);
            project.common = rmfield(project.common, 'dsp_model');
            path = write_project(testCase.WorkFolder, ...
                'v2-missing-dsp-model.mat', project);
            session = saved_dirty_session(testCase.WorkFolder);
            before = snapshot(session);

            testCase.verifyError(@() session.loadProject(path, 'Don''t Save'), ...
                'C2837xBlock:Project:InvalidStructure');
            verify_snapshot(testCase, session, before);
        end

        function testV2MissingIoDeviceTypeIsRejectedAtomically(testCase)
            project = v2_fixture(testCase.WorkFolder);
            project.instances.iodevice = rmfield( ...
                project.instances.iodevice, 'type');
            path = write_project(testCase.WorkFolder, ...
                'v2-missing-iodevice-type.mat', project);
            session = saved_dirty_session(testCase.WorkFolder);
            before = snapshot(session);

            testCase.verifyError(@() session.loadProject(path, 'Don''t Save'), ...
                'C2837xBlock:Project:InvalidStructure');
            verify_snapshot(testCase, session, before);
        end

        function testV2MissingAlgorithmModeIsRejectedAtomically(testCase)
            project = v2_fixture(testCase.WorkFolder);
            project.instances.algorithm = rmfield( ...
                project.instances.algorithm, 'mode');
            path = write_project(testCase.WorkFolder, ...
                'v2-missing-algorithm-mode.mat', project);
            session = saved_dirty_session(testCase.WorkFolder);
            before = snapshot(session);

            testCase.verifyError(@() session.loadProject(path, 'Don''t Save'), ...
                'C2837xBlock:Project:InvalidStructure');
            verify_snapshot(testCase, session, before);
        end

        function testSciCopyClearsExclusiveResourcesWhenCtrlNone(testCase)
            source = sci_instance('source', 'None');
            source.iodevice.settings.module = 'SCI-B';
            source.iodevice.settings.pin_group = 'B-1';
            project = c2837x_block_create_default_project();
            project.instances = source;
            session = c2837x_block_project_session(project);

            session.copyInstance(1, 'Copy', 'copy');
            copied = session.Project.instances(2);

            verify_sci_copy(testCase, copied, source);
            testCase.verifyEqual(copied.iodevice.settings.ctrl_gpio, 'None');
        end

        function testSciCopyClearsExclusiveResourcesWhenCtrlGpio(testCase)
            source = sci_instance('source', 'GPIO42');
            source.iodevice.settings.module = 'SCI-C';
            source.iodevice.settings.pin_group = 'C-2';
            project = c2837x_block_create_default_project();
            project.instances = source;
            session = c2837x_block_project_session(project);

            session.copyInstance(1, 'Copy', 'copy');
            copied = session.Project.instances(2);

            verify_sci_copy(testCase, copied, source);
            testCase.verifyEqual(copied.iodevice.settings.ctrl_gpio, 'None');
        end

        function testNetworkValidationIsConditional(testCase)
            sciProject = project_with_invalid_network();
            sciProject.instances = sci_instance('sci_only', 'None');
            w5300Project = project_with_invalid_network();
            w5300Project.instances = valid_instance('w5300_only', 0, 5000);
            mixedProject = project_with_invalid_network();
            mixedProject.instances = [valid_instance('w5300', 0, 5000), ...
                sci_instance('sci', 'None')];
            networkCodes = {'MAC_ALL_ZERO', 'IP_ALL_ZERO', ...
                'SUBNET_NONCONTIGUOUS'};

            sciIssues = c2837x_block_validate_project(sciProject, 'instant');
            w5300Issues = c2837x_block_validate_project(w5300Project, 'instant');
            mixedIssues = c2837x_block_validate_project(mixedProject, 'instant');

            testCase.verifyFalse(any(ismember({sciIssues.code}, networkCodes)));
            testCase.verifyTrue(any(ismember({w5300Issues.code}, networkCodes)));
            testCase.verifyTrue(any(ismember({mixedIssues.code}, networkCodes)));
            testCase.verifyEqual(sciProject.common.network, ...
                project_with_invalid_network().common.network);
        end

        function testTransportAndSciHardwareDoNotChangeInterfaceHash(testCase)
            project = c2837x_block_create_default_project();
            project.instances = valid_instance('wire', 0, 5000);
            [~, w5300Hash] = c2837x_block_build_interface_hash(project, 1);
            project.instances.iodevice = c2837x_block_create_iodevice('sci');
            [~, sciDefaultHash] = c2837x_block_build_interface_hash(project, 1);
            settings = project.instances.iodevice.settings;
            settings.module = 'SCI-D';
            settings.baud = uint32(115200);
            settings.pin_group = 'D-1';
            settings.rx_pin_type = 'Standard';
            settings.rx_qualification = 'Sync';
            settings.tx_pin_type = 'Standard';
            settings.ctrl_gpio = 'GPIO12';
            settings.ctrl_pin_type = 'Pull-up';
            settings.ctrl_tx_active_level = 'Low';
            project.instances.iodevice.settings = settings;
            [~, sciChangedHash] = c2837x_block_build_interface_hash(project, 1);
            project.common.package = 'NON_WIRE_TEST_VALUE';
            [~, packageChangedHash] = c2837x_block_build_interface_hash(project, 1);

            testCase.verifyEqual(sciDefaultHash, w5300Hash);
            testCase.verifyEqual(sciChangedHash, w5300Hash);
            testCase.verifyEqual(packageChangedHash, w5300Hash);
            testCase.verifyFalse(isfield(project, 'com'));
            testCase.verifyFalse(isfield(project.common, 'com'));
            testCase.verifyFalse(isfield(settings, 'com'));
            testCase.verifyFalse(isfield(settings, 'com_port'));
        end
    end
end

function instance = valid_instance(name, socket, port)
instance = c2837x_block_create_default_instance();
instance.display_name = name;
instance.internal_name = name;
instance.iodevice.settings.socket_number = uint16(socket);
instance.iodevice.settings.tcp_port = uint16(port);
instance.inputs = variable('command');
instance.outputs = variable('status');
end

function instance = sci_instance(name, ctrlGpio)
instance = valid_instance(name, 0, 5000);
instance.iodevice = c2837x_block_create_iodevice('sci');
instance.iodevice.settings.baud = uint32(115200);
instance.iodevice.settings.rx_pin_type = 'Standard';
instance.iodevice.settings.rx_qualification = 'Sync';
instance.iodevice.settings.tx_pin_type = 'Standard';
instance.iodevice.settings.ctrl_gpio = ctrlGpio;
instance.iodevice.settings.ctrl_pin_type = 'Pull-up';
instance.iodevice.settings.ctrl_tx_active_level = 'Low';
end

function value = variable(name)
value = struct('name', name, 'type', 'single', 'dim', 1);
end

function project = project_with_invalid_network()
project = c2837x_block_create_default_project();
project.common.network.mac = uint8(zeros(1, 6));
project.common.network.ip = '0.0.0.0';
project.common.network.subnet = '255.0.255.0';
end

function project = v2_fixture(folder)
instance = struct( ...
    'display_name', 'Historical', ...
    'internal_name', 'historical', ...
    'iodevice', struct('type', 'w5300_tcp', 'settings', ...
        struct('socket_number', uint16(4), 'tcp_port', uint16(5400))), ...
    'sample_time_sec', 2e-4, ...
    'max_payload_size_bytes', uint32(2048), ...
    'inputs', variable('command'), ...
    'outputs', variable('status'), ...
    'algorithm', struct('mode', 'external_reference', 'source_path', ...
        c2837x_block_normalize_absolute_path(fullfile(folder, 'algorithm.c'))), ...
    'interface_hash', uint32(123));
project = struct( ...
    'format_version', uint16(2), ...
    'common', struct( ...
        'dsp_model', 'historical-target', ...
        'protocol_version', uint16(1), ...
        'abi', 'coffabi', ...
        'network', struct('mac', uint8([2 1 2 3 4 5]), ...
            'ip', '10.0.0.2', 'gateway', '10.0.0.1', ...
            'subnet', '255.255.255.0')), ...
    'instances', instance, ...
    'output', struct( ...
        'dsp_root', c2837x_block_normalize_absolute_path( ...
            fullfile(folder, 'dsp')), ...
        'sfun_root', c2837x_block_normalize_absolute_path( ...
            fullfile(folder, 'sfun'))));
end

function verify_sci_copy(testCase, copied, source)
testCase.verifyEmpty(copied.iodevice.settings.module);
testCase.verifyEmpty(copied.iodevice.settings.pin_group);
testCase.verifyEqual(copied.iodevice.settings.baud, ...
    source.iodevice.settings.baud);
testCase.verifyEqual(copied.iodevice.settings.rx_pin_type, ...
    source.iodevice.settings.rx_pin_type);
testCase.verifyEqual(copied.iodevice.settings.rx_qualification, ...
    source.iodevice.settings.rx_qualification);
testCase.verifyEqual(copied.iodevice.settings.tx_pin_type, ...
    source.iodevice.settings.tx_pin_type);
testCase.verifyEqual(copied.iodevice.settings.ctrl_pin_type, ...
    source.iodevice.settings.ctrl_pin_type);
testCase.verifyEqual(copied.iodevice.settings.ctrl_tx_active_level, ...
    source.iodevice.settings.ctrl_tx_active_level);
testCase.verifyEqual(copied.sample_time_sec, source.sample_time_sec, ...
    AbsTol=eps(source.sample_time_sec));
testCase.verifyEqual(copied.max_payload_size_bytes, ...
    source.max_payload_size_bytes);
testCase.verifyEqual(copied.inputs, source.inputs);
testCase.verifyEqual(copied.outputs, source.outputs);
testCase.verifyEqual(copied.algorithm.mode, source.algorithm.mode);
testCase.verifyEqual(copied.algorithm.source_path, source.algorithm.source_path);
testCase.verifyEqual(copied.interface_hash, uint32(0));
end

function bytes = file_bytes(path)
file = fopen(path, 'rb');
cleanup = onCleanup(@() fclose(file));
bytes = fread(file, Inf, '*uint8');
end

function path = write_project(folder, name, project)
path = fullfile(folder, name);
save(path, 'project');
end

function session = saved_dirty_session(folder)
session = c2837x_block_project_session();
session.saveProject(fullfile(folder, 'current-v3.mat'));
project = session.Project;
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(folder, 'dirty-dsp'));
session.updateProject(project);
end

function value = snapshot(session)
value = struct('project', session.Project, 'file_path', session.FilePath, ...
    'dirty', session.Dirty, 'legacy_file_risks', session.LegacyFileRisks);
end

function verify_snapshot(testCase, session, expected)
testCase.verifyEqual(session.Project, expected.project);
testCase.verifyEqual(session.FilePath, expected.file_path);
testCase.verifyEqual(session.Dirty, expected.dirty);
testCase.verifyEqual(session.LegacyFileRisks, expected.legacy_file_risks);
end
