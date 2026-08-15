classdef test_sci_s3_04_preview_transaction < matlab.unittest.TestCase
    properties (TestParameter)
        generationMode = struct( ...
            'w5300', 'w5300', ...
            'sci', 'sci', ...
            'mixed', 'mixed')
    end

    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
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
        function testStage3GenerationAndSnapshotDeterminism(testCase, ...
                generationMode)
            project = make_project(testCase.WorkFolder, generationMode);

            [firstCandidates, firstDependencies, firstIssues] = ...
                c2837x_block_build_dsp_candidates(project);
            [secondCandidates, secondDependencies, secondIssues] = ...
                c2837x_block_build_dsp_candidates(project);
            [firstSnapshot, firstSnapshotIssues, firstSummary] = ...
                c2837x_block_create_preview_snapshot( ...
                project, firstCandidates, firstDependencies);
            [secondSnapshot, secondSnapshotIssues, secondSummary] = ...
                c2837x_block_create_preview_snapshot( ...
                project, secondCandidates, secondDependencies);

            testCase.verifyEmpty(firstIssues);
            testCase.verifyEmpty(secondIssues);
            testCase.verifyFalse(has_errors(firstSnapshotIssues));
            testCase.verifyFalse(has_errors(secondSnapshotIssues));
            testCase.verifyEqual(firstCandidates, secondCandidates);
            testCase.verifyEqual(firstDependencies, secondDependencies);
            testCase.verifyEqual(firstSnapshot, secondSnapshot);
            testCase.verifyEqual(firstSummary, secondSummary);
            verify_transport_shape(testCase, generationMode, ...
                firstCandidates, firstDependencies);
        end

        function testSciHardwareChangeInvalidatesSnapshotAndCommit(testCase)
            project = make_project(testCase.WorkFolder, 'sci');
            [candidates, dependencies, buildIssues] = ...
                c2837x_block_build_dsp_candidates(project);
            [snapshot, snapshotIssues] = ...
                c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);

            changedProject = project;
            changedProject.instances(1).iodevice.settings.baud = uint32(57600);
            [changedCandidates, changedDependencies, changedBuildIssues] = ...
                c2837x_block_build_dsp_candidates(changedProject);
            [isValid, validationIssues] = ...
                c2837x_block_validate_preview_snapshot( ...
                snapshot, changedProject, changedCandidates, changedDependencies);
            [result, commitIssues] = c2837x_block_commit_preview_snapshot( ...
                snapshot, changedProject, changedCandidates, changedDependencies);

            testCase.verifyEmpty(buildIssues);
            testCase.verifyFalse(has_errors(snapshotIssues));
            testCase.verifyEmpty(changedBuildIssues);
            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({validationIssues.code}, ...
                'SNAPSHOT_PROJECT_CHANGED')));
            testCase.verifyTrue(any(strcmp({validationIssues.code}, ...
                'SNAPSHOT_CANDIDATE_CHANGED')));
            testCase.verifyFalse(result.success);
            testCase.verifyEqual(result.status, 'blocked');
            testCase.verifyTrue(any(strcmp({commitIssues.code}, ...
                'SNAPSHOT_PROJECT_CHANGED')));
            testCase.verifyFalse(any(cellfun(@isfile, ...
                {candidates.target_path})));
        end

        function testResourceConflictIsRejectedBeforeAnyWrite(testCase)
            project = make_project(testCase.WorkFolder, 'sci');
            second = project.instances(1);
            second.display_name = 'Serial Two';
            second.internal_name = 'serial_two';
            project.instances(2) = second;
            [candidates, dependencies, buildIssues] = ...
                c2837x_block_build_dsp_candidates(project);
            before = filesystem_state(testCase.WorkFolder);

            [snapshot, previewIssues] = ...
                c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);
            [result, commitIssues] = c2837x_block_commit_preview_snapshot( ...
                snapshot, project, candidates, dependencies);
            after = filesystem_state(testCase.WorkFolder);

            testCase.verifyEmpty(buildIssues);
            testCase.verifyEmpty(fieldnames(snapshot));
            testCase.verifyTrue(any(strcmp({previewIssues.code}, ...
                'SCI_MODULE_DUPLICATE')));
            testCase.verifyFalse(result.success);
            testCase.verifyEqual(result.status, 'blocked');
            testCase.verifyTrue(any(strcmp({commitIssues.code}, ...
                'SNAPSHOT_INVALID')));
            testCase.verifyEqual(after, before);
            testCase.verifyFalse(any(cellfun(@isfile, ...
                {candidates.target_path})));
        end

        function testSciPreviewSnapshotDoesNotWriteTargets(testCase)
            project = make_project(testCase.WorkFolder, 'sci');
            [candidates, dependencies, buildIssues] = ...
                c2837x_block_build_dsp_candidates(project);
            before = filesystem_state(testCase.WorkFolder);

            [snapshot, previewIssues] = ...
                c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);
            after = filesystem_state(testCase.WorkFolder);

            testCase.verifyEmpty(buildIssues);
            testCase.verifyFalse(has_errors(previewIssues));
            testCase.verifyFalse(isempty(fieldnames(snapshot)));
            testCase.verifyEqual(after, before);
            testCase.verifyFalse(isfolder(project.output.dsp_root));
            testCase.verifyFalse(isfolder(project.output.sfun_root));
            testCase.verifyFalse(any(cellfun(@isfile, ...
                {candidates.target_path})));
        end

        function testSciCandidatesUseKeepReplaceCommitTransaction(testCase)
            project = make_project(testCase.WorkFolder, 'sci');
            [candidates, dependencies, buildIssues] = ...
                c2837x_block_build_dsp_candidates(project);
            keepIndex = find(strcmp({candidates.category}, 'user') & ...
                endsWith({candidates.target_path}, 'serial_user_config.h'), 1);
            replaceIndex = find(strcmp({candidates.category}, 'user') & ...
                endsWith({candidates.target_path}, 'serial_algorithm.c'), 1);
            generatedIndex = find( ...
                strcmp({candidates.category}, 'auto_generated') & ...
                endsWith({candidates.target_path}, 'serial_config.h'), 1);
            testCase.assertNotEmpty([keepIndex replaceIndex generatedIndex]);
            keepBytes = uint8('keep this user file');
            replaceBytes = uint8('replace this user file');
            generatedBytes = uint8('replace this generated file');
            write_bytes(candidates(keepIndex).target_path, keepBytes);
            write_bytes(candidates(replaceIndex).target_path, replaceBytes);
            write_bytes(candidates(generatedIndex).target_path, generatedBytes);

            [snapshot, snapshotIssues] = ...
                c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);
            snapshot.comparison_baseline(replaceIndex).selected_action = ...
                'replace';
            [result, commitIssues] = c2837x_block_commit_preview_snapshot( ...
                snapshot, project, candidates, dependencies);

            testCase.verifyEmpty(buildIssues);
            testCase.verifyFalse(has_errors(snapshotIssues));
            testCase.verifyEqual( ...
                snapshot.comparison_baseline(keepIndex).default_action, 'keep');
            testCase.verifyEqual( ...
                snapshot.comparison_baseline(replaceIndex).default_action, 'keep');
            testCase.verifyEqual( ...
                snapshot.comparison_baseline(generatedIndex).default_action, ...
                'replace');
            testCase.verifyTrue(result.success);
            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyFalse(has_errors(commitIssues));
            testCase.verifyEqual(result.files(keepIndex).outcome, 'kept');
            testCase.verifyEqual(result.files(replaceIndex).outcome, 'replaced');
            testCase.verifyEqual(result.files(generatedIndex).outcome, 'replaced');
            testCase.verifyEqual(read_bytes(candidates(keepIndex).target_path), ...
                keepBytes);
            testCase.verifyEqual(read_bytes(candidates(replaceIndex).target_path), ...
                candidates(replaceIndex).content_bytes);
            testCase.verifyEqual(read_bytes(candidates(generatedIndex).target_path), ...
                candidates(generatedIndex).content_bytes);
        end

        function testSciHardwareDoesNotEnterInterfaceHash(testCase)
            project = make_project(testCase.WorkFolder, 'sci');
            [firstText, firstHash] = ...
                c2837x_block_build_interface_hash(project, 1);
            project.instances(1).iodevice.settings.baud = uint32(57600);
            [secondText, secondHash] = ...
                c2837x_block_build_interface_hash(project, 1);

            testCase.verifyEqual(secondText, firstText);
            testCase.verifyEqual(secondHash, firstHash);
            testCase.verifyClass(secondHash, 'uint32');
        end
    end
