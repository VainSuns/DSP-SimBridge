classdef test_udp_s5_04_mixed_generation < matlab.unittest.TestCase
    properties (TestParameter)
        representative = struct( ...
            'udp_only', struct('types', {{'w5300_udp'}}), ...
            'tcp_udp', struct('types', {{'w5300_tcp', 'w5300_udp'}}), ...
            'udp_sci', struct('types', {{'w5300_udp', 'sci'}}), ...
            'tcp_udp_sci', struct('types', ...
            {{'w5300_tcp', 'w5300_udp', 'sci'}}))
    end

    properties
        WorkFolder
        RepositoryRoot
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            testCase.RepositoryRoot = fileparts(fileparts(fileparts( ...
                mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'app')));
        end
    end

    methods (TestMethodSetup)
        function createWorkFolder(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.WorkFolder = fixture.Folder;
        end
    end

    methods (Test)
        function testRepresentativeMixedClosureAndTransaction(testCase, ...
                representative)
            project = make_project(testCase.WorkFolder, representative.types);
            [firstCandidates, firstDependencies, firstBuildIssues] = ...
                c2837x_block_build_project_candidates(project);
            [secondCandidates, secondDependencies, secondBuildIssues] = ...
                c2837x_block_build_project_candidates(project);

            verify_repeated_generation(testCase, firstCandidates, ...
                firstDependencies, firstBuildIssues, secondCandidates, ...
                secondDependencies, secondBuildIssues);
            verify_dsp_closure(testCase, project, firstCandidates, ...
                representative.types);
            verify_sfun_closure(testCase, project, firstCandidates, ...
                representative.types);
            verify_candidate_isolation(testCase, firstCandidates, project);
            verify_dependencies(testCase, firstDependencies, ...
                representative.types, testCase.RepositoryRoot);

            beforePreview = filesystem_snapshot(project.output.dsp_root, ...
                project.output.sfun_root);
            [snapshot, snapshotIssues, summary] = ...
                c2837x_block_create_preview_snapshot(project, firstCandidates, ...
                firstDependencies);
            afterPreview = filesystem_snapshot(project.output.dsp_root, ...
                project.output.sfun_root);
            [snapshotValid, validationIssues, currentSummary] = ...
                c2837x_block_validate_preview_snapshot(snapshot, project, ...
                firstCandidates, firstDependencies);

            testCase.verifyFalse(has_errors(firstBuildIssues));
            testCase.verifyFalse(has_errors(secondBuildIssues));
            testCase.verifyFalse(has_errors(snapshotIssues));
            testCase.verifyTrue(snapshotValid);
            testCase.verifyFalse(has_errors(validationIssues));
            testCase.verifyEqual(afterPreview, beforePreview);
            testCase.verifyEqual(summary.candidate_count, ...
                double(numel(firstCandidates)));
            testCase.verifyEqual(currentSummary, summary);
            testCase.verifyEqual(snapshot.candidates, firstCandidates);
            testCase.verifyEqual({snapshot.comparison_baseline.default_action}, ...
                repmat({'create'}, 1, numel(firstCandidates)));
            verify_snapshot_dependency_capture(testCase, snapshot);

            [result, commitIssues] = c2837x_block_commit_preview_snapshot( ...
                snapshot, project, firstCandidates, firstDependencies);

            testCase.verifyTrue(result.success);
            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyFalse(has_errors(commitIssues));
            testCase.verifyEqual(result.created_count, ...
                numel(firstCandidates));
            testCase.verifyEqual(result.replaced_count, 0);
            testCase.verifyEqual(result.skipped_count, 0);
            testCase.verifyEqual(result.kept_count, 0);
            testCase.verifyEqual({result.files.target_path}, ...
                {firstCandidates.target_path});
            testCase.verifyEqual({result.files.outcome}, ...
                repmat({'created'}, 1, numel(firstCandidates)));
            verify_written_candidates(testCase, firstCandidates);

            [thirdCandidates, thirdDependencies, thirdBuildIssues] = ...
                c2837x_block_build_project_candidates(project);
            [secondSnapshot, secondSnapshotIssues, secondSummary] = ...
                c2837x_block_create_preview_snapshot(project, thirdCandidates, ...
                thirdDependencies);
            [secondValid, secondValidationIssues, secondCurrentSummary] = ...
                c2837x_block_validate_preview_snapshot(secondSnapshot, project, ...
                thirdCandidates, thirdDependencies);
            [secondResult, secondCommitIssues] = ...
                c2837x_block_commit_preview_snapshot(secondSnapshot, project, ...
                thirdCandidates, thirdDependencies);

            testCase.verifyFalse(has_errors(thirdBuildIssues));
            testCase.verifyFalse(has_errors(secondSnapshotIssues));
            testCase.verifyTrue(secondValid);
            testCase.verifyFalse(has_errors(secondValidationIssues));
            testCase.verifyEqual(thirdCandidates, firstCandidates);
            testCase.verifyEqual(thirdDependencies, firstDependencies);
            testCase.verifyEqual(secondSummary.candidate_count, ...
                double(numel(firstCandidates)));
            testCase.verifyEqual(secondCurrentSummary, secondSummary);
            testCase.verifyEqual({secondSnapshot.comparison_baseline.default_action}, ...
                repmat({'skip'}, 1, numel(firstCandidates)));
            testCase.verifyTrue(secondResult.success);
            testCase.verifyEqual(secondResult.status, 'completed');
            testCase.verifyFalse(has_errors(secondCommitIssues));
            testCase.verifyEqual(secondResult.skipped_count, ...
                numel(firstCandidates));
            testCase.verifyEqual(secondResult.created_count, 0);
            testCase.verifyEqual(secondResult.replaced_count, 0);
            testCase.verifyEqual(secondResult.kept_count, 0);
        end

        function testMixedUserProtectionAndGeneratedReplacement(testCase)
            project = make_project(testCase.WorkFolder, ...
                {'w5300_tcp', 'w5300_udp'});
            [candidates, dependencies, buildIssues] = ...
                c2837x_block_build_project_candidates(project);
            userIndex = find(strcmp({candidates.category}, 'user') & ...
                endsWith({candidates.target_path}, 'sfun_user_config.h'), 1);
            generatedIndex = find(strcmp({candidates.category}, ...
                'auto_generated') & endsWith({candidates.target_path}, ...
                'sfun_config.h'), 1);
            testCase.assertEqual(numel(userIndex), 1);
            testCase.assertEqual(numel(generatedIndex), 1);
            userBytes = uint8('protected mixed user configuration');
            generatedBytes = uint8('stale generated configuration');
            write_bytes(candidates(userIndex).target_path, userBytes);
            write_bytes(candidates(generatedIndex).target_path, ...
                generatedBytes);

            [snapshot, snapshotIssues] = ...
                c2837x_block_create_preview_snapshot(project, candidates, ...
                dependencies);
            [result, commitIssues] = c2837x_block_commit_preview_snapshot( ...
                snapshot, project, candidates, dependencies);

            testCase.verifyFalse(has_errors(buildIssues));
            testCase.verifyFalse(has_errors(snapshotIssues));
            testCase.verifyEqual( ...
                snapshot.comparison_baseline(userIndex).default_action, 'keep');
            testCase.verifyFalse( ...
                snapshot.comparison_baseline(userIndex).action_mandatory);
            testCase.verifyEqual( ...
                snapshot.comparison_baseline(generatedIndex).default_action, ...
                'replace');
            testCase.verifyTrue(result.success);
            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyFalse(has_errors(commitIssues));
            testCase.verifyEqual(result.files(userIndex).outcome, 'kept');
            testCase.verifyEqual(result.files(generatedIndex).outcome, ...
                'replaced');
            testCase.verifyEqual(read_bytes(candidates(userIndex).target_path), ...
                userBytes);
            testCase.verifyEqual( ...
                read_bytes(candidates(generatedIndex).target_path), ...
                candidates(generatedIndex).content_bytes);
        end

        function testMixedSnapshotRejectsStaleProject(testCase)
            project = make_project(testCase.WorkFolder, ...
                {'w5300_tcp', 'w5300_udp', 'sci'});
            [candidates, dependencies, buildIssues] = ...
                c2837x_block_build_project_candidates(project);
            [snapshot, snapshotIssues] = ...
                c2837x_block_create_preview_snapshot(project, candidates, ...
                dependencies);
            changedProject = project;
            changedProject.common.network.ip = '192.168.1.101';
            [changedCandidates, changedDependencies, changedBuildIssues] = ...
                c2837x_block_build_project_candidates(changedProject);
            beforeCommit = filesystem_snapshot(project.output.dsp_root, ...
                project.output.sfun_root);
            [snapshotValid, validationIssues] = ...
                c2837x_block_validate_preview_snapshot(snapshot, changedProject, ...
                changedCandidates, changedDependencies);
            [result, commitIssues] = c2837x_block_commit_preview_snapshot( ...
                snapshot, changedProject, changedCandidates, changedDependencies);
            afterCommit = filesystem_snapshot(project.output.dsp_root, ...
                project.output.sfun_root);

            testCase.verifyFalse(has_errors(buildIssues));
            testCase.verifyFalse(has_errors(snapshotIssues));
            testCase.verifyFalse(has_errors(changedBuildIssues));
            testCase.verifyFalse(snapshotValid);
            testCase.verifyTrue(any(strcmp({validationIssues.code}, ...
                'SNAPSHOT_PROJECT_CHANGED')));
            testCase.verifyTrue(any(strcmp({validationIssues.code}, ...
                'SNAPSHOT_CANDIDATE_CHANGED')));
            testCase.verifyFalse(result.success);
            testCase.verifyEqual(result.status, 'blocked');
            testCase.verifyTrue(any(strcmp({commitIssues.code}, ...
                'SNAPSHOT_PROJECT_CHANGED')));
            testCase.verifyEqual(afterCommit, beforeCommit);
        end

        function testUnknownIoDeviceDoesNotFallbackToTcp(testCase)
            project = make_project(testCase.WorkFolder, {'w5300_udp'});
            project.instances(1).iodevice.type = 'unsupported_iodevice';
            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'IODEVICE_UNSUPPORTED')));
            testCase.verifyError( ...
                @() c2837x_block_build_project_candidates(project), ...
                'C2837xBlock:IoDevice:Unsupported');
        end
    end
