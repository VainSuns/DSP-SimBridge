classdef test_dsp_core_candidates < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
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
        function testBuildsOnlyNormalizedCoreCandidates(testCase)
            project = valid_project(testCase.WorkFolder, 'dsp');

            [candidates, dependencies, issues] = ...
                c2837x_block_build_dsp_candidates(project);

            testCase.verifyEmpty(issues);
            verify_candidates(testCase, candidates, project.output.dsp_root);
            verify_dependencies(testCase, dependencies);
            testCase.verifyFalse(isfolder(project.output.dsp_root));
        end

        function testRootChangesOnlyCandidateTargets(testCase)
            firstProject = valid_project(testCase.WorkFolder, 'first_dsp');
            secondProject = firstProject;
            secondProject.output.dsp_root = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'second_dsp'));
            first = c2837x_block_build_dsp_candidates(firstProject);

            second = c2837x_block_build_dsp_candidates(secondProject);

            testCase.verifyNotEqual({second.target_path}, {first.target_path});
            testCase.verifyEqual({second.content_bytes}, {first.content_bytes});
            testCase.verifyFalse(isfolder(firstProject.output.dsp_root));
            testCase.verifyFalse(isfolder(secondProject.output.dsp_root));
        end

        function testConsecutiveBuildsAreByteIdentical(testCase)
            project = valid_project(testCase.WorkFolder, 'dsp');

            [firstCandidates, firstDependencies] = ...
                c2837x_block_build_dsp_candidates(project);
            [secondCandidates, secondDependencies] = ...
                c2837x_block_build_dsp_candidates(project);

            testCase.verifyEqual(secondCandidates, firstCandidates);
            testCase.verifyEqual(secondDependencies, firstDependencies);
        end

        function testCoreDependencyChangeInvalidatesSnapshot(testCase)
            [isValid, issues] = changed_dependency_result( ...
                testCase, testCase.WorkFolder, 'core_source');

            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'SNAPSHOT_DEPENDENCY_CHANGED')));
        end

        function testGeneratorDependencyChangeInvalidatesSnapshot(testCase)
            [isValid, issues] = changed_dependency_result( ...
                testCase, testCase.WorkFolder, 'generator_template');

            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'SNAPSHOT_DEPENDENCY_CHANGED')));
        end

        function testDefinitionDependenciesFollowProjectTypes(testCase)
            providerProject = provider_project(testCase.WorkFolder, false);
            [~, providerDependencies] = ...
                c2837x_block_build_dsp_candidates(providerProject);
            providerDefinitions = definition_dependencies(providerDependencies);
            testCase.verifyEqual({providerDefinitions.identity}, ...
                {'dsp-generator:iodevice-definition:test_provider'});
            testCase.verifyNotEmpty(strfind( ...
                providerDefinitions.source_path, ...
                'c2837x_block_iodevice_test_provider_definition.m'));

            mixedProject = provider_project(testCase.WorkFolder, true);
            [~, mixedDependencies] = ...
                c2837x_block_build_dsp_candidates(mixedProject);
            mixedDefinitions = definition_dependencies(mixedDependencies);
            testCase.verifyEqual({mixedDefinitions.identity}, { ...
                'dsp-generator:iodevice-definition:test_provider', ...
                'dsp-generator:iodevice-definition:w5300_tcp'});
            testCase.verifyEqual(numel(unique({mixedDefinitions.identity})), 2);
        end

        function testProviderDefinitionChangeInvalidatesSnapshot(testCase)
            fixturePath = which( ...
                'c2837x_block_iodevice_test_provider_definition');
            providerFolder = fullfile(testCase.WorkFolder, 'provider');
            mkdir(providerFolder);
            providerPath = fullfile(providerFolder, ...
                'c2837x_block_iodevice_test_provider_definition.m');
            copyfile(fixturePath, providerPath);
            addpath(providerFolder, '-begin');
            testCase.addTeardown(@() cleanup_provider_path(providerFolder));
            clear c2837x_block_iodevice_test_provider_definition
            rehash;
            project = provider_project(testCase.WorkFolder, false);
            [candidates, dependencies] = ...
                c2837x_block_build_dsp_candidates(project);
            providerDependency = definition_dependencies(dependencies);
            testCase.verifyEqual(providerDependency.source_path, ...
                c2837x_block_normalize_absolute_path(providerPath));
            [snapshot, snapshotIssues] = c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);
            testCase.assertFalse(any(strcmp({snapshotIssues.severity}, 'Error')));

            write_bytes(providerPath, [read_bytes(providerPath) uint8(10)]);
            [isValid, issues] = c2837x_block_validate_preview_snapshot( ...
                snapshot, project, candidates, dependencies);

            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'SNAPSHOT_DEPENDENCY_CHANGED')));
        end

        function testLegacyWriterRetiresWithoutCreatingTarget(testCase)
            target = fullfile(testCase.WorkFolder, 'missing');

            testCase.verifyError( ...
                @() c2837x_block_generate_dsp_files(struct(), target), ...
                'C2837xBlock:Generation:LegacyDirectWriterRetired');
            testCase.verifyFalse(isfolder(target));
        end

        function testLegacyWriterPreservesExistingFiles(testCase)
            target = fullfile(testCase.WorkFolder, 'existing');
            mkdir(target);
            unrelated = fullfile(target, 'unrelated.txt');
            write_bytes(unrelated, uint8('preserve'));

            testCase.verifyError( ...
                @() c2837x_block_generate_dsp_files(struct(), target), ...
                'C2837xBlock:Generation:LegacyDirectWriterRetired');
            testCase.verifyEqual(read_bytes(unrelated), uint8('preserve'));
            testCase.verifyFalse(isfolder(fullfile(target, 'inc')));
            testCase.verifyFalse(isfolder(fullfile(target, 'src')));
        end
    end
