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