end

function project = make_project(root, types)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.1.10';
project.common.network.gateway = '192.168.1.1';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));

base = c2837x_block_create_default_instance();
base.inputs = struct('name', 'command', 'type', 'uint16', 'dim', 1);
base.outputs = struct('name', 'feedback', 'type', 'uint16', 'dim', 1);
project.instances = base([]);
for index = 1:numel(types)
    instance = base;
    instance.display_name = sprintf('Instance %u', index);
    instance.internal_name = sprintf('instance_%u', index);
    instance.iodevice = c2837x_block_create_iodevice(types{index});
    switch types{index}
        case 'w5300_tcp'
            instance.iodevice.settings.socket_number = uint16(index - 1);
            instance.iodevice.settings.tcp_port = uint16(5000 + index - 1);
        case 'w5300_udp'
            instance.iodevice.settings.socket_number = uint16(index - 1);
            instance.iodevice.settings.udp_port = uint16(6000 + index - 1);
        case 'sci'
            instance.iodevice.settings.module = 'SCI-B';
            instance.iodevice.settings.baud = uint32(115200);
            instance.iodevice.settings.rx_gpio = 'GPIO19';
            instance.iodevice.settings.tx_gpio = 'GPIO14';
            instance.iodevice.settings.rx_pin_type = 'Standard';
            instance.iodevice.settings.rx_qualification = 'Sync';
            instance.iodevice.settings.tx_pin_type = 'Pull-up';
            instance.iodevice.settings.ctrl_gpio = 'None';
            instance.iodevice.settings.ctrl_pin_type = 'Standard';
            instance.iodevice.settings.ctrl_tx_active_level = 'Low';
    end
    project.instances(end + 1) = instance;
