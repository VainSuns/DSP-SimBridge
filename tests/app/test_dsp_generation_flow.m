classdef test_dsp_generation_flow < matlab.unittest.TestCase
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
        function makeFolder(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.WorkFolder = fixture.Folder;
            configure_writer(0);
        end
    end

    methods (Test)
        function testOfficialPreviewAndGenerateAreDeterministic(testCase)
            project = flow_project(testCase.WorkFolder);
            session = c2837x_block_project_session(project);
            session.updateProject(project);
            coordinator = c2837x_block_app_coordinator(session, ...
                @c2837x_block_build_dsp_candidates);
            original = session_state(session);
            before = filesystem_files(testCase.WorkFolder);

            [firstView, previewIssues] = coordinator.createPreview();
            afterPreview = filesystem_files(testCase.WorkFolder);
            [result, commitIssues] = coordinator.commitPreview();
            [secondView, secondIssues] = coordinator.createPreview();
            second = coordinator.commitPreview();

            testCase.verifyEqual(firstView.status, 'valid');
            testCase.verifyFalse(has_errors(previewIssues));
            testCase.verifyEqual(numel(firstView.comparisons), 30);
            testCase.verifyEqual(afterPreview, before);
            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyEqual(result.phase, 'complete');
            testCase.verifyEqual(result.created_count, 30);
            testCase.verifyFalse(has_errors(commitIssues));
            testCase.verifyEqual(read_bytes(fullfile(project.output.dsp_root, ...
                'src', 'motor_algorithm.c')), read_bytes(project.instances(1).algorithm.source_path));
            testCase.verifyFalse(isfile(fullfile(project.output.dsp_root, ...
                'src', 'plant_algorithm.c')));
            testCase.verifyFalse(isfolder(project.output.sfun_root));
            testCase.verifyFalse(any(strcmp({secondIssues.severity}, 'Error')));
            testCase.verifyEqual({secondView.comparisons.target_state}, ...
                repmat({'same'}, 1, 30));
            testCase.verifyEqual(second.skipped_count, 30);
            testCase.verifyEqual(second.status, 'completed');
            testCase.verifyEqual(session_state(session), original);
        end

        function testActionMatrixAndUserReplace(testCase)
            project = flow_project(testCase.WorkFolder);
            [candidates, dependencies] = c2837x_block_build_dsp_candidates(project);
            write_selected_targets(candidates);
            [snapshot, issues] = c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);
            userIndex = find(strcmp({snapshot.comparison_baseline.category}, ...
                'user') & strcmp({snapshot.comparison_baseline.target_state}, ...
                'different'), 1);
            mandatoryIndex = find(strcmp({snapshot.comparison_baseline.category}, ...
                'core') & strcmp({snapshot.comparison_baseline.target_state}, ...
                'different'), 1);
            invalid = snapshot;
            invalid.comparison_baseline(mandatoryIndex).selected_action = 'keep';
            [blocked, blockedIssues] = c2837x_block_commit_preview_snapshot( ...
                invalid, project, candidates, dependencies);
            snapshot.comparison_baseline(userIndex).selected_action = 'replace';

            [result, commitIssues] = c2837x_block_commit_preview_snapshot( ...
                snapshot, project, candidates, dependencies);

            testCase.verifyFalse(has_errors(issues));
            testCase.verifyEqual(snapshot.comparison_baseline(userIndex).default_action, ...
                'keep');
            testCase.verifyFalse(snapshot.comparison_baseline(userIndex).action_mandatory);
            testCase.verifyEqual(snapshot.comparison_baseline(mandatoryIndex).default_action, ...
                'replace');
            testCase.verifyEqual(blocked.status, 'blocked');
            testCase.verifyTrue(any(strcmp({blockedIssues.code}, ...
                'CANDIDATE_REPLACE_REQUIRED')));
            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyFalse(has_errors(commitIssues));
            testCase.verifyEqual(read_bytes(candidates(userIndex).target_path), ...
                candidates(userIndex).content_bytes);
        end

        function testOfficialSnapshotRejectsChanges(testCase)
            project = flow_project(testCase.WorkFolder);
            [candidates, dependencies] = c2837x_block_build_dsp_candidates(project);
            snapshot = c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);

            verify_official_invalidations(testCase, snapshot, project, ...
                candidates, dependencies);
        end

        function testPartialFailureAndFormatter(testCase)
            project = flow_project(testCase.WorkFolder);
            [candidates, dependencies] = c2837x_block_build_dsp_candidates(project);
            snapshot = c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);
            configure_writer(2);

            [result, issues] = c2837x_block_commit_preview_snapshot( ...
                snapshot, project, candidates, dependencies, ...
                struct('file_writer', @injected_writer));
            lines = c2837x_block_format_generation_result(result, project, ...
                legacy_risk());
            text = strjoin(lines, newline);

            testCase.verifyEqual(result.status, 'partial_failure');
            testCase.verifyEqual(result.phase, 'file_commit');
            testCase.verifyEqual(result.files(1).outcome, 'created');
            testCase.verifyEqual(result.files(2).outcome, 'failed');
            testCase.verifyTrue(all(strcmp({result.files(3:end).outcome}, ...
                'not_attempted')));
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'TEST_INJECTED_WRITE_FAILED')));
            testCase.verifyTrue(contains(text, '[CREATED]'));
            testCase.verifyTrue(contains(text, '[FAILED]'));
            testCase.verifyTrue(contains(text, '[NOT ATTEMPTED]'));
            testCase.verifyTrue(contains(text, 'External Reference:'));
            testCase.verifyTrue(contains(text, ...
                'Add the original .c source to the CCS project.'));
            testCase.verifyTrue(contains(text, ...
                'Old files are not automatically deleted'));
        end

        function testProjectReportUsesWireLayout(testCase)
            project = flow_project(testCase.WorkFolder);
            [report, issues] = c2837x_block_build_project_report(project);
            wire = c2837x_block_build_dsp_wire_layout(project);

            testCase.verifyEmpty(issues);
            testCase.verifyEqual(report.total_protocol_buffer_words, ...
                wire.project_protocol_buffer_words);
            testCase.verifyEqual([report.instances.protocol_buffer_words], ...
                [wire.instances.protocol_buffer_words]);
        end
    end
