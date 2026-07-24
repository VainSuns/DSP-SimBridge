classdef test_preview_snapshot < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addPreviewPaths(testCase)
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
        function testCreatesFixedSnapshotAndSummary(testCase)
            bundle = preview_bundle(testCase.WorkFolder);

            [snapshot, issues, summary] = create_snapshot(bundle);

            testCase.verifyFalse(has_errors(issues));
            testCase.verifyEqual(fieldnames(snapshot), {'schema_version'; 'project'; ...
                'output_paths'; 'interface_specs'; 'dependencies'; ...
                'external_sources'; 'candidates'; 'comparison_baseline'; ...
                'target_states'});
            testCase.verifyEqual(snapshot.schema_version, uint16(1));
            testCase.verifyClass(snapshot.schema_version, 'uint16');
            testCase.verifyEqual([snapshot.interface_specs.instance_index], [1 2]);
            testCase.verifyClass(snapshot.interface_specs(1).interface_hash, 'uint32');
            testCase.verifyEqual({snapshot.dependencies.role}, ...
                {'generator_template', 'core_source'});
            testCase.verifyEqual({snapshot.external_sources.mode}, ...
                {'external_copy', 'external_reference'});
            testCase.verifyEqual({snapshot.comparison_baseline.target_state}, ...
                {'missing', 'same', 'different', 'same', 'different', ...
                'missing', 'same', 'different'});
            testCase.verifyEqual({snapshot.target_states.state}, ...
                {'missing', 'file', 'file', 'file', 'file', 'missing', 'file', 'file'});
            testCase.verifyEqual(summary, expected_summary(bundle, snapshot));
        end

        function testUnchangedSnapshotIsDeterministicAndPwdIndependent(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            [snapshot, ~, summary] = create_snapshot(bundle);
            original = snapshot;

            [firstValid, firstIssues, firstSummary] = validate_snapshot(snapshot, bundle);
            testCase.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(tempdir));
            [secondValid, secondIssues, secondSummary] = validate_snapshot(snapshot, bundle);

            testCase.verifyTrue(firstValid);
            testCase.verifyTrue(secondValid);
            testCase.verifyFalse(has_errors(firstIssues));
            testCase.verifyEqual(secondIssues, firstIssues);
            testCase.verifyEqual(firstSummary, summary);
            testCase.verifyEqual(secondSummary, summary);
            testCase.verifyEqual(snapshot, original);
        end

        function testRepeatedCreationIsIsequalnDeterministic(testCase)
            bundle = preview_bundle(testCase.WorkFolder);

            [first, firstIssues, firstSummary] = create_snapshot(bundle);
            [second, secondIssues, secondSummary] = create_snapshot(bundle);

            testCase.verifyTrue(isequaln(first, second));
            testCase.verifyTrue(isequaln(firstSummary, secondSummary));
            testCase.verifyEqual(secondIssues, firstIssues);
        end

        function testProjectChangesInvalidateExpectedGroups(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);

            verify_project_change(testCase, snapshot, bundle, ...
                set_field(bundle.project, 'common.abi', 'coffabi'), ...
                {'SNAPSHOT_PROJECT_CHANGED'});
            verify_project_change(testCase, snapshot, bundle, ...
                set_field(bundle.project, 'common.network.ip', '192.168.7.20'), ...
                {'SNAPSHOT_PROJECT_CHANGED'});
            verify_project_change(testCase, snapshot, bundle, ...
                set_field(bundle.project, 'instances(1).sample_time_sec', 2e-4), ...
                {'SNAPSHOT_PROJECT_CHANGED'});
            verify_project_change(testCase, snapshot, bundle, ...
                set_field(bundle.project, 'instances(1).display_name', 'Renamed'), ...
                {'SNAPSHOT_PROJECT_CHANGED'});
            verify_project_change(testCase, snapshot, bundle, ...
                set_field(bundle.project, ...
                'instances(1).iodevice.settings.socket_number', uint16(2)), ...
                {'SNAPSHOT_PROJECT_CHANGED'});
        end

        function testOutputAndInterfaceChangesReportAllGroups(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            outputProject = bundle.project;
            outputProject.output.dsp_root = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'other_dsp'));
            ioProject = bundle.project;
            ioProject.instances(1).inputs(1).name = 'command2';

            verify_project_change(testCase, snapshot, bundle, outputProject, ...
                {'SNAPSHOT_PROJECT_CHANGED', 'SNAPSHOT_OUTPUT_PATH_CHANGED'});
            verify_project_change(testCase, snapshot, bundle, ioProject, ...
                {'SNAPSHOT_PROJECT_CHANGED', 'SNAPSHOT_INTERFACE_CHANGED'});
        end

        function testAlgorithmModeAndPathChangesInvalidate(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            modeProject = bundle.project;
            modeProject.instances(1).algorithm.mode = 'external_reference';
            pathProject = bundle.project;
            pathProject.instances(1).algorithm.source_path = ...
                bundle.project.instances(2).algorithm.source_path;

            verify_project_change(testCase, snapshot, bundle, modeProject, ...
                {'SNAPSHOT_PROJECT_CHANGED', 'SNAPSHOT_EXTERNAL_SOURCE_CHANGED'});
            verify_project_change(testCase, snapshot, bundle, pathProject, ...
                {'SNAPSHOT_PROJECT_CHANGED', 'SNAPSHOT_EXTERNAL_SOURCE_CHANGED'});
        end

        function testCorruptInterfaceTextAndHashInvalidate(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            textSnapshot = create_snapshot(bundle);
            textSnapshot.interface_specs(1).canonical_text = 'damaged';
            hashSnapshot = create_snapshot(bundle);
            hashSnapshot.interface_specs(1).interface_hash = uint32(7);

            verify_invalid_code(testCase, textSnapshot, bundle, ...
                'SNAPSHOT_INTERFACE_CHANGED');
            verify_invalid_code(testCase, hashSnapshot, bundle, ...
                'SNAPSHOT_INTERFACE_CHANGED');
        end

        function testMemoryAndFileDependenciesCaptureRawOctets(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            memoryChanged = bundle;
            memoryChanged.dependencies(1).content_bytes(2) = uint8(99);

            verify_invalid_code(testCase, snapshot, memoryChanged, ...
                'SNAPSHOT_DEPENDENCY_CHANGED');
            testCase.verifyEqual(snapshot.dependencies(2).content_bytes, ...
                read_bytes(bundle.dependencies(2).source_path));
        end

        function testFileDependencyChangesAndDeletionInvalidate(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            corePath = bundle.dependencies(2).source_path;

            write_bytes(corePath, uint8([10 20 31]));
            verify_invalid_code(testCase, snapshot, bundle, ...
                'SNAPSHOT_DEPENDENCY_CHANGED');
            delete(corePath);
            [isValid, issues] = validate_snapshot(snapshot, bundle);

            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'SNAPSHOT_DEPENDENCY_UNREADABLE')));
        end

        function testFileDependencyDirectoryInvalidates(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            corePath = bundle.dependencies(2).source_path;

            delete(corePath);
            mkdir(corePath);
            [isValid, issues] = validate_snapshot(snapshot, bundle);

            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'SNAPSHOT_DEPENDENCY_UNREADABLE')));
        end

        function testUnreadableDependencyIsAssumedOnWindows(testCase)
            testCase.assumeFalse(ispc, ...
                'Windows current-account permissions do not reliably create an unreadable file.');
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            path = bundle.dependencies(2).source_path;
            make_unreadable(testCase, path);

            [isValid, issues] = validate_snapshot(snapshot, bundle);

            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'SNAPSHOT_DEPENDENCY_UNREADABLE')));
        end

        function testExternalCopyOctetAndLineEndingChangesInvalidate(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            path = bundle.project.instances(1).algorithm.source_path;

            write_bytes(path, uint8('copy changed'));
            verify_invalid_code(testCase, snapshot, bundle, ...
                'SNAPSHOT_EXTERNAL_SOURCE_CHANGED');
            write_bytes(path, uint8(sprintf('int copy(void) { return 1; }\r\n')));
            verify_invalid_code(testCase, snapshot, bundle, ...
                'SNAPSHOT_EXTERNAL_SOURCE_CHANGED');
        end

        function testExternalReferenceChangeAndDeletionInvalidate(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            path = bundle.project.instances(2).algorithm.source_path;

            write_bytes(path, uint8('reference changed'));
            verify_invalid_code(testCase, snapshot, bundle, ...
                'SNAPSHOT_EXTERNAL_SOURCE_CHANGED');
            delete(path);
            [isValid, issues] = validate_snapshot(snapshot, bundle);

            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({issues.code}, 'ALGORITHM_SOURCE_MISSING')));
        end

        function testCandidateFieldChangesInvalidate(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);

            changed = bundle; changed.candidates(1).target_path = ...
                c2837x_block_normalize_absolute_path(fullfile(testCase.WorkFolder, 'new.bin'));
            verify_invalid_code(testCase, snapshot, changed, 'SNAPSHOT_CANDIDATE_CHANGED');
            changed = bundle; changed.candidates(1).category = 'core';
            verify_invalid_code(testCase, snapshot, changed, 'SNAPSHOT_CANDIDATE_CHANGED');
            changed = bundle; changed.candidates(1).owner = 'changed';
            verify_invalid_code(testCase, snapshot, changed, 'SNAPSHOT_CANDIDATE_CHANGED');
            changed = bundle; changed.candidates(1).instance_index = 1;
            verify_invalid_code(testCase, snapshot, changed, 'SNAPSHOT_CANDIDATE_CHANGED');
            changed = bundle; changed.candidates(1).content_bytes = uint8(9);
            changed.candidates(1).content_size_octets = 1;
            verify_invalid_code(testCase, snapshot, changed, 'SNAPSHOT_CANDIDATE_CHANGED');
        end

        function testInvalidCandidatePreventsCurrentSnapshot(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            bundle.candidates(1).content_size_octets = 99;

            [isValid, issues, summary] = validate_snapshot(snapshot, bundle);

            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'CANDIDATE_CONTENT_SIZE_INVALID')));
            testCase.verifyEqual(summary, empty_summary());
        end

        function testMissingFileAndDirectoryTransitionsInvalidate(testCase)
            verify_target_mutation(testCase, ...
                isolated_bundle(testCase.WorkFolder, 'missing_file'), ...
                1, uint8(1), 'write');
            verify_target_mutation(testCase, ...
                isolated_bundle(testCase.WorkFolder, 'file_missing'), ...
                2, uint8(0), 'delete');
            verify_target_mutation(testCase, ...
                isolated_bundle(testCase.WorkFolder, 'file_directory'), ...
                2, uint8(0), 'directory');
        end

        function testExactTargetOctetVariantsInvalidate(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            verify_target_bytes(testCase, bundle, 8, uint8('A'), uint8('B'));
            verify_target_bytes(testCase, bundle, 8, ...
                uint8(sprintf('A\n')), uint8(sprintf('A\r\n')));
            verify_target_bytes(testCase, bundle, 8, uint8('A'), uint8([239 187 191 65]));
            verify_target_bytes(testCase, bundle, 8, uint8([65 10]), uint8(65));
            verify_target_bytes(testCase, bundle, 8, uint8([0 1 2]), uint8([0 1 3]));
        end

        function testDifferentAtoDifferentBUsesRawTargetOctets(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            path = bundle.candidates(8).target_path;
            write_bytes(path, uint8('different A'));
            snapshot = create_snapshot(bundle);
            testCase.verifyEqual(snapshot.comparison_baseline(8).target_state, 'different');

            write_bytes(path, uint8('different B'));
            [isValid, issues] = validate_snapshot(snapshot, bundle);

            testCase.verifyFalse(isValid);
            testCase.verifyEqual(current_comparison_state(bundle, 8), 'different');
            testCase.verifyTrue(any(strcmp({issues.code}, 'SNAPSHOT_TARGET_CHANGED')));
        end

        function testTimestampOnlyChangeRemainsValid(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            path = bundle.candidates(2).target_path;
            file = java.io.File(path);
            testCase.assumeTrue(file.setLastModified(file.lastModified() + 2000), ...
                'The platform did not permit a timestamp-only update.');

            [isValid, issues] = validate_snapshot(snapshot, bundle);

            testCase.verifyTrue(isValid);
            testCase.verifyFalse(has_errors(issues));
        end

        function testDependencyInputModelRejectsInvalidValues(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 1, 'role', 'guess'));
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 1, 'identity', ''));
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 2, 'identity', 'template'));
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 1, 'source_kind', 'guess'));
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 1, 'source_path', bundle.dependencies(2).source_path));
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 2, 'source_path', ''));
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 2, 'content_bytes', uint8(1)));
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 1, 'content_bytes', 1));
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 2, 'source_path', 'relative.c'));
            noncanonical = fullfile(testCase.WorkFolder, 'folder', '..', 'core.c');
            verify_bad_dependency(testCase, bundle, set_dependency(bundle.dependencies, 2, 'source_path', noncanonical));
            verify_bad_dependency(testCase, bundle, bundle.dependencies(2));
            verify_bad_dependency(testCase, bundle, bundle.dependencies(1));
        end

        function testDamagedSnapshotModelsReturnSnapshotInvalid(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);

            verify_snapshot_invalid(testCase, 7, bundle);
            missingField = rmfield(snapshot, 'target_states');
            verify_snapshot_invalid(testCase, missingField, bundle);
            wrongVersion = snapshot; wrongVersion.schema_version = uint16(2);
            verify_snapshot_invalid(testCase, wrongVersion, bundle);
            badInterface = snapshot; badInterface.interface_specs(1).interface_hash = 1;
            verify_snapshot_invalid(testCase, badInterface, bundle);
            badTarget = snapshot; badTarget.target_states(1).state = 'unknown';
            verify_snapshot_invalid(testCase, badTarget, bundle);
        end

        function testSelectedActionDoesNotInvalidateSnapshot(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            snapshot.comparison_baseline(8).selected_action = 'replace';

            [isValid, issues] = validate_snapshot(snapshot, bundle);

            testCase.verifyTrue(isValid);
            testCase.verifyFalse(has_errors(issues));
        end

        function testServicesDoNotWriteOrMutateInputs(testCase)
            bundle = preview_bundle(testCase.WorkFolder);
            projectBefore = bundle.project;
            candidatesBefore = bundle.candidates;
            dependenciesBefore = bundle.dependencies;
            treeBefore = filesystem_snapshot(testCase.WorkFolder);

            [snapshot, ~] = create_snapshot(bundle);
            snapshotBefore = snapshot;
            validate_snapshot(snapshot, bundle);
            treeAfter = filesystem_snapshot(testCase.WorkFolder);

            testCase.verifyEqual(bundle.project, projectBefore);
            testCase.verifyEqual(bundle.candidates, candidatesBefore);
            testCase.verifyEqual(bundle.dependencies, dependenciesBefore);
            testCase.verifyEqual(snapshot, snapshotBefore);
            testCase.verifyEqual(treeAfter, treeBefore);
            testCase.verifyFalse(isfile(bundle.candidates(1).target_path));
        end
    end
end

function bundle = preview_bundle(root)
copyPath = c2837x_block_normalize_absolute_path(fullfile(root, 'copy.c'));
referencePath = c2837x_block_normalize_absolute_path(fullfile(root, 'reference.c'));
corePath = c2837x_block_normalize_absolute_path(fullfile(root, 'core.c'));
write_bytes(copyPath, uint8(sprintf('int copy(void) { return 1; }\n')));
write_bytes(referencePath, uint8(sprintf('int reference(void) { return 2; }\r\n')));
write_bytes(corePath, uint8([10 20 30]));

project = valid_project(root, copyPath, referencePath);
[definitions, ~] = c2837x_block_stage1_candidate_fixture(root);
candidates = c2837x_block_build_candidate_files(definitions);
dependencies = [dependency('generator_template', 'template', 'memory', '', ...
    uint8([1 2 3])), dependency('core_source', 'CoreMain', 'file', corePath, ...
    zeros(1, 0, 'uint8'))];
bundle = struct('project', project, 'candidates', candidates, ...
    'dependencies', dependencies);
end

function project = valid_project(root, copyPath, referencePath)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.1.10';
project.common.network.gateway = '0.0.0.0';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
first = instance('Motor', 'motor', uint16(0), uint16(5000), ...
    'external_copy', copyPath, 'command', 'status');
second = instance('Plant', 'plant', uint16(1), uint16(5001), ...
    'external_reference', referencePath, 'setpoint', 'feedback');
project.instances = [first second];
end

function value = instance(displayName, internalName, socket, port, mode, path, inputName, outputName)
value = c2837x_block_create_default_instance();
value.display_name = displayName;
value.internal_name = internalName;
value.iodevice.settings.socket_number = socket;
value.iodevice.settings.tcp_port = port;
value.inputs = variable(inputName, 'int16', 1);
value.outputs = variable(outputName, 'uint16', 1);
value.algorithm.mode = mode;
value.algorithm.source_path = path;
end

function value = variable(name, type, dim)
value = struct('name', name, 'type', type, 'dim', dim);
end

function value = dependency(role, identity, sourceKind, sourcePath, bytes)
value = struct('role', role, 'identity', identity, ...
    'source_kind', sourceKind, 'source_path', sourcePath, ...
    'content_bytes', bytes);
end

function [snapshot, issues, summary] = create_snapshot(bundle)
[snapshot, issues, summary] = c2837x_block_create_preview_snapshot( ...
    bundle.project, bundle.candidates, bundle.dependencies);
end

function [isValid, issues, summary] = validate_snapshot(snapshot, bundle)
[isValid, issues, summary] = c2837x_block_validate_preview_snapshot( ...
    snapshot, bundle.project, bundle.candidates, bundle.dependencies);
end

function verify_project_change(testCase, snapshot, bundle, project, expectedCodes)
changed = bundle;
changed.project = project;
[isValid, issues] = validate_snapshot(snapshot, changed);
testCase.verifyFalse(isValid);
testCase.verifyTrue(all(ismember(expectedCodes, {issues.code})));
end

function verify_invalid_code(testCase, snapshot, bundle, code)
[isValid, issues] = validate_snapshot(snapshot, bundle);
testCase.verifyFalse(isValid);
testCase.verifyTrue(any(strcmp({issues.code}, code)));
end

function verify_bad_dependency(testCase, bundle, dependencies)
[snapshot, issues] = c2837x_block_create_preview_snapshot( ...
    bundle.project, bundle.candidates, dependencies);
testCase.verifyEqual(snapshot, struct());
testCase.verifyTrue(any(strcmp({issues.code}, 'SNAPSHOT_DEPENDENCIES_INVALID')));
end

function verify_snapshot_invalid(testCase, snapshot, bundle)
[isValid, issues] = validate_snapshot(snapshot, bundle);
testCase.verifyFalse(isValid);
testCase.verifyEqual({issues.code}, {'SNAPSHOT_INVALID'});
end

function verify_target_mutation(testCase, bundle, index, bytes, action)
snapshot = create_snapshot(bundle);
path = bundle.candidates(index).target_path;
switch action
    case 'write'
        write_bytes(path, bytes);
    case 'delete'
        delete(path);
    case 'directory'
        delete(path);
        mkdir(path);
end
[isValid, issues] = validate_snapshot(snapshot, bundle);
testCase.verifyFalse(isValid);
testCase.verifyTrue(any(ismember({issues.code}, ...
    {'SNAPSHOT_TARGET_CHANGED', 'CANDIDATE_TARGET_IS_DIRECTORY'})));
end

function verify_target_bytes(testCase, bundle, index, before, after)
path = bundle.candidates(index).target_path;
write_bytes(path, before);
snapshot = create_snapshot(bundle);
write_bytes(path, after);
verify_invalid_code(testCase, snapshot, bundle, 'SNAPSHOT_TARGET_CHANGED');
end

function state = current_comparison_state(bundle, index)
comparisons = c2837x_block_compare_candidate_files(bundle.candidates);
state = comparisons(index).target_state;
end

function value = set_field(value, path, replacement)
tokens = regexp(path, '\.', 'split');
if strcmp(path, 'common.network.ip')
    value.common.network.ip = replacement;
elseif strcmp(path, 'instances(1).sample_time_sec')
    value.instances(1).sample_time_sec = replacement;
elseif strcmp(path, 'instances(1).display_name')
    value.instances(1).display_name = replacement;
elseif numel(tokens) == 2
    value.(tokens{1}).(tokens{2}) = replacement;
else
    value.instances(1).iodevice.settings.socket_number = replacement;
end
end

function bundle = isolated_bundle(root, name)
folder = fullfile(root, name);
mkdir(folder);
bundle = preview_bundle(folder);
end

function values = set_dependency(values, index, field, replacement)
values(index).(field) = replacement;
end

function summary = expected_summary(bundle, snapshot)
summary = empty_summary();
summary.instance_count = 2;
summary.candidate_count = 8;
summary.dependency_count = 2;
summary.external_source_count = 2;
summary.target_file_count = 6;
summary.missing_target_count = 2;
summary.create_count = 2;
summary.skip_count = 3;
summary.replace_count = 2;
summary.keep_count = 1;
summary.dsp_root = bundle.project.output.dsp_root;
summary.sfun_root = bundle.project.output.sfun_root;
summary.interface_hashes = [snapshot.interface_specs.interface_hash];
end

function summary = empty_summary()
summary = struct('instance_count', 0, 'candidate_count', 0, ...
    'dependency_count', 0, 'external_source_count', 0, ...
    'target_file_count', 0, 'missing_target_count', 0, ...
    'create_count', 0, 'skip_count', 0, 'replace_count', 0, ...
    'keep_count', 0, 'dsp_root', '', 'sfun_root', '', ...
    'interface_hashes', zeros(1, 0, 'uint32'));
end

function tf = has_errors(issues)
tf = any(strcmp({issues.severity}, 'Error'));
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

function make_unreadable(testCase, path)
testCase.addTeardown(@() system(sprintf('chmod u+r "%s"', path)));
[status, ~] = system(sprintf('chmod u-r "%s"', path));
testCase.assumeEqual(status, 0, 'Unable to remove read permission.');
fileID = fopen(path, 'rb');
testCase.assumeLessThan(fileID, 0, ...
    'Current account can still read a permission-restricted file.');
end

function snapshot = filesystem_snapshot(root)
entries = dir(fullfile(root, '**', '*'));
entries = entries(~[entries.isdir]);
[~, order] = sort(strcat({entries.folder}, filesep, {entries.name}));
entries = entries(order);
snapshot = struct('name', {entries.name}, 'folder', {entries.folder}, ...
    'bytes', {entries.bytes}, 'datenum', {entries.datenum}, ...
    'content', cell(1, numel(entries)));
for index = 1:numel(entries)
    snapshot(index).content = read_bytes(fullfile(entries(index).folder, entries(index).name));
end
end