end
for index = 1:numel(project.instances)
    [~, project.instances(index).interface_hash] = ...
        c2837x_block_build_interface_hash(project, index);
end
end

function verify_repeated_generation(testCase, firstCandidates, ...
        firstDependencies, firstBuildIssues, secondCandidates, ...
        secondDependencies, secondBuildIssues)
testCase.verifyEqual(secondCandidates, firstCandidates);
testCase.verifyEqual(secondDependencies, firstDependencies);
testCase.verifyEqual(secondBuildIssues, firstBuildIssues);
testCase.verifyEmpty(c2837x_block_validate_candidate_files(firstCandidates));
end

function verify_dsp_closure(testCase, project, candidates, types)
core = candidates(strcmp({candidates.category}, 'core'));
testCase.verifyEqual(relative_paths(core, project.output.dsp_root), ...
    expected_core_paths(types));
projectSource = candidate_text(testCase, candidates, ...
    'c2837x_block_project.c');
if has_type(types, 'w5300_tcp') || has_type(types, 'w5300_udp')
    testCase.verifyEqual(numel(regexp(projectSource, ...
        ['(?m)^const\s+C2837xW5300ProjectConfig\s+' ...
        'c2837x_w5300_project_config\s*='], 'match')), 1);
    testCase.verifyEqual(numel(regexp(projectSource, ...
        '(?m)^\s*c2837x_w5300_project_config\s*=', 'match')), 1);
    testCase.verifySubstring(projectSource, 'c2837x_block_platform_config');
