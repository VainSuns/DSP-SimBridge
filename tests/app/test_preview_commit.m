classdef test_preview_commit < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addCommitPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'app', 'fixtures')));
        end
    end

    methods (TestMethodSetup)
        function createWorkFolder(testCase)
            testCase.WorkFolder = ...
                c2837x_block_normalize_absolute_path(tempname);
            mkdir(testCase.WorkFolder);
            testCase.addTeardown(@() rmdir(testCase.WorkFolder, 's'));
            reset_writer();
            testCase.addTeardown(@reset_writer);
        end
    end

    methods (Test)
        function testDefaultActionsCommitInCandidateOrder(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            before = target_metadata(bundle.candidates);

            [result, issues] = commit_snapshot(snapshot, bundle);

            testCase.verifyTrue(result.success);
            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyEqual(result.phase, 'complete');
            testCase.verifyEqual({result.files.outcome}, ...
                {'created', 'skipped', 'replaced', 'skipped', ...
                'replaced', 'created', 'skipped', 'kept'});
            testCase.verifyEqual([result.created_count result.replaced_count ...
                result.skipped_count result.kept_count result.failed_count ...
                result.not_attempted_count], [2 2 3 1 0 0]);
            testCase.verifyFalse(has_errors(issues));
            testCase.verifyEmpty(result.temporary_files_remaining);
            verify_committed_bytes(testCase, snapshot, result);
            verify_untouched(testCase, bundle.candidates, before, [2 4 7 8]);
        end

        function testUserDifferentCanReplace(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            snapshot.comparison_baseline(8).selected_action = 'replace';

            result = commit_snapshot(snapshot, bundle);

            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyEqual(result.replaced_count, 3);
            testCase.verifyEqual(result.kept_count, 0);
            testCase.verifyEqual(read_bytes(bundle.candidates(8).target_path), ...
                bundle.candidates(8).content_bytes);
        end

        function testMandatoryActionChangesBlockBeforeWriter(testCase)
            verify_action_blocked(testCase, testCase.WorkFolder, 3, 'keep', ...
                'CANDIDATE_REPLACE_REQUIRED');
            verify_action_blocked(testCase, testCase.WorkFolder, 5, 'keep', ...
                'CANDIDATE_REPLACE_REQUIRED');
            verify_action_blocked(testCase, testCase.WorkFolder, 1, 'skip', ...
                'CANDIDATE_CREATE_REQUIRED');
            verify_action_blocked(testCase, testCase.WorkFolder, 2, 'replace', ...
                'CANDIDATE_SKIP_REQUIRED');
            verify_action_blocked(testCase, testCase.WorkFolder, 8, 'create', ...
                'CANDIDATE_ACTION_INVALID');
        end

        function testProjectChangeBlocksBeforeWriter(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            bundle.project.common.network.ip = '192.168.1.99';

            verify_stale_block(testCase, snapshot, bundle, ...
                'SNAPSHOT_PROJECT_CHANGED');
        end

        function testMemoryDependencyChangeBlocksBeforeWriter(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            bundle.dependencies(1).content_bytes = uint8([9 8 7]);

            verify_stale_block(testCase, snapshot, bundle, ...
                'SNAPSHOT_DEPENDENCY_CHANGED');
        end

        function testFileDependencyChangeBlocksBeforeWriter(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            write_bytes(bundle.dependencies(2).source_path, uint8([8 9]));

            verify_stale_block(testCase, snapshot, bundle, ...
                'SNAPSHOT_DEPENDENCY_CHANGED');
        end

        function testExternalSourceChangeBlocksBeforeWriter(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            write_bytes(bundle.project.instances(1).algorithm.source_path, ...
                uint8([0 255 0]));

            verify_stale_block(testCase, snapshot, bundle, ...
                'SNAPSHOT_EXTERNAL_SOURCE_CHANGED');
        end

        function testCandidateChangeBlocksBeforeWriter(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            bundle.candidates(1).content_bytes = uint8([1 2 3]);
            bundle.candidates(1).content_size_octets = 3;

            verify_stale_block(testCase, snapshot, bundle, ...
                'SNAPSHOT_CANDIDATE_CHANGED');
        end

        function testMissingTargetCreatedExternallyIsNotOverwritten(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            external = uint8([90 91 92]);
            write_bytes(bundle.candidates(1).target_path, external);

            [result, issues] = commit_snapshot(snapshot, bundle);

            testCase.verifyEqual(result.status, 'blocked');
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'COMMIT_TARGET_CHANGED')));
            testCase.verifyEqual(read_bytes(bundle.candidates(1).target_path), ...
                external);
        end

        function testExistingTargetChangedExternallyIsNotOverwritten(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            external = uint8([11 0 255]);
            write_bytes(bundle.candidates(3).target_path, external);

            [result, issues] = commit_snapshot(snapshot, bundle);

            testCase.verifyEqual(result.status, 'blocked');
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'COMMIT_TARGET_CHANGED')));
            testCase.verifyEqual(read_bytes(bundle.candidates(3).target_path), ...
                external);
        end

        function testTargetChangedToDirectoryIsNotRemoved(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            path = bundle.candidates(3).target_path;
            delete(path);
            mkdir(path);

            [result, issues] = commit_snapshot(snapshot, bundle);

            testCase.verifyEqual(result.status, 'blocked');
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'COMMIT_TARGET_CHANGED')));
            testCase.verifyTrue(isfolder(path));
        end

        function testWriterPreservesArbitraryOctetsForCreateAndReplace(testCase)
            verify_octet_cases(testCase, testCase.WorkFolder);
        end

        function testNestedParentDirectoryIsCreatedAndReported(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            nested = c2837x_block_normalize_absolute_path(fullfile( ...
                testCase.WorkFolder, 'new', 'nested', 'target.bin'));
            bundle.candidates(1).target_path = nested;
            snapshot = create_snapshot(bundle);

            result = commit_snapshot(snapshot, bundle);

            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyTrue(isfile(nested));
            testCase.verifyTrue(any(strcmp(result.created_directories, ...
                fileparts(nested))));
        end

        function testDirectoryFailureAfterCreationIsPartial(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            firstParent = c2837x_block_normalize_absolute_path(fullfile( ...
                testCase.WorkFolder, 'first_parent'));
            blockedParent = c2837x_block_normalize_absolute_path(fullfile( ...
                testCase.WorkFolder, 'blocked_parent'));
            bundle.candidates(1).target_path = c2837x_block_normalize_absolute_path( ...
                fullfile(firstParent, 'first.bin'));
            bundle.candidates(6).target_path = c2837x_block_normalize_absolute_path( ...
                fullfile(blockedParent, 'second.bin'));
            snapshot = create_snapshot(bundle);
            write_bytes(blockedParent, uint8(1));

            [result, issues] = commit_snapshot(snapshot, bundle);

            testCase.verifyEqual(result.status, 'partial_failure');
            testCase.verifyEqual(result.phase, 'directory_creation');
            testCase.verifyTrue(isfolder(firstParent));
            testCase.verifyTrue(any(strcmp(result.created_directories, firstParent)));
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'COMMIT_DIRECTORY_CREATE_FAILED')));
            testCase.verifyTrue(all(strcmp({result.files.outcome}, ...
                'not_attempted')));
        end

        function testSkipAndKeepNeverCallWriterOrChangeTimestamp(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            before = target_metadata(bundle.candidates);
            configure_writer('real');
            options = struct('file_writer', @injected_writer);

            result = c2837x_block_commit_preview_snapshot(snapshot, ...
                bundle.project, bundle.candidates, bundle.dependencies, options);

            testCase.verifyEqual(writer_count(), 4);
            testCase.verifyEqual(result.skipped_count, 3);
            testCase.verifyEqual(result.kept_count, 1);
            verify_untouched(testCase, bundle.candidates, before, [2 4 7 8]);
        end

        function testWriterUsesSameDirectoryAndRemovesTemporaryFile(testCase)
            parent = c2837x_block_normalize_absolute_path(fullfile( ...
                testCase.WorkFolder, 'writer'));
            mkdir(parent);
            target = c2837x_block_normalize_absolute_path(fullfile(parent, 'new.bin'));
            before = dir(parent);

            result = c2837x_block_commit_file_bytes(target, uint8([0 255]), ...
                'create', missing_state(target));

            after = dir(parent);
            testCase.verifyTrue(result.success);
            testCase.verifyEqual(read_bytes(target), uint8([0 255]));
            testCase.verifyEmpty(result.temporary_path);
            testCase.verifyEqual({after.name}, [before.name {'new.bin'}]);
        end

        function testCreateRejectsExistingTarget(testCase)
            target = c2837x_block_normalize_absolute_path(fullfile( ...
                testCase.WorkFolder, 'existing.bin'));
            expected = missing_state(target);
            external = uint8([7 8 9]);
            write_bytes(target, external);

            result = c2837x_block_commit_file_bytes(target, uint8(1), ...
                'create', expected);

            testCase.verifyFalse(result.success);
            testCase.verifyEqual(result.code, 'COMMIT_TARGET_CHANGED');
            testCase.verifyEqual(read_bytes(target), external);
        end

        function testReplaceRejectsChangedTarget(testCase)
            target = c2837x_block_normalize_absolute_path(fullfile( ...
                testCase.WorkFolder, 'changed.bin'));
            original = uint8([1 2 3]);
            write_bytes(target, original);
            expected = file_state(target, original);
            external = uint8([4 5 6]);
            write_bytes(target, external);

            result = c2837x_block_commit_file_bytes(target, uint8(9), ...
                'replace', expected);

            testCase.verifyFalse(result.success);
            testCase.verifyEqual(result.code, 'COMMIT_TARGET_CHANGED');
            testCase.verifyEqual(read_bytes(target), external);
        end

        function testSecondWriterFailureReturnsPartialFailure(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            configure_writer('second_fail');
            options = struct('file_writer', @injected_writer);

            [result, issues] = c2837x_block_commit_preview_snapshot(snapshot, ...
                bundle.project, bundle.candidates, bundle.dependencies, options);

            testCase.verifyEqual(result.status, 'partial_failure');
            testCase.verifyEqual(writer_count(), 2);
            testCase.verifyEqual(result.files(1).outcome, 'created');
            testCase.verifyEqual(result.files(3).outcome, 'failed');
            testCase.verifyTrue(all(strcmp({result.files(4:end).outcome}, ...
                'not_attempted')));
            testCase.verifyEqual(read_bytes(bundle.candidates(1).target_path), ...
                bundle.candidates(1).content_bytes);
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'TEST_INJECTED_WRITE_FAILED')));
        end

        function testFirstWriterFailureHasNoSideEffects(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            before = filesystem_snapshot(testCase.WorkFolder);
            configure_writer('fail');
            options = struct('file_writer', @injected_writer);

            result = c2837x_block_commit_preview_snapshot(snapshot, ...
                bundle.project, bundle.candidates, bundle.dependencies, options);

            testCase.verifyEqual(result.status, 'failed');
            testCase.verifyEqual(writer_count(), 1);
            testCase.verifyEqual(result.files(1).outcome, 'failed');
            testCase.verifyTrue(all(strcmp({result.files(2:end).outcome}, ...
                'not_attempted')));
            testCase.verifyEqual(filesystem_snapshot(testCase.WorkFolder), before);
        end

        function testWriterExceptionBecomesStableIssue(testCase)
            verify_writer_failure(testCase, testCase.WorkFolder, 'throw', ...
                'COMMIT_FILE_WRITER_FAILED');
        end

        function testMalformedWriterResultBecomesStableIssue(testCase)
            verify_writer_failure(testCase, testCase.WorkFolder, 'malformed', ...
                'COMMIT_FILE_WRITER_RESULT_INVALID');
        end

        function testWriterSuccessClaimIsIndependentlyVerified(testCase)
            verify_writer_failure(testCase, testCase.WorkFolder, 'lie', ...
                'COMMIT_POST_WRITE_VERIFY_FAILED');
        end

        function testSecondPreviewMakesCommittedFilesSkip(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            firstSnapshot = create_snapshot(bundle);
            first = commit_snapshot(firstSnapshot, bundle);
            secondSnapshot = create_snapshot(bundle);
            before = target_metadata(bundle.candidates);

            second = commit_snapshot(secondSnapshot, bundle);

            testCase.verifyEqual(first.status, 'completed');
            testCase.verifyEqual(second.status, 'completed');
            testCase.verifyEqual(second.skipped_count, 7);
            testCase.verifyEqual(second.kept_count, 1);
            testCase.verifyEqual( ...
                [secondSnapshot.interface_specs.interface_hash], ...
                [firstSnapshot.interface_specs.interface_hash]);
            verify_untouched(testCase, bundle.candidates, before, 1:8);
        end

        function testInputsRemainUnchangedAndNoPersistentArtifactsAppear(testCase)
            bundle = commit_bundle(testCase.WorkFolder);
            snapshot = create_snapshot(bundle);
            originalBundle = bundle;
            originalSnapshot = snapshot;

            result = commit_snapshot(snapshot, bundle);

            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyEqual(bundle, originalBundle);
            testCase.verifyEqual(snapshot, originalSnapshot);
            testCase.verifyEmpty(dir(fullfile(testCase.WorkFolder, '**', '*.mat')));
            testCase.verifyEmpty(dir(fullfile(testCase.WorkFolder, '**', ...
                '*manifest*')));
        end

        function testInvalidWriterInputsReturnFixedFailure(testCase)
            result = c2837x_block_commit_file_bytes('relative.bin', ...
                uint8(1), 'create', struct());

            testCase.verifyEqual(result, struct('success', false, ...
                'code', 'COMMIT_WRITE_INPUT_INVALID', ...
                'message', 'Commit writer inputs do not use the fixed model.', ...
                'temporary_path', ''));
        end
    end
end

function bundle = commit_bundle(root)
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
    uint8([1 2 3])), dependency('core_source', 'CoreMain', 'file', ...
    corePath, zeros(1, 0, 'uint8'))];