end

function verify_candidates(testCase, candidates, root)
expected = fixed_core_paths();
testCase.verifyNumElements(candidates, 19);
core = candidates(strcmp({candidates.category}, 'core'));
testCase.verifyNumElements(core, 17);
testCase.verifyEqual(relative_targets(root, {core.target_path}), expected);
testCase.verifyEqual({core.category}, repmat({'core'}, 1, 17));
testCase.verifyEqual([core.instance_index], zeros(1, 17));
testCase.verifyEqual({core.owner}, ...
    cellfun(@(path) ['dsp-core:' path], expected, 'UniformOutput', false));
testCase.verifyEqual(numel(unique({core.owner})), 17);
testCase.verifyEmpty(c2837x_block_validate_candidate_files(candidates));
for index = 1:numel(core)
    bytes = core(index).content_bytes;
    text = native2unicode(bytes, 'UTF-8');
    testCase.verifyEqual(reshape(uint8(unicode2native(text, 'UTF-8')), 1, []), bytes);
    testCase.verifyFalse(startsWithBytes(bytes, uint8([239 187 191])));
    testCase.verifyFalse(any(bytes == 13));
    testCase.verifyEqual(bytes(end), uint8(10));
    testCase.verifyTrue(isscalar(bytes) || bytes(end - 1) ~= uint8(10));
    testCase.verifyTrue(contains(text, 'DSP-SimBridge core source'));
    testCase.verifyFalse(contains(text, root));
end
end

function verify_dependencies(testCase, dependencies)
testCase.verifyNumElements(dependencies, 22);
testCase.verifyEqual({dependencies(1:5).role}, ...
    repmat({'generator_template'}, 1, 5));
testCase.verifyEqual({dependencies(6:end).role}, repmat({'core_source'}, 1, 17));
testCase.verifyEqual({dependencies.source_kind}, repmat({'file'}, 1, 22));
testCase.verifyEqual(numel(unique({dependencies.identity})), 22);
testCase.verifyTrue(all(cellfun(@isfile, {dependencies.source_path})));
testCase.verifyTrue(all(cellfun(@isempty, {dependencies.content_bytes})));
end

function values = definition_dependencies(dependencies)
values = dependencies(startsWith({dependencies.identity}, ...
    'dsp-generator:iodevice-definition:'));
end