else
    testCase.verifyEmpty(strfind(projectSource, ...
        'c2837x_w5300_project_config'));
end

for index = 1:numel(types)
    name = char(project.instances(index).internal_name);
    configText = candidate_text(testCase, candidates, [name '_config.c']);
    ioText = candidate_text(testCase, candidates, [name '_io.c']);
    switch types{index}
        case 'w5300_tcp'
            testCase.verifySubstring(configText, ...
                '&c2837x_w5300_iodevice_ops');
            testCase.verifySubstring(configText, ...
                ['c2837x_block_' name '_iodevice_channel']);
            testCase.verifySubstring(ioText, ...
                'C2837X_W5300_CHANNEL_INITIALIZER');
        case 'w5300_udp'
            testCase.verifySubstring(configText, ...
                '&c2837x_w5300_udp_iodevice_ops');
            testCase.verifySubstring(configText, ...
                ['c2837x_block_' name '_iodevice_channel']);
            testCase.verifySubstring(ioText, ...
                'C2837X_W5300_UDP_CHANNEL_INITIALIZER');
        case 'sci'
            testCase.verifySubstring(configText, ...
                '&c2837x_block_sci_iodevice_ops');
            testCase.verifySubstring(configText, ...
                ['c2837x_block_' name '_iodevice_channel']);
            testCase.verifySubstring(ioText, ...
                'C2837X_BLOCK_SCI_CHANNEL_INITIALIZER');
    end
end
end