bundle = struct('project', project, 'candidates', candidates, ...
    'dependencies', dependencies);
end

function project = valid_project(root, copyPath, referencePath)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.1.10';
project.common.network.gateway = '0.0.0.0';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));
project.instances = [instance('Motor', 'motor', uint16(0), uint16(5000), ...
    'external_copy', copyPath, 'command', 'status'), ...
    instance('Plant', 'plant', uint16(1), uint16(5001), ...
    'external_reference', referencePath, 'setpoint', 'feedback')];
end

function value = instance(displayName, internalName, socket, port, ...
        mode, path, inputName, outputName)
value = c2837x_block_create_default_instance();
value.display_name = displayName;
value.internal_name = internalName;
value.iodevice.settings.socket_number = socket;
value.iodevice.settings.tcp_port = port;
value.inputs = struct('name', inputName, 'type', 'int16', 'dim', 1);
value.outputs = struct('name', outputName, 'type', 'uint16', 'dim', 1);
value.algorithm.mode = mode;
value.algorithm.source_path = path;
end

function value = dependency(role, identity, sourceKind, sourcePath, bytes)
value = struct('role', role, 'identity', identity, ...
    'source_kind', sourceKind, 'source_path', sourcePath, ...
    'content_bytes', bytes);
end

function snapshot = create_snapshot(bundle)
[snapshot, issues] = c2837x_block_create_preview_snapshot( ...
    bundle.project, bundle.candidates, bundle.dependencies);