function cleanup_provider_path(folder)
rmpath(folder);
clear c2837x_block_iodevice_test_provider_definition
rehash;
end

function [isValid, issues] = changed_dependency_result(testCase, root, role)
project = valid_project(root, 'dsp');
[candidates, dependencies] = c2837x_block_build_dsp_candidates(project);
index = find(strcmp({dependencies.role}, role), 1);
copyPath = c2837x_block_normalize_absolute_path(fullfile(root, [role '.m']));
copyfile(dependencies(index).source_path, copyPath);
dependencies(index).source_path = copyPath;
[snapshot, snapshotIssues] = c2837x_block_create_preview_snapshot( ...
    project, candidates, dependencies);
testCase.assertFalse(any(strcmp({snapshotIssues.severity}, 'Error')), ...
    strjoin({snapshotIssues.code}, ', '));
write_bytes(copyPath, [read_bytes(copyPath) uint8(10)]);
[isValid, issues] = c2837x_block_validate_preview_snapshot( ...
    snapshot, project, candidates, dependencies);
end

function project = valid_project(root, dspFolder)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.1.10';
project.common.network.gateway = '0.0.0.0';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, dspFolder));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));
first = valid_instance('Current Loop', 'current_loop', 0, 5000);
second = valid_instance('Voltage Loop', 'voltage_loop', 1, 5001);
project.instances = [first second];
for index = 1:2
    [~, project.instances(index).interface_hash] = ...
        c2837x_block_build_interface_hash(project, index);
end
end

function instance = valid_instance(displayName, internalName, socket, port)
instance = c2837x_block_create_default_instance();
instance.display_name = displayName;
instance.internal_name = internalName;
instance.iodevice.settings.socket_number = uint16(socket);
instance.iodevice.settings.tcp_port = uint16(port);
instance.inputs = struct('name', 'command', 'type', 'single', 'dim', 1);
instance.outputs = struct('name', 'feedback', 'type', 'single', 'dim', 1);
end

function project = provider_project(root, mixed)
project = valid_project(root, 'provider_dsp');
project.instances(1).iodevice.type = 'test_provider';
project.instances(1).iodevice.settings = struct('channel_id', 42);
if mixed
    third = project.instances(1);
    third.display_name = 'Third';
    third.internal_name = 'third';
    project.instances(3) = third;
else
    project.instances = project.instances(1);
end
end

function paths = fixed_core_paths()
paths = {'inc/c2837x_block.h', 'inc/c2837x_block_protocol.h', ...
    'inc/c2837x_block_iodevice.h', 'inc/c2837x_w5300_regs.h', ...
    'inc/c2837x_w5300_hal.h', 'inc/c2837x_w5300_socket.h', ...
    'inc/c2837x_w5300_channel.h', 'src/c2837x_block.c', ...
    'src/c2837x_block_protocol.c', 'src/c2837x_block_internal.h', ...
    'src/c2837x_block_config_internal.h', 'src/c2837x_block_platform.h', ...
    'src/c2837x_block_platform.c', 'src/c2837x_block_timer2.c', ...
    'src/c2837x_w5300_hal.c', 'src/c2837x_w5300_socket.c', ...
    'src/c2837x_w5300_channel.c'};
end

function relative = relative_targets(root, targets)
prefixLength = numel(root) + 2;
relative = cellfun(@(path) strrep(path(prefixLength:end), '\', '/'), ...
    targets, 'UniformOutput', false);
end

function tf = startsWithBytes(bytes, prefix)
tf = numel(bytes) >= numel(prefix) && isequal(bytes(1:numel(prefix)), prefix);
end

function write_bytes(path, bytes)
fileID = fopen(path, 'wb');
assert(fileID >= 0, 'Test file could not be opened.');
cleanup = onCleanup(@() fclose(fileID));
fwrite(fileID, bytes, 'uint8');
clear cleanup
end

function bytes = read_bytes(path)
fileID = fopen(path, 'rb');
assert(fileID >= 0, 'Test file could not be read.');
cleanup = onCleanup(@() fclose(fileID));
bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
clear cleanup
end
