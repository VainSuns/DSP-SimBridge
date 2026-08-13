classdef test_legacy_project_migration < matlab.unittest.TestCase
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
        function testMigratesLegacyConfigToOneV4Instance(testCase)
            config = hashable_legacy_config();
            path = write_legacy(testCase.WorkFolder, 'legacy.mat', config);
            session = c2837x_block_project_session();

            loaded = session.loadProject(path);
            project = session.Project;
            instance = project.instances;

            testCase.verifyTrue(loaded);
            testCase.verifyEqual(project.format_version, uint16(4));
            testCase.verifyEqual(project.common.package, 'PTP');
            testCase.verifyEqual(project.common.protocol_version, uint16(1));
            testCase.verifyEqual(project.common.network.mac, config.mac);
            testCase.verifyEqual(project.common.network.ip, config.dsp_ip);
            testCase.verifyEqual(project.common.network.gateway, config.gateway);
            testCase.verifyEqual(project.common.network.subnet, config.subnet);
            testCase.verifyNumElements(project.instances, 1);
            testCase.verifyEqual(instance.display_name, 'C2837xBlock');
            testCase.verifyEqual(instance.internal_name, 'c2837x_block');
            testCase.verifyEqual(instance.iodevice.type, 'w5300_tcp');
            testCase.verifyEqual(instance.iodevice.settings.socket_number, ...
                config.socket_num);
            testCase.verifyEqual(instance.iodevice.settings.tcp_port, config.tcp_port);
            testCase.verifyEqual(instance.sample_time_sec, config.sample_time_sec, ...
                AbsTol=eps(config.sample_time_sec));
            testCase.verifyEqual(instance.max_payload_size_bytes, ...
                config.max_payload_size_bytes);
            testCase.verifyEqual(instance.inputs, config.inputs);
            testCase.verifyEqual(instance.outputs, config.outputs);
            testCase.verifyEqual(instance.algorithm.mode, 'generated_example');
            testCase.verifyEqual(instance.algorithm.source_path, '');
            [~, expectedHash] = c2837x_block_build_interface_hash(project, 1);
            testCase.verifyEqual(instance.interface_hash, expectedHash);
            testCase.verifyEmpty(session.FilePath);
            testCase.verifyTrue(session.Dirty);
        end

        function testMigratesEabi(testCase)
            project = migrate_with_abi('eabi');
            testCase.verifyEqual(project.common.abi, 'eabi');
        end

        function testMigratesCoff(testCase)
            project = migrate_with_abi('coff');
            testCase.verifyEqual(project.common.abi, 'coffabi');
        end

        function testMigratesCoffabi(testCase)
            project = migrate_with_abi('coffabi');
            testCase.verifyEqual(project.common.abi, 'coffabi');
        end

        function testDefaultsMissingAbi(testCase)
            config = rmfield(legacy_config(), 'abi');
            project = validated_migration(config);
            testCase.verifyEqual(project.common.abi, 'eabi');
        end

        function testRejectsInvalidAbi(testCase)
            config = legacy_config();
            config.abi = 'EABI';
            testCase.verifyError(@() c2837x_block_migrate_legacy_config(config), ...
                'C2837xBlock:Project:InvalidLegacyConfig');
        end

        function testDefaultsMissingProtocolVersion(testCase)
            config = rmfield(legacy_config(), 'protocol_version');
            project = validated_migration(config);
            testCase.verifyEqual(project.common.protocol_version, uint16(1));
        end

        function testMigratesProtocolVersionOne(testCase)
            config = legacy_config();
            config.protocol_version = 1;
            project = validated_migration(config);
            testCase.verifyEqual(project.common.protocol_version, uint16(1));
        end

        function testRejectsHighProtocolVersion(testCase)
            config = legacy_config();
            config.protocol_version = uint16(2);
            testCase.verifyError(@() c2837x_block_migrate_legacy_config(config), ...
                'C2837xBlock:Project:UnsupportedVersion');
        end

        function testRejectsZeroProtocolVersion(testCase)
            config = legacy_config();
            config.protocol_version = uint16(0);
            testCase.verifyError(@() c2837x_block_migrate_legacy_config(config), ...
                'C2837xBlock:Project:InvalidVersion');
        end

        function testRejectsInvalidProtocolVersion(testCase)
            config = legacy_config();
            config.protocol_version = '1';
            testCase.verifyError(@() c2837x_block_migrate_legacy_config(config), ...
                'C2837xBlock:Project:InvalidVersion');
        end

        function testIgnoresArbitraryDoubleModeAndLegacyFields(testCase)
            config = legacy_config();
            config.double_mode = struct('unexpected', true);
            config.socket0_tx_kb = 8;
            config.socket0_rx_kb = 8;
            config.dsp_output_path = 'legacy-dsp';
            config.pc_output_path = 'legacy-pc';
            config.interface_hash = uint32(42);
            [config.inputs.legacy_hash] = deal(uint32(42));

            project = validated_migration(config);

            testCase.verifyFalse(isfield(project, 'config'));
            testCase.verifyFalse(isfield(project, 'double_mode'));
            testCase.verifyFalse(isfield(project.common, 'double_mode'));
            testCase.verifyFalse(isfield(project.instances, 'double_mode'));
            testCase.verifyEqual(project.output.dsp_root, '');
            testCase.verifyEqual(project.output.sfun_root, '');
            testCase.verifyEqual(project.instances.interface_hash, uint32(0));
            testCase.verifyFalse(isfield(project.instances.inputs, 'legacy_hash'));
        end

        function testLegacyFileIsUnmodifiedAndSaveAsStoresOnlyProject(testCase)
            legacyPath = write_legacy(testCase.WorkFolder, 'legacy.mat', ...
                hashable_legacy_config());
            savedPath = fullfile(testCase.WorkFolder, 'saved-v3.mat');
            before = file_bytes(legacyPath);
            session = c2837x_block_project_session();

            session.loadProject(legacyPath);
            session.saveProject(savedPath);
            after = file_bytes(legacyPath);
            variables = whos('-file', savedPath);

            testCase.verifyEqual(after, before);
            testCase.verifyEqual({variables.name}, {'project'});
            testCase.verifyEqual(session.FilePath, savedPath);
            testCase.verifyFalse(session.Dirty);
        end

        function testMissingCriticalFieldPreservesSession(testCase)
            config = rmfield(legacy_config(), 'tcp_port');
            path = write_legacy(testCase.WorkFolder, 'missing-field.mat', config);
            session = saved_dirty_session(testCase.WorkFolder);
            before = snapshot(session);

            testCase.verifyError(@() session.loadProject(path, 'Don''t Save'), ...
                'C2837xBlock:Project:InvalidLegacyConfig');
            verify_snapshot(testCase, session, before);
        end

        function testInvalidAbiPreservesSession(testCase)
            config = legacy_config();
            config.abi = 'other';
            path = write_legacy(testCase.WorkFolder, 'invalid-abi.mat', config);
            session = saved_dirty_session(testCase.WorkFolder);
            before = snapshot(session);

            testCase.verifyError(@() session.loadProject(path, 'Don''t Save'), ...
                'C2837xBlock:Project:InvalidLegacyConfig');
            verify_snapshot(testCase, session, before);
        end

        function testInvalidProtocolPreservesSession(testCase)
            config = legacy_config();
            config.protocol_version = 0;
            path = write_legacy(testCase.WorkFolder, 'invalid-protocol.mat', config);
            session = saved_dirty_session(testCase.WorkFolder);
            before = snapshot(session);

            testCase.verifyError(@() session.loadProject(path, 'Don''t Save'), ...
                'C2837xBlock:Project:InvalidVersion');
            verify_snapshot(testCase, session, before);
        end

        function testProjectTakesPrecedenceOverLegacyConfig(testCase)
            project = c2837x_block_create_default_project();
            project.common = rmfield(project.common, 'network');
            config = legacy_config();
            path = fullfile(testCase.WorkFolder, 'both.mat');
            save(path, 'project', 'config');
            session = saved_dirty_session(testCase.WorkFolder);
            before = snapshot(session);

            testCase.verifyError(@() session.loadProject(path, 'Don''t Save'), ...
                'C2837xBlock:Project:InvalidStructure');
            verify_snapshot(testCase, session, before);
        end

        function testRejectsFileWithoutProjectOrConfig(testCase)
            other = 1;
            path = fullfile(testCase.WorkFolder, 'other.mat');
            save(path, 'other');

            testCase.verifyError(@() load_new_session(path), ...
                'C2837xBlock:Project:MissingProject');
        end
    end