assert(~any(strcmp({issues.severity}, 'Error')), ...
    'Test setup could not create a valid preview snapshot.');
end

function [result, issues] = commit_snapshot(snapshot, bundle)
[result, issues] = c2837x_block_commit_preview_snapshot(snapshot, ...
    bundle.project, bundle.candidates, bundle.dependencies);
end

function verify_action_blocked(testCase, root, index, action, expectedCode)
bundle = commit_bundle(fullfile(root, sprintf('action_%u', index)));
snapshot = create_snapshot(bundle);
snapshot.comparison_baseline(index).selected_action = action;
before = filesystem_snapshot(fileparts(bundle.project.output.dsp_root));
configure_writer('fail');
options = struct('file_writer', @injected_writer);
[result, issues] = c2837x_block_commit_preview_snapshot(snapshot, ...
    bundle.project, bundle.candidates, bundle.dependencies, options);
testCase.verifyEqual(result.status, 'blocked');
testCase.verifyTrue(any(strcmp({issues.code}, expectedCode)));
testCase.verifyEqual(writer_count(), 0);
testCase.verifyEqual(filesystem_snapshot( ...
    fileparts(bundle.project.output.dsp_root)), before);
end

function verify_stale_block(testCase, snapshot, bundle, expectedCode)
before = filesystem_snapshot(fileparts(bundle.project.output.dsp_root));
configure_writer('fail');
options = struct('file_writer', @injected_writer);
[result, issues] = c2837x_block_commit_preview_snapshot(snapshot, ...
    bundle.project, bundle.candidates, bundle.dependencies, options);
