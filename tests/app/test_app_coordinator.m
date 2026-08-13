classdef test_app_coordinator < matlab.unittest.TestCase
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
        end
    end

    methods (Test)
        function testUnavailableProvider(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            [view, issues] = coordinator.createPreview();
            testCase.verifyEqual(view.status, 'blocked');
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'APP_PREVIEW_PROVIDER_UNAVAILABLE')));
        end

        function testProviderFailureIsHidden(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, @throwing_provider);
            [~, issues] = coordinator.createPreview();
            testCase.verifyEqual(issues(end).code, 'APP_PREVIEW_PROVIDER_FAILED');
            testCase.verifyFalse(contains(issues(end).message, 'secret'));
        end

        function testInvalidProviderResult(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, @invalid_provider);
            [~, issues] = coordinator.createPreview();
            testCase.verifyEqual(issues(end).code, ...
                'APP_PREVIEW_PROVIDER_RESULT_INVALID');
        end

        function testInvalidDependencyResult(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, ...
                @invalid_dependency_provider);
            [~, issues] = coordinator.createPreview();
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'APP_PREVIEW_PROVIDER_RESULT_INVALID')));
        end

        function testInstantValidationForwarded(testCase)
            session = c2837x_block_project_session();
            coordinator = c2837x_block_app_coordinator(session, []);
            direct = c2837x_block_validate_project(session.Project, 'instant');
            testCase.verifyEqual(coordinator.validateProject('instant'), direct);
        end

        function testFullValidationForwarded(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            direct = c2837x_block_validate_project( ...
                coordinator.Session.Project, 'full');
            testCase.verifyEqual(coordinator.validateProject('full'), direct);
        end

        function testValidPreview(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, @valid_provider);
            [view, issues] = coordinator.createPreview();
            testCase.verifyFalse(has_errors(issues));
            testCase.verifyEqual(view.status, 'valid');
            testCase.verifyEqual(numel(view.comparisons), 1);
        end

        function testPreviewDoesNotWrite(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, @valid_provider);
            before = dir(fullfile(testCase.WorkFolder, '**', '*'));
            coordinator.createPreview();
            after = dir(fullfile(testCase.WorkFolder, '**', '*'));
            testCase.verifyEqual({after.name}, {before.name});
        end

        function testProjectEditMakesPreviewStale(testCase)
            coordinator = previewed(testCase.WorkFolder);
            project = coordinator.Session.Project;
            project.common.network.ip = '10.0.0.2';
            coordinator.updateProject(project);
            testCase.verifyEqual(coordinator.PreviewStatus, 'stale');
            testCase.verifyEmpty(fieldnames(coordinator.PreviewSnapshot));
        end

        function testInputOrderMakesPreviewStale(testCase)
            coordinator = previewed(testCase.WorkFolder);
            inputs = coordinator.Session.Project.instances(1).inputs([2 1]);
            coordinator.updateInstance(1, struct('inputs', inputs));
            testCase.verifyEqual(coordinator.PreviewStatus, 'stale');
        end

        function testIoDeviceSwitchMakesPreviewStale(testCase)
            coordinator = previewed(testCase.WorkFolder);

            coordinator.switchIoDevice(1, 'sci');

            testCase.verifyEqual(coordinator.PreviewStatus, 'stale');
            testCase.verifyEqual(coordinator.Session.Project.instances.iodevice, ...
                c2837x_block_create_iodevice('sci'));
        end

        function testAddMakesPreviewStale(testCase)
            coordinator = previewed(testCase.WorkFolder);
            coordinator.addInstance(instance_changes(2));
            testCase.verifyEqual(coordinator.PreviewStatus, 'stale');
        end

        function testCopyMakesPreviewStale(testCase)
            coordinator = previewed(testCase.WorkFolder);
            coordinator.copyInstance(1, 'Copy', 'copy', uint16(1), uint16(5001));
            testCase.verifyEqual(coordinator.PreviewStatus, 'stale');
            testCase.verifyEmpty(coordinator.Session.Project.instances(2).algorithm.source_path);
        end

        function testRenameCreatesRisk(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            coordinator.renameInstance(1, 'Renamed', 'renamed');
            testCase.verifyEqual(coordinator.Session.LegacyFileRisks.action, 'rename');
        end

        function testDeleteCreatesRisk(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            coordinator.deleteInstance(1);
            testCase.verifyEqual(coordinator.Session.LegacyFileRisks.action, 'delete');
        end

        function testUserKeepCanBecomeReplace(testCase)
            target = fullfile(testCase.WorkFolder, 'user.c');
            write_bytes(target, uint8('old'));
            coordinator = make_coordinator(testCase.WorkFolder, @valid_provider);
            coordinator.createPreview();
            dirty = coordinator.Session.Dirty;
            project = coordinator.Session.Project;
            issues = coordinator.setCandidateAction(1, 'replace');
            testCase.verifyFalse(has_errors(issues));
            testCase.verifyEqual(coordinator.Session.Project, project);
            testCase.verifyEqual(coordinator.Session.Dirty, dirty);
        end

        function testMandatoryActionRejected(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, @automatic_provider);
            coordinator.createPreview();
            original = coordinator.PreviewSnapshot;
            issues = coordinator.setCandidateAction(1, 'keep');
            testCase.verifyNotEmpty(issues);
            testCase.verifyEqual(coordinator.PreviewSnapshot, original);
        end

        function testCommitSucceeds(testCase)
            coordinator = previewed(testCase.WorkFolder);
            [result, issues] = coordinator.commitPreview();
            testCase.verifyTrue(result.success);
            testCase.verifyFalse(has_errors(issues));
            testCase.verifyEqual(coordinator.PreviewStatus, 'committed');
        end

        function testCommitKeepsDirty(testCase)
            coordinator = previewed(testCase.WorkFolder);
            coordinator.commitPreview();
            testCase.verifyTrue(coordinator.Session.Dirty);
        end

        function testSecondCommitRequiresPreview(testCase)
            coordinator = previewed(testCase.WorkFolder);
            coordinator.commitPreview();
            [~, issues] = coordinator.commitPreview();
            testCase.verifyEqual(issues.code, 'APP_PREVIEW_REQUIRED');
        end

        function testStaleCommitBlocked(testCase)
            coordinator = previewed(testCase.WorkFolder);
            project = coordinator.Session.Project;
            project.common.abi = 'coffabi';
            coordinator.updateProject(project);
            [~, issues] = coordinator.commitPreview();
            testCase.verifyEqual(issues.code, 'APP_PREVIEW_REQUIRED');
        end

        function testProviderInputsRemainUnchanged(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, @valid_provider);
            project = coordinator.Session.Project;
            coordinator.createPreview();
            testCase.verifyEqual(coordinator.Session.Project, project);
        end

        function testProviderIssuesRejectExtraField(testCase)
            issue = valid_issue();
            issue.extra = true;
            verify_invalid_provider_issue(testCase, testCase.WorkFolder, issue);
        end

        function testProviderIssuesRejectMissingField(testCase)
            issue = rmfield(valid_issue(), 'message');
            verify_invalid_provider_issue(testCase, testCase.WorkFolder, issue);
        end

        function testProviderIssuesRejectInvalidSeverity(testCase)
            issue = valid_issue();
            issue.severity = 'Fatal';
            verify_invalid_provider_issue(testCase, testCase.WorkFolder, issue);
        end

        function testProviderIssuesRejectInvalidInstanceIndex(testCase)
            issue = valid_issue();
            issue.instance_index = 0.5;
            verify_invalid_provider_issue(testCase, testCase.WorkFolder, issue);
        end

        function testProviderIssuesRejectNontextFields(testCase)
            fields = {'severity', 'code', 'message', 'field_path', 'file_path'};
            for index = 1:numel(fields)
                issue = valid_issue();
                issue.(fields{index}) = 7;
                verify_invalid_provider_issue(testCase, testCase.WorkFolder, issue);
            end
        end

        function testLoadInvalidatesValidPreview(testCase)
            coordinator = previewed(testCase.WorkFolder);
            draft = coordinator.Session.Project;
            draft.instances(1).internal_name = 'renamed';
            coordinator.updateProjectDraft(draft);
            coordinator.createPreview();
            testCase.verifyNotEmpty(coordinator.LegacyFileRisks);
            path = fullfile(testCase.WorkFolder, 'other.mat');
            save_project(path, valid_project(fullfile(testCase.WorkFolder, 'other')));
            [loaded, issues] = coordinator.loadProject(path);
            testCase.verifyTrue(loaded);
            testCase.verifyEmpty(issues);
            verify_preview_cleared(testCase, coordinator, 'stale');
            testCase.verifyEmpty(coordinator.LegacyFileRisks);
            [~, commitIssues] = coordinator.commitPreview();
            testCase.verifyEqual(commitIssues.code, 'APP_PREVIEW_REQUIRED');
        end

        function testLoadClearsLastCommitResult(testCase)
            coordinator = previewed(testCase.WorkFolder);
            coordinator.commitPreview();
            path = fullfile(testCase.WorkFolder, 'other.mat');
            save_project(path, valid_project(fullfile(testCase.WorkFolder, 'other')));
            coordinator.loadProject(path);
            testCase.verifyEmpty(fieldnames(coordinator.LastCommitResult));
        end

        function testLoadFailurePreservesCurrentState(testCase)
            coordinator = previewed(testCase.WorkFolder);
            project = coordinator.Session.Project;
            snapshot = coordinator.PreviewSnapshot;
            candidates = coordinator.PreviewCandidates;
            dependencies = coordinator.PreviewDependencies;
            status = coordinator.PreviewStatus;
            dirty = coordinator.Session.Dirty;
            filePath = coordinator.Session.FilePath;
            previewIssues = coordinator.PreviewIssues;
            summary = coordinator.PreviewSummary;
            lastCommit = coordinator.LastCommitResult;
            [loaded, issues] = coordinator.loadProject( ...
                fullfile(testCase.WorkFolder, 'missing.mat'));
            testCase.verifyFalse(loaded);
            testCase.verifyEqual(issues.code, 'APP_PROJECT_LOAD_FAILED');
            testCase.verifyEqual(coordinator.Session.Project, project);
            testCase.verifyEqual(coordinator.Session.Dirty, dirty);
            testCase.verifyEqual(coordinator.Session.FilePath, filePath);
            testCase.verifyEqual(coordinator.PreviewStatus, status);
            testCase.verifyEqual(coordinator.PreviewSnapshot, snapshot);
            testCase.verifyEqual(coordinator.PreviewCandidates, candidates);
            testCase.verifyEqual(coordinator.PreviewDependencies, dependencies);
            testCase.verifyEqual(coordinator.PreviewIssues, previewIssues);
            testCase.verifyEqual(coordinator.PreviewSummary, summary);
            testCase.verifyEqual(coordinator.LastCommitResult, lastCommit);
        end

        function testLoadStaleHashSucceedsAndMakesDirty(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            project = valid_project(fullfile(testCase.WorkFolder, 'stale'));
            [~, expectedHash] = c2837x_block_build_interface_hash(project, 1);
            project.instances.interface_hash = bitxor(expectedHash, uint32(1));
            path = fullfile(testCase.WorkFolder, 'stale.mat');
            save_project(path, project);

            [loaded, issues] = coordinator.loadProject(path);

            testCase.verifyTrue(loaded);
            testCase.verifyEmpty(issues);
            testCase.verifyEqual( ...
                coordinator.Session.Project.instances.interface_hash, expectedHash);
            testCase.verifyTrue(coordinator.Session.Dirty);
        end

        function testLoadMatchingHashSucceedsAndStaysClean(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            project = valid_project(fullfile(testCase.WorkFolder, 'matching'));
            path = fullfile(testCase.WorkFolder, 'matching.mat');
            save_project(path, project);

            [loaded, issues] = coordinator.loadProject(path);

            testCase.verifyTrue(loaded);
            testCase.verifyEmpty(issues);
            testCase.verifyFalse(coordinator.Session.Dirty);
        end

        function testDraftStructureErrorDoesNotApply(testCase)
            coordinator = previewed(testCase.WorkFolder);
            project = coordinator.Session.Project;
            draft = rmfield(project, 'common');
            [applied, issues] = coordinator.updateProjectDraft(draft);
            testCase.verifyFalse(applied);
            testCase.verifyTrue(any(strcmp({issues.code}, 'PROJECT_STRUCTURE_INVALID')));
            testCase.verifyEqual(coordinator.Session.Project, project);
            verify_preview_cleared(testCase, coordinator, 'stale');
        end

        function testDraftSemanticValidationScenarios(testCase)
            scenarios = {'internal_name', 'dim_zero', 'dim_fraction', ...
                'socket_range', 'port_zero', 'port_fraction', ...
                'socket_duplicate', 'port_duplicate', 'io_duplicate', ...
                'case_duplicate', 'payload_odd', 'payload_small'};
            expected = {'INTERNAL_NAME_INVALID', 'VARIABLE_DIM_INVALID', ...
                'VARIABLE_DIM_INVALID', 'SOCKET_INVALID', 'TCP_PORT_INVALID', ...
                'TCP_PORT_INVALID', 'SOCKET_DUPLICATE', 'TCP_PORT_DUPLICATE', ...
                'VARIABLE_NAME_CONFLICT', 'VARIABLE_NAME_CONFLICT', ...
                'MAX_PAYLOAD_ODD', 'MAX_PAYLOAD_TOO_SMALL'};
            for index = 1:numel(scenarios)
                coordinator = previewed(fullfile(testCase.WorkFolder, scenarios{index}));
                draft = semantic_draft(coordinator.Session.Project, scenarios{index});
                [applied, issues] = coordinator.updateProjectDraft(draft);
                testCase.verifyTrue(applied, scenarios{index});
                testCase.verifyTrue(any(strcmp({issues.code}, expected{index})), ...
                    scenarios{index});
                testCase.verifyEqual(coordinator.Session.Project, draft, ...
                    scenarios{index});
                testCase.verifyTrue(coordinator.Session.Dirty, scenarios{index});
                testCase.verifyEqual(coordinator.PreviewStatus, 'stale', ...
                    scenarios{index});
            end
        end

        function testValidDraftNormalizesIntegerTypes(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            draft = coordinator.Session.Project;
            draft.instances(1).iodevice.settings.socket_number = 2;
            draft.instances(1).iodevice.settings.tcp_port = 6000;
            draft.instances(1).max_payload_size_bytes = 2048;
            [applied, issues] = coordinator.updateProjectDraft(draft);
            testCase.verifyTrue(applied);
            testCase.verifyFalse(has_errors(issues));
            value = coordinator.Session.Project.instances(1);
            testCase.verifyClass(value.iodevice.settings.socket_number, 'uint16');
            testCase.verifyClass(value.iodevice.settings.tcp_port, 'uint16');
            testCase.verifyClass(value.max_payload_size_bytes, 'uint32');
        end

        function testDraftRenameCreatesDeduplicatedEditorRisk(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            draft = coordinator.Session.Project;
            draft.instances(1).internal_name = 'renamed';
            coordinator.updateProjectDraft(draft);
            draft.instances(1).internal_name = 'instance_1';
            coordinator.updateProjectDraft(draft);
            draft.instances(1).internal_name = 'renamed_again';
            coordinator.updateProjectDraft(draft);
            risks = coordinator.LegacyFileRisks;
            testCase.verifyEqual({risks.internal_name}, {'instance_1', 'renamed'});
        end

        function testValidProjectSavesWithoutConfirmation(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            path = fullfile(testCase.WorkFolder, 'project.mat');
            [saved, issues, confirmation] = coordinator.saveProject(path, false);
            testCase.verifyTrue(saved);
            testCase.verifyFalse(confirmation);
            testCase.verifyFalse(has_errors(issues));
            testCase.verifyTrue(isfile(path));
        end

        function testInvalidProjectRequiresSaveConfirmation(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            draft = semantic_draft(coordinator.Session.Project, 'port_zero');
            coordinator.updateProjectDraft(draft);
            path = fullfile(testCase.WorkFolder, 'blocked.mat');
            [saved, issues, confirmation] = coordinator.saveProject(path, false);
            testCase.verifyFalse(saved);
            testCase.verifyTrue(confirmation);
            testCase.verifyTrue(has_errors(issues));
            testCase.verifyFalse(isfile(path));
        end

        function testAllowedInvalidProjectActuallySaves(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            draft = semantic_draft(coordinator.Session.Project, 'port_zero');
            coordinator.updateProjectDraft(draft);
            path = fullfile(testCase.WorkFolder, 'allowed.mat');
            [saved, ~, confirmation] = coordinator.saveProject(path, true);
            testCase.verifyTrue(saved);
            testCase.verifyTrue(confirmation);
            testCase.verifyTrue(isfile(path));
        end

        function testInformationOnlyDoesNotRequireConfirmation(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            path = fullfile(testCase.WorkFolder, 'information.mat');
            [saved, issues, confirmation] = coordinator.saveProject(path, false);
            testCase.verifyTrue(any(strcmp({issues.severity}, 'Information')));
            testCase.verifyFalse(confirmation);
            testCase.verifyTrue(saved);
        end

        function testSaveFailureReturnsStableIssue(testCase)
            coordinator = make_coordinator(testCase.WorkFolder, []);
            path = fullfile(testCase.WorkFolder, 'missing', 'project.mat');
            [saved, issues] = coordinator.saveProject(path, false);
            testCase.verifyFalse(saved);
            testCase.verifyEqual(issues(end).code, 'APP_PROJECT_SAVE_FAILED');
            testCase.verifyNotEqual(issues(end).message, ...
                'Failed to save project.');
        end

        function testHighVersionLoadReturnsStableIssue(testCase)
            coordinator = previewed(testCase.WorkFolder);
            project = valid_project(testCase.WorkFolder);
            project.format_version = uint16(5);
            path = fullfile(testCase.WorkFolder, 'future.mat');
            save_project(path, project);
            [loaded, issues] = coordinator.loadProject(path);
            testCase.verifyFalse(loaded);
            testCase.verifyEqual(issues.code, ...
                'APP_PROJECT_VERSION_UNSUPPORTED');
            testCase.verifyEqual(issues.severity, 'Error');
            testCase.verifyTrue(contains(issues.message, ...
                'version higher than this App supports'));
            testCase.verifyTrue(contains(issues.message, ...
                'use a newer version of the App'));
            testCase.verifyFalse(any(strcmp({issues.code}, ...
                'APP_PROJECT_LOAD_FAILED')));
            testCase.verifyEqual(coordinator.PreviewStatus, 'valid');
        end
    end
end

function coordinator = make_coordinator(root, provider)
project = valid_project(root);
session = c2837x_block_project_session(project);
session.updateProject(project);
coordinator = c2837x_block_app_coordinator(session, provider);
end

function coordinator = previewed(root)
coordinator = make_coordinator(root, @valid_provider);
[~, issues] = coordinator.createPreview();
assert(~has_errors(issues));
end

function project = valid_project(root)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.1.10';
project.common.network.gateway = '0.0.0.0';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
instance = c2837x_block_create_default_instance();
changes = instance_changes(1);
names = fieldnames(changes);
for index = 1:numel(names)
    instance.(names{index}) = changes.(names{index});
end
project.instances = instance;
[~, project.instances.interface_hash] = ...
    c2837x_block_build_interface_hash(project, 1);
end

function changes = instance_changes(index)
changes = struct('display_name', sprintf('Instance %u', index), ...
    'internal_name', sprintf('instance_%u', index), ...
    'iodevice', struct('type', 'w5300_tcp', 'settings', struct( ...
    'socket_number', uint16(index - 1), 'tcp_port', uint16(4999 + index))), ...
    'inputs', [struct('name', 'a', 'type', 'int16', 'dim', 1), ...
    struct('name', 'b', 'type', 'single', 'dim', 1)], ...
    'outputs', struct('name', 'result', 'type', 'single', 'dim', 1));
end

function [candidates, dependencies, issues] = valid_provider(project)
[candidates, dependencies, issues] = provider(project, 'user');
end

function [candidates, dependencies, issues] = automatic_provider(project)
[candidates, dependencies, issues] = provider(project, 'auto_generated');
end

function [candidates, dependencies, issues] = provider(project, category)
target = c2837x_block_normalize_absolute_path(fullfile( ...
    project.output.dsp_root, '..', 'user.c'));
definition = struct('target_path', target, 'category', category, ...
    'owner', 'test', 'instance_index', 1, ...
    'content_bytes', uint8('candidate'));
candidates = c2837x_block_build_candidate_files(definition);
dependencies = [dependency('generator_template', 'template'), ...
    dependency('core_source', 'core')];
issues = empty_issues();
end

function value = dependency(role, identity)
value = struct('role', role, 'identity', identity, 'source_kind', 'memory', ...
    'source_path', '', 'content_bytes', uint8(identity));
end

function [candidates, dependencies, issues] = throwing_provider(~)
candidates = struct([]); %#ok<NASGU>
dependencies = struct([]); %#ok<NASGU>
issues = empty_issues(); %#ok<NASGU>
error('Test:Secret', 'secret provider detail');
end

function [candidates, dependencies, issues] = invalid_provider(~)
candidates = struct('bad', true); dependencies = struct([]); issues = struct([]);
end

function [candidates, dependencies, issues] = invalid_dependency_provider(project)
[candidates, dependencies, issues] = valid_provider(project);
dependencies(1).role = 'bad';
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end

function tf = has_errors(issues)
tf = ~isempty(issues) && any(strcmp({issues.severity}, 'Error'));
end

function write_bytes(path, bytes)
fileID = fopen(path, 'wb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
assert(fwrite(fileID, bytes, 'uint8') == numel(bytes));
clear cleanup
end

function issue = valid_issue()
issue = struct('severity', 'Warning', 'code', 'TEST_WARNING', ...
    'message', 'Test warning.', 'field_path', 'project', ...
    'instance_index', 0, 'file_path', '');
end

function verify_invalid_provider_issue(testCase, root, issue)
provider_issue_state('set', issue);
coordinator = make_coordinator(root, @configured_issue_provider);
before = filesystem_snapshot(root);
[view, issues] = coordinator.createPreview();
testCase.verifyEqual(view.status, 'blocked');
testCase.verifyEqual(issues(end).code, ...
    'APP_PREVIEW_PROVIDER_RESULT_INVALID');
testCase.verifyEqual(filesystem_snapshot(root), before);
end

function [candidates, dependencies, issues] = configured_issue_provider(project)
[candidates, dependencies] = valid_provider(project);
issues = provider_issue_state('get');
end

function issue = provider_issue_state(action, value)
persistent stored
if strcmp(action, 'set')
    stored = value;
end
issue = stored;
end

function verify_preview_cleared(testCase, coordinator, status)
testCase.verifyEqual(coordinator.PreviewStatus, status);
testCase.verifyEmpty(fieldnames(coordinator.PreviewSnapshot));
testCase.verifyEmpty(coordinator.PreviewCandidates);
testCase.verifyEmpty(coordinator.PreviewDependencies);
testCase.verifyEmpty(coordinator.PreviewIssues);
testCase.verifyEmpty(fieldnames(coordinator.PreviewSummary));
end

function draft = semantic_draft(project, scenario)
draft = project;
switch scenario
    case 'internal_name'
        draft.instances(1).internal_name = '_bad';
    case 'dim_zero'
        draft.instances(1).inputs(1).dim = 0;
    case 'dim_fraction'
        draft.instances(1).inputs(1).dim = 1.5;
    case 'socket_range'
        draft.instances(1).iodevice.settings.socket_number = 8;
    case 'port_zero'
        draft.instances(1).iodevice.settings.tcp_port = 0;
    case 'port_fraction'
        draft.instances(1).iodevice.settings.tcp_port = 5000.5;
    case {'socket_duplicate', 'port_duplicate'}
        second = draft.instances(1);
        second.display_name = 'Second';
        second.internal_name = 'second';
        second.iodevice.settings.socket_number = 1;
        second.iodevice.settings.tcp_port = 5001;
        if strcmp(scenario, 'socket_duplicate')
            second.iodevice.settings.socket_number = ...
                draft.instances(1).iodevice.settings.socket_number;
        else
            second.iodevice.settings.tcp_port = ...
                draft.instances(1).iodevice.settings.tcp_port;
        end
        draft.instances(2) = second;
    case 'io_duplicate'
        draft.instances(1).outputs(1).name = ...
            draft.instances(1).inputs(1).name;
    case 'case_duplicate'
        draft.instances(1).outputs(1).name = upper( ...
            draft.instances(1).inputs(1).name);
    case 'payload_odd'
        draft.instances(1).max_payload_size_bytes = 1023;
    case 'payload_small'
        draft.instances(1).max_payload_size_bytes = 6;
end
end

function save_project(path, project)
parent = fileparts(path);
if ~isfolder(parent)
    mkdir(parent);
end
save(path, 'project');
end

function snapshot = filesystem_snapshot(root)
entries = dir(fullfile(root, '**', '*'));
entries = entries(~[entries.isdir]);
snapshot = struct('folder', {entries.folder}, 'name', {entries.name}, ...
    'bytes', {entries.bytes});
end