end

function project = make_project(root, mode)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, [mode '_dsp']));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, [mode '_sfun']));

base = c2837x_block_create_default_instance();
base.inputs = struct('name', 'command', 'type', 'single', 'dim', 1);
base.outputs = struct('name', 'feedback', 'type', 'single', 'dim', 1);

w5300 = base;
w5300.display_name = 'Network';
w5300.internal_name = 'network';

sci = base;
sci.display_name = 'Serial';
sci.internal_name = 'serial';
sci.iodevice = c2837x_block_create_iodevice('sci');
sci.iodevice.settings.module = 'SCI-B';
sci.iodevice.settings.baud = uint32(115200);
sci.iodevice.settings.rx_gpio = 'GPIO19';
sci.iodevice.settings.tx_gpio = 'GPIO14';
sci.iodevice.settings.rx_pin_type = 'Standard';
sci.iodevice.settings.rx_qualification = 'Sync';
sci.iodevice.settings.tx_pin_type = 'Pull-up';
sci.iodevice.settings.ctrl_gpio = 'None';
sci.iodevice.settings.ctrl_pin_type = 'Standard';
sci.iodevice.settings.ctrl_tx_active_level = 'Low';

switch mode
    case 'w5300'
        project.instances = w5300;
    case 'sci'
        project.instances = sci;
    case 'mixed'
        project.instances = [w5300 sci];
    otherwise
        error('test_sci_s3_04_preview_transaction:InvalidMode', ...
            'Unknown project mode.');