testCase.verifyEqual(result.status, 'blocked');
testCase.verifyTrue(any(strcmp({issues.code}, expectedCode)));
testCase.verifyEqual(writer_count(), 0);
testCase.verifyEqual(filesystem_snapshot( ...
    fileparts(bundle.project.output.dsp_root)), before);
end

function verify_octet_cases(testCase, root)
cases = {zeros(1, 0, 'uint8'), uint8([0 255]), uint8([239 187 191 65]), ...
    uint8([65 10 66 10]), uint8([65 13 10 66 13 10]), ...
    uint8([65 10]), uint8(65)};
for index = 1:numel(cases)
    target = c2837x_block_normalize_absolute_path(fullfile( ...
        root, sprintf('octets_%u.bin', index)));
    createResult = c2837x_block_commit_file_bytes(target, cases{index}, ...
        'create', missing_state(target));
    testCase.verifyTrue(createResult.success);
    testCase.verifyEqual(read_bytes(target), cases{index});
    original = cases{index};
    replacement = uint8([double(index) 0 255]);
    replaceResult = c2837x_block_commit_file_bytes(target, replacement, ...
        'replace', file_state(target, original));
    testCase.verifyTrue(replaceResult.success);
    testCase.verifyEqual(read_bytes(target), replacement);
end
end