end

function config = legacy_config()
config = struct( ...
    'protocol_version', uint16(1), ...
    'abi', 'eabi', ...
    'mac', uint8([0 17 34 51 68 85]), ...
    'dsp_ip', '192.168.1.100', ...
    'gateway', '192.168.1.1', ...
    'subnet', '255.255.255.0', ...
    'socket_num', uint16(3), ...
    'tcp_port', uint16(5500), ...
    'sample_time_sec', 2e-4, ...
    'max_payload_size_bytes', uint32(2048), ...
    'inputs', struct('name', {'second'; 'first'}, ...
        'type', {'uint16'; 'single'}, 'dim', {[2 3]; 4}), ...
    'outputs', struct('name', {'z'; 'a'}, ...
        'type', {'int32'; 'uint8'}, 'dim', {1; [3 2]}));
end

function config = hashable_legacy_config()
config = legacy_config();
[config.inputs.dim] = deal(6, 4);
[config.outputs.type] = deal('int32', 'uint16');
[config.outputs.dim] = deal(1, 6);
end

function path = write_legacy(folder, name, config)
path = fullfile(folder, name);
save(path, 'config');
end

function project = migrate_with_abi(abi)
config = legacy_config();
config.abi = abi;
project = validated_migration(config);
end

function project = validated_migration(config)
project = c2837x_block_migrate_legacy_config(config);
c2837x_block_project_session(project);
end

function bytes = file_bytes(path)
file = fopen(path, 'rb');
cleanup = onCleanup(@() fclose(file));
bytes = fread(file, Inf, '*uint8');
end

function session = saved_dirty_session(folder)
session = c2837x_block_project_session();
session.saveProject(fullfile(folder, 'current.mat'));
project = session.Project;
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(folder, 'dirty'));
session.updateProject(project);
end

function value = snapshot(session)
value = struct('project', session.Project, 'filePath', session.FilePath, ...
    'dirty', session.Dirty);
end

function verify_snapshot(testCase, session, expected)
testCase.verifyEqual(session.Project, expected.project);
testCase.verifyEqual(session.FilePath, expected.filePath);
testCase.verifyEqual(session.Dirty, expected.dirty);
end

function load_new_session(path)
session = c2837x_block_project_session();
session.loadProject(path);
end