function verify_sfun_closure(testCase, project, candidates, types)
for index = 1:numel(types)
    name = char(project.instances(index).internal_name);
    selected = candidates([candidates.instance_index] == index & ...
        under_root({candidates.target_path}, project.output.sfun_root));
    testCase.verifyEqual(relative_paths(selected, project.output.sfun_root), ...
        expected_sfun_paths(name, types{index}));
    buildText = candidate_text(testCase, selected, ...
        ['build_' name '_sfun.m']);
    protocolHeader = candidate_text(testCase, selected, ...
        [name '_protocol.h']);
    switch types{index}
        case 'w5300_tcp'
            transport = 'pc_socket';
            testCase.verifySubstring(protocolHeader, ...
                ['#include "' name '_pc_socket.h"']);
            testCase.verifySubstring(buildText, [name '_pc_socket.c']);
            testCase.verifySubstring(buildText, [name '_pc_socket.h']);
        case 'w5300_udp'
            transport = 'pc_udp';
            testCase.verifySubstring(protocolHeader, ...
                ['#include "' name '_pc_udp.h"']);
            testCase.verifySubstring(buildText, [name '_pc_udp.c']);
            testCase.verifySubstring(buildText, [name '_pc_udp.h']);
        case 'sci'
            transport = 'pc_serial';
            testCase.verifySubstring(protocolHeader, ...
                ['#include "' name '_pc_serial.h"']);
            testCase.verifySubstring(buildText, [name '_pc_serial.c']);
            testCase.verifySubstring(buildText, [name '_pc_serial.h']);
    end
    allText = candidate_group_text(selected);
    transportNames = {'pc_socket', 'pc_udp', 'pc_serial'};
    for transportIndex = 1:numel(transportNames)
        if strcmp(transportNames{transportIndex}, transport)
            selectedPaths = relative_paths(selected, project.output.sfun_root);
            testCase.verifyEqual( ...
                sum(endsWith(selectedPaths, ...
                [name '_' transportNames{transportIndex} '.c'])) + ...
                sum(endsWith(selectedPaths, ...
                [name '_' transportNames{transportIndex} '.h'])), 2);
        else
            testCase.verifyEmpty(strfind(allText, transportNames{transportIndex}));
        end
    end
    testCase.verifyTrue(contains(allText, [name '_protocol.c']));
    testCase.verifyTrue(contains(allText, [name '_protocol.h']));
end
end

function verify_candidate_isolation(testCase, candidates, project)
paths = lower({candidates.target_path});
owners = {candidates.owner};
testCase.verifyEqual(numel(unique(paths)), numel(paths));
testCase.verifyEqual(numel(unique(owners)), numel(owners));
testCase.verifyEmpty(c2837x_block_validate_candidate_files(candidates));
for index = 1:numel(project.instances)
    name = char(project.instances(index).internal_name);
    selected = candidates([candidates.instance_index] == index & ...
        under_root({candidates.target_path}, project.output.sfun_root));
    text = candidate_group_text(selected);
    testCase.verifySubstring(text, name);
    otherIndices = setdiff(1:numel(project.instances), index);
    for otherIndex = otherIndices
        testCase.verifyFalse(contains(text, ...
            char(project.instances(otherIndex).internal_name)));
    end
end
end

function verify_dependencies(testCase, dependencies, types, repositoryRoot)
paths = {dependencies.source_path};
lowerPaths = lower_cell(paths);
rootPrefix = lower([repositoryRoot filesep]);
testCase.verifyTrue(all(cellfun(@(path) startsWith(path, rootPrefix), ...
    lowerPaths)));
testCase.verifyTrue(all(strcmp({dependencies.source_kind}, 'file')));
testCase.verifyEqual(numel(unique(lowerPaths)), numel(lowerPaths));
testCase.verifyEqual(numel(unique({dependencies.identity})), ...
    numel(dependencies));
testCase.verifyTrue(has_dependency(lowerPaths, ...
    'app/templates/protocol.c.in'));
testCase.verifyTrue(has_dependency(lowerPaths, ...
    'app/templates/protocol.h.in'));
testCase.verifyTrue(has_dependency(lowerPaths, 'simulink/c2837x_block_pc_error.h'));

corePaths = expected_core_paths(types);
for pathIndex = 1:numel(corePaths)
    testCase.verifyTrue(has_dependency(lowerPaths, ...
        ['dsp/' corePaths{pathIndex}]));
end

expected = {};
unexpected = {};
if has_type(types, 'w5300_tcp')
    expected = [expected, ...
        {'app/c2837x_block_iodevice_w5300_tcp_definition.m', ...
        'app/templates/pc_socket.c.in', 'app/templates/pc_socket.h.in'}];