function verify_committed_bytes(testCase, snapshot, result)
for index = 1:numel(result.files)
    if any(strcmp(result.files(index).outcome, {'created', 'replaced'}))
        testCase.verifyEqual(read_bytes(result.files(index).target_path), ...
            snapshot.candidates(index).content_bytes);
    end
end
end

function before = target_metadata(candidates)
before = repmat(struct('exists', false, 'bytes', zeros(1, 0, 'uint8'), ...
    'datenum', 0), 1, numel(candidates));
for index = 1:numel(candidates)
    path = candidates(index).target_path;
    before(index).exists = isfile(path);
    if before(index).exists
        info = dir(path);
        before(index).bytes = read_bytes(path);
        before(index).datenum = info.datenum;
    end
end
end

function verify_untouched(testCase, candidates, before, indices)
for index = indices
    info = dir(candidates(index).target_path);
    testCase.verifyTrue(before(index).exists);
    testCase.verifyEqual(read_bytes(candidates(index).target_path), ...
        before(index).bytes);
    testCase.verifyEqual(info.datenum, before(index).datenum);
end
end

function state = missing_state(target)
state = struct('target_path', target, 'state', 'missing', ...
    'content_bytes', zeros(1, 0, 'uint8'), 'content_size_octets', 0);
end

function state = file_state(target, bytes)
state = struct('target_path', target, 'state', 'file', ...
    'content_bytes', bytes, 'content_size_octets', double(numel(bytes)));
end

function verify_writer_failure(testCase, root, mode, expectedCode)
bundle = commit_bundle(root);
snapshot = create_snapshot(bundle);
configure_writer(mode);
options = struct('file_writer', @injected_writer);
[result, issues] = c2837x_block_commit_preview_snapshot(snapshot, ...
    bundle.project, bundle.candidates, bundle.dependencies, options);
testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.files(1).outcome, 'failed');
testCase.verifyEqual(result.files(1).code, expectedCode);
testCase.verifyTrue(any(strcmp({issues.code}, expectedCode)));
end

function result = injected_writer(targetPath, contentBytes, action, expected)
state = writer_state('increment');
switch state.mode
    case 'real'
        result = c2837x_block_commit_file_bytes( ...
            targetPath, contentBytes, action, expected);
    case 'second_fail'
        if state.count == 1
            result = c2837x_block_commit_file_bytes( ...
                targetPath, contentBytes, action, expected);
        else
            result = injected_failure();
        end
    case 'fail'
        result = injected_failure();
    case 'throw'
        error('Test:InjectedWriter', 'Injected writer exception.');
    case 'malformed'
        result = 7;
    otherwise
        result = struct('success', true, 'code', '', ...
            'message', '', 'temporary_path', '');
end
end

function result = injected_failure()
result = struct('success', false, 'code', 'TEST_INJECTED_WRITE_FAILED', ...
    'message', 'Injected write failure.', 'temporary_path', '');
end

function configure_writer(mode)
writer_state('set', mode);
end

function count = writer_count()
state = writer_state('get');
count = state.count;
end

function reset_writer()
writer_state('reset');
end

function state = writer_state(action, value)
persistent stored
if isempty(stored)
    stored = struct('mode', '', 'count', 0);
end
switch action
    case 'set'
        stored = struct('mode', value, 'count', 0);
    case 'increment'
        stored.count = stored.count + 1;
    case 'reset'
        stored = struct('mode', '', 'count', 0);
end
state = stored;
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
    snapshot(index).content = read_bytes( ...
        fullfile(entries(index).folder, entries(index).name));
end
end

function write_bytes(path, bytes)
parent = fileparts(path);
if ~isfolder(parent)
    mkdir(parent);
end
fileID = fopen(path, 'wb');
assert(fileID >= 0, 'Test file could not be opened.');
cleanup = onCleanup(@() fclose(fileID));
written = fwrite(fileID, bytes, 'uint8');
assert(written == numel(bytes), 'Test file could not be written.');
clear cleanup
end

function bytes = read_bytes(path)
fileID = fopen(path, 'rb');
assert(fileID >= 0, 'Test file could not be read.');
cleanup = onCleanup(@() fclose(fileID));
bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
clear cleanup
end

function tf = has_errors(issues)
tf = any(strcmp({issues.severity}, 'Error'));
end