end

function project = flow_project(root)
copyPath = c2837x_block_normalize_absolute_path(fullfile(root, 'copy.c'));
referencePath = c2837x_block_normalize_absolute_path(fullfile(root, 'reference.c'));
write_bytes(copyPath, uint8([255 0 13 10 65]));
write_bytes(referencePath, uint8('int plant(void) { return 1; }'));
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.1.10';
project.common.network.gateway = '0.0.0.0';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));
project.instances = [flow_instance('Motor', 'motor', 0, 5000, ...
    'external_copy', copyPath), flow_instance('Plant', 'plant', 1, 5001, ...
    'external_reference', referencePath)];
end

function value = flow_instance(displayName, internalName, socket, port, mode, path)
value = c2837x_block_create_default_instance();
value.display_name = displayName;
value.internal_name = internalName;
value.iodevice.settings.socket_number = uint16(socket);
value.iodevice.settings.tcp_port = uint16(port);
value.inputs = struct('name', 'command', 'type', 'int16', 'dim', 1);
value.outputs = struct('name', 'status', 'type', 'uint16', 'dim', 1);
value.algorithm = struct('mode', mode, 'source_path', path);
end

function state = session_state(session)
state = struct('project', session.Project, 'file_path', session.FilePath, ...
    'dirty', session.Dirty);
end

function files = filesystem_files(root)
values = dir(fullfile(root, '**', '*'));
values = values(~[values.isdir]);
files = sort(fullfile({values.folder}, {values.name}));
end

function write_selected_targets(candidates)
indices = [find(strcmp({candidates.category}, 'core'), 1), ...
    find(strcmp({candidates.category}, 'auto_generated'), 1), ...
    find(strcmp({candidates.category}, 'user'), 1)];
for index = indices
    parent = fileparts(candidates(index).target_path);
    if ~isfolder(parent)
        mkdir(parent);
    end
    write_bytes(candidates(index).target_path, uint8('different'));
end
end

function verify_official_invalidations(testCase, snapshot, project, candidates, dependencies)
changedProject = project;
changedProject.common.abi = 'coffabi';
[~, projectIssues] = c2837x_block_commit_preview_snapshot(snapshot, ...
    changedProject, candidates, dependencies);
changedExternal = uint8('changed reference');
write_bytes(project.instances(2).algorithm.source_path, changedExternal);
[~, externalIssues] = c2837x_block_commit_preview_snapshot(snapshot, ...
    project, candidates, dependencies);
    write_bytes(project.instances(2).algorithm.source_path, ...
        snapshot.external_sources(2).content_bytes);
    mkdir(fileparts(candidates(1).target_path));
    write_bytes(candidates(1).target_path, uint8('external target'));
[~, targetIssues] = c2837x_block_commit_preview_snapshot(snapshot, ...
    project, candidates, dependencies);
testCase.verifyTrue(any(strcmp({projectIssues.code}, ...
    'SNAPSHOT_PROJECT_CHANGED')));
testCase.verifyTrue(any(strcmp({externalIssues.code}, ...
    'SNAPSHOT_EXTERNAL_SOURCE_CHANGED')));
testCase.verifyTrue(any(strcmp({targetIssues.code}, ...
    'SNAPSHOT_TARGET_CHANGED')));
end

function result = injected_writer(targetPath, bytes, action, expected)
state = writer_state();
state.count = state.count + 1;
writer_state(state);
if state.count == state.fail_at
    result = struct('success', false, 'code', 'TEST_INJECTED_WRITE_FAILED', ...
        'message', 'Injected write failure.', 'cleanup_code', '', ...
        'cleanup_message', '', 'temporary_path', '');
else
    result = c2837x_block_commit_file_bytes(targetPath, bytes, action, expected);
end
end

function configure_writer(failAt)
writer_state(struct('count', 0, 'fail_at', failAt));
end

function state = writer_state(value)
persistent stored
if nargin > 0
    stored = value;
end
if isempty(stored)
    stored = struct('count', 0, 'fail_at', 0);
end
state = stored;
end

function risk = legacy_risk()
risk = struct('action', 'rename', 'internal_name', 'old_motor', ...
    'reason', 'The instance was renamed.');
end

function write_bytes(path, bytes)
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
tf = any(strcmp({issues.severity}, 'Error'));
end