else
    unexpected = [unexpected, ...
        {'app/c2837x_block_iodevice_w5300_tcp_definition.m', ...
        'app/templates/pc_socket.c.in', 'app/templates/pc_socket.h.in'}];
end
if has_type(types, 'w5300_udp')
    expected = [expected, ...
        {'app/c2837x_block_iodevice_w5300_udp_definition.m', ...
        'app/templates/pc_udp.c.in', 'app/templates/pc_udp.h.in'}];
else
    unexpected = [unexpected, ...
        {'app/c2837x_block_iodevice_w5300_udp_definition.m', ...
        'app/templates/pc_udp.c.in', 'app/templates/pc_udp.h.in'}];
end
if has_type(types, 'sci')
    expected = [expected, ...
        {'app/c2837x_block_iodevice_sci_definition.m', ...
        'simulink/c2837x_block_pc_serial.c', ...
        'simulink/c2837x_block_pc_serial.h', ...
        'app/c2837x_block_calculate_sci_baud.m', ...
        'app/c2837x_block_get_sci_clock_config.m', ...
        'app/c2837x_block_load_device_capability.m', ...
        'app/capabilities/TMS320F28377D_PTP.json'}];
else
    unexpected = [unexpected, ...
        {'app/c2837x_block_iodevice_sci_definition.m', ...
        'simulink/c2837x_block_pc_serial.c', ...
        'simulink/c2837x_block_pc_serial.h', ...
        'app/c2837x_block_calculate_sci_baud.m', ...
        'app/c2837x_block_get_sci_clock_config.m', ...
        'app/c2837x_block_load_device_capability.m', ...
        'app/capabilities/TMS320F28377D_PTP.json'}];
end
for pathIndex = 1:numel(expected)
    testCase.verifyTrue(has_dependency(lowerPaths, expected{pathIndex}), ...
        expected{pathIndex});
end
for pathIndex = 1:numel(unexpected)
    testCase.verifyFalse(has_dependency(lowerPaths, unexpected{pathIndex}), ...
        unexpected{pathIndex});
end
end

function verify_snapshot_dependency_capture(testCase, snapshot)
for index = 1:numel(snapshot.dependencies)
    bytes = read_bytes(snapshot.dependencies(index).source_path);
    testCase.verifyEqual(snapshot.dependencies(index).content_bytes, bytes);
    testCase.verifyEqual(snapshot.dependencies(index).content_size_octets, ...
        double(numel(bytes)));
end
end

function verify_written_candidates(testCase, candidates)
for index = 1:numel(candidates)
    testCase.verifyTrue(isfile(candidates(index).target_path));
    testCase.verifyEqual(read_bytes(candidates(index).target_path), ...
        candidates(index).content_bytes);
end
end

function paths = expected_core_paths(types)
commonHeaders = {'inc/c2837x_block.h', ...
    'inc/c2837x_block_protocol.h', 'inc/c2837x_block_iodevice.h'};
w5300Headers = {'inc/c2837x_w5300_regs.h', ...
    'inc/c2837x_w5300_hal.h', 'inc/c2837x_w5300_socket.h'};
commonSources = {'src/c2837x_block.c', 'src/c2837x_block_protocol.c', ...
    'src/c2837x_block_internal.h', 'src/c2837x_block_config_internal.h', ...
    'src/c2837x_block_platform.h', 'src/c2837x_block_platform.c', ...
    'src/c2837x_block_timer2.c'};
paths = commonHeaders;
if has_type(types, 'w5300_tcp') || has_type(types, 'w5300_udp')
    paths = [paths w5300Headers];
end
if has_type(types, 'w5300_tcp')
    paths{end + 1} = 'inc/c2837x_w5300_channel.h';
end
if has_type(types, 'w5300_udp')
    paths{end + 1} = 'inc/c2837x_w5300_udp_channel.h';