end
end

function verify_transport_shape(testCase, mode, candidates, dependencies)
candidatePaths = cellfun(@lower, {candidates.target_path}, ...
    'UniformOutput', false);
dependencyText = lower(strjoin({dependencies.identity}, '|'));
hasSci = any(contains(candidatePaths, 'c2837x_block_sci')) || ...
    contains(dependencyText, 'sci');
hasW5300 = any(contains(candidatePaths, 'w5300')) || ...
    contains(dependencyText, 'w5300');

switch mode
    case 'w5300'
        testCase.verifyTrue(hasW5300);
        testCase.verifyFalse(hasSci);
    case 'sci'
        testCase.verifyTrue(hasSci);
        testCase.verifyFalse(hasW5300);
        configText = candidate_text(testCase, candidates, 'serial_config.c');
        ioText = candidate_text(testCase, candidates, 'serial_io.c');
        testCase.verifyTrue(contains(configText, ...
            'c2837x_block_serial_sci_descriptor'));
        testCase.verifyTrue(contains(configText, 'C2837X_BLOCK_SCI_MODULE_B'));
        testCase.verifyTrue(contains(ioText, ...
            'C2837X_BLOCK_SCI_CHANNEL_INITIALIZER'));
    case 'mixed'
        testCase.verifyTrue(hasW5300);
        testCase.verifyTrue(hasSci);
end
end

function text = candidate_text(testCase, candidates, suffix)
index = find(endsWith({candidates.target_path}, suffix), 1);
testCase.assertNotEmpty(index);
text = native2unicode(candidates(index).content_bytes, 'UTF-8');
end

function value = filesystem_state(root)
value = struct('path', {}, 'bytes', {});
entries = dir(fullfile(root, '**', '*'));
entries = entries(~[entries.isdir]);
for index = 1:numel(entries)
    path = fullfile(entries(index).folder, entries(index).name);
    value(end + 1) = struct('path', path, ...
        'bytes', read_bytes(path)); %#ok<AGROW>
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