end
if has_type(types, 'sci')
    paths{end + 1} = 'inc/c2837x_block_sci.h';
end
paths = [paths commonSources];
if has_type(types, 'w5300_tcp') || has_type(types, 'w5300_udp')
    paths = [paths {'src/c2837x_w5300_hal.c', ...
        'src/c2837x_w5300_socket.c'}];
end
if has_type(types, 'w5300_tcp')
    paths{end + 1} = 'src/c2837x_w5300_channel.c';
end
if has_type(types, 'w5300_udp')
    paths{end + 1} = 'src/c2837x_w5300_udp_channel.c';
end
if has_type(types, 'sci')
    paths{end + 1} = 'src/c2837x_block_sci.c';
end
end

function paths = expected_sfun_paths(name, type)
common = {[name '/' name '_sfun.c'], [name '/' name '_sfun.h'], ...
    [name '/' name '_sfun_io.c'], [name '/' name '_sfun_config.h'], ...
    [name '/' name '_sfun_user_config.h'], [name '/' name '_pc_error.h']};
switch type
    case 'w5300_tcp'
        transport = {[name '/' name '_pc_socket.c'], ...
            [name '/' name '_pc_socket.h']};
    case 'w5300_udp'
        transport = {[name '/' name '_pc_udp.c'], ...
            [name '/' name '_pc_udp.h']};
    case 'sci'
        transport = {[name '/' name '_pc_serial.c'], ...
            [name '/' name '_pc_serial.h']};
end
tail = {[name '/' name '_protocol.c'], [name '/' name '_protocol.h'], ...
    [name '/build_' name '_sfun.m']};
paths = [common transport tail];
end

function paths = relative_paths(candidates, root)
prefix = [root filesep];
paths = cell(1, numel(candidates));
for index = 1:numel(candidates)
    target = candidates(index).target_path;
    paths{index} = strrep(target(numel(prefix) + 1:end), filesep, '/');
end
end

function text = candidate_text(testCase, candidates, suffix)
index = find(endsWith({candidates.target_path}, suffix), 1);
testCase.assertEqual(numel(index), 1);
text = native2unicode(candidates(index).content_bytes, 'UTF-8');
end

function text = candidate_group_text(candidates)
text = '';
for index = 1:numel(candidates)
    text = [text newline native2unicode(candidates(index).content_bytes, ...
        'UTF-8')]; %#ok<AGROW>
end
end

function tf = has_type(types, type)
tf = any(strcmp(types, type));
end

function tf = has_dependency(paths, suffix)
suffix = lower(strrep(suffix, '/', filesep));
tf = any(endsWith(paths, suffix));
end

function mask = under_root(paths, root)
prefix = lower([root filesep]);
mask = cellfun(@(path) startsWith(lower(path), prefix), paths);
end

function values = lower_cell(values)
values = cellfun(@lower, values, 'UniformOutput', false);
end

function value = filesystem_snapshot(varargin)
value = struct('path', {}, 'bytes', {});
for rootIndex = 1:nargin
    root = varargin{rootIndex};
    if ~isfolder(root)
        continue;
    end
    entries = dir(fullfile(root, '**', '*'));
    entries = entries(~[entries.isdir]);
    for index = 1:numel(entries)
        path = fullfile(entries(index).folder, entries(index).name);
        value(end + 1) = struct('path', path, ...
            'bytes', read_bytes(path)); %#ok<AGROW>
    end
end
if ~isempty(value)
    [~, order] = sort(lower_cell({value.path}));
    value = value(order);
end
end

function write_bytes(path, bytes)
folder = fileparts(path);
if ~isfolder(folder)
    mkdir(folder);
end
fileID = fopen(path, 'wb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
assert(fwrite(fileID, bytes, 'uint8') == numel(bytes));
clear cleanup
end

function bytes = read_bytes(path)
fileID = fopen(path, 'rb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
clear cleanup
end

function tf = has_errors(issues)
tf = ~isempty(issues) && any(strcmp({issues.severity}, 'Error'));
end
