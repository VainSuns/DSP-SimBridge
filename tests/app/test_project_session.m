classdef test_project_session < matlab.unittest.TestCase
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
        function testRoundTripStoresOnlyProject(testCase)
            project = populated_project('round-trip');
            filePath = fullfile(testCase.WorkFolder, 'project.mat');
            source = c2837x_block_project_session(project);
            target = c2837x_block_project_session();

            source.saveProject(filePath);
            variables = whos('-file', filePath);
            target.loadProject(filePath);

            testCase.verifyEqual({variables.name}, {'project'});
            testCase.verifyEqual(target.Project, project);
        end

        function testStateAndSuccessfulSave(testCase)
            session = c2837x_block_project_session();
            project = populated_project('saved');
            filePath = fullfile(testCase.WorkFolder, 'saved.mat');

            testCase.verifyEqual(session.State, 'never_saved');
            session.updateProject(project);
            testCase.verifyTrue(session.Dirty);
            session.saveProject(filePath);

            testCase.verifyEqual(session.State, 'saved_clean');
            testCase.verifyEqual(session.FilePath, filePath);
            testCase.verifyFalse(session.Dirty);
            session.updateProject(populated_project('changed'));
            testCase.verifyEqual(session.State, 'saved_dirty');
        end

        function testLoadMatchingHashStaysClean(testCase)
            project = populated_project('matching-hash');
            expectedHash = project.instances.interface_hash;
            filePath = write_project(testCase.WorkFolder, 'matching-hash.mat', project);
            session = c2837x_block_project_session();

            loaded = session.loadProject(filePath);

            testCase.verifyTrue(loaded);
            testCase.verifyEqual(session.Project.instances.interface_hash, expectedHash);
            testCase.verifyFalse(session.Dirty);
        end

        function testLoadStaleHashRefreshesAndMakesDirty(testCase)
            project = populated_project('stale-hash');
            project.instances.interface_hash = bitxor( ...
                project.instances.interface_hash, uint32(1));
            filePath = write_project(testCase.WorkFolder, 'stale-hash.mat', project);
            session = c2837x_block_project_session();

            loaded = session.loadProject(filePath);
            [~, expectedHash] = c2837x_block_build_interface_hash( ...
                session.Project, 1);

            testCase.verifyTrue(loaded);
            testCase.verifyEqual(session.Project.instances.interface_hash, expectedHash);
            testCase.verifyTrue(session.Dirty);
        end

        function testLoadMultipleHashesWithOneStaleMakesDirty(testCase)
            project = multi_instance_project('one-stale');
            expectedHashes = [project.instances.interface_hash];
            project.instances(2).interface_hash = bitxor( ...
                project.instances(2).interface_hash, uint32(1));
            filePath = write_project(testCase.WorkFolder, 'one-stale.mat', project);
            session = c2837x_block_project_session();

            loaded = session.loadProject(filePath);

            testCase.verifyTrue(loaded);
            testCase.verifyEqual([session.Project.instances.interface_hash], ...
                expectedHashes);
            testCase.verifyTrue(session.Dirty);
        end

        function testLoadMultipleMatchingHashesStaysClean(testCase)
            project = multi_instance_project('all-matching');
            expectedHashes = [project.instances.interface_hash];
            filePath = write_project(testCase.WorkFolder, 'all-matching.mat', project);
            session = c2837x_block_project_session();

            loaded = session.loadProject(filePath);

            testCase.verifyTrue(loaded);
            testCase.verifyEqual([session.Project.instances.interface_hash], ...
                expectedHashes);
            testCase.verifyFalse(session.Dirty);
        end

        function testFailedSaveKeepsDirtyAndPath(testCase)
            goodPath = fullfile(testCase.WorkFolder, 'saved.mat');
            badPath = fullfile(testCase.WorkFolder, 'missing', 'failed.mat');
            session = c2837x_block_project_session(populated_project('before'));
            session.saveProject(goodPath);
            session.updateProject(populated_project('dirty'));

            testCase.verifyError(@() session.saveProject(badPath), ...
                'C2837xBlock:Project:SaveFailed');

            testCase.verifyTrue(session.Dirty);
            testCase.verifyEqual(session.FilePath, goodPath);
        end

        function testLoadSaveDecisionSavesCurrentThenLoads(testCase)
            currentPath = fullfile(testCase.WorkFolder, 'current.mat');
            targetPath = write_project(testCase.WorkFolder, 'target.mat', ...
                populated_project('target'));
            session = saved_dirty_session(currentPath);
            dirtyProject = session.Project;

            loaded = session.loadProject(targetPath, 'Save');
            saved = load(currentPath, 'project');

            testCase.verifyTrue(loaded);
            testCase.verifyEqual(saved.project, dirtyProject);
            testCase.verifyEqual(session.Project.output.dsp_root, project_path('target'));
            testCase.verifyEqual(session.FilePath, targetPath);
            testCase.verifyFalse(session.Dirty);
        end

        function testLoadDontSaveDecisionLoadsWithoutSaving(testCase)
            currentPath = fullfile(testCase.WorkFolder, 'current.mat');
            targetPath = write_project(testCase.WorkFolder, 'target.mat', ...
                populated_project('target'));
            session = saved_dirty_session(currentPath);

            loaded = session.loadProject(targetPath, 'Don''t Save');
            saved = load(currentPath, 'project');

            testCase.verifyTrue(loaded);
            testCase.verifyEqual(saved.project.output.dsp_root, project_path('original'));
            testCase.verifyEqual(session.Project.output.dsp_root, project_path('target'));
            testCase.verifyFalse(session.Dirty);
        end

        function testLoadCancelKeepsCurrentSession(testCase)
            currentPath = fullfile(testCase.WorkFolder, 'current.mat');
            targetPath = write_project(testCase.WorkFolder, 'target.mat', ...
                populated_project('target'));
            session = saved_dirty_session(currentPath);
            before = snapshot(session);

            loaded = session.loadProject(targetPath, 'Cancel');

            testCase.verifyFalse(loaded);
            verify_snapshot(testCase, session, before);
        end

        function testCancelledSaveAbortsLoad(testCase)
            targetPath = write_project(testCase.WorkFolder, 'target.mat', ...
                populated_project('target'));
            session = c2837x_block_project_session();
            session.updateProject(populated_project('dirty'));
            before = snapshot(session);

            loaded = session.loadProject(targetPath, 'Save');

            testCase.verifyFalse(loaded);
            verify_snapshot(testCase, session, before);
        end

        function testFailedSaveAbortsLoad(testCase)
            targetPath = write_project(testCase.WorkFolder, 'target.mat', ...
                populated_project('target'));
            badSavePath = fullfile(testCase.WorkFolder, 'missing', 'save.mat');
            session = c2837x_block_project_session();
            session.updateProject(populated_project('dirty'));
            before = snapshot(session);

            testCase.verifyError( ...
                @() session.loadProject(targetPath, 'Save', badSavePath), ...
                'C2837xBlock:Project:SaveFailed');

            verify_snapshot(testCase, session, before);
        end

        function testCloseDecisions(testCase)
            savePath = fullfile(testCase.WorkFolder, 'close.mat');
            saveSession = dirty_session('save');
            discardSession = dirty_session('discard');
            cancelSession = dirty_session('cancel');

            saveResult = saveSession.canDiscardChanges('Save', savePath);
            discardResult = discardSession.canDiscardChanges('Don''t Save');
            cancelResult = cancelSession.canDiscardChanges('Cancel');

            testCase.verifyTrue(saveResult);
            testCase.verifyFalse(saveSession.Dirty);
            testCase.verifyTrue(discardResult);
            testCase.verifyTrue(discardSession.Dirty);
            testCase.verifyFalse(cancelResult);
            testCase.verifyTrue(cancelSession.Dirty);
        end

        function testRejectsUnsupportedFormatVersion(testCase)
            project = c2837x_block_create_default_project();
            project.format_version = uint16(4);
            filePath = write_project(testCase.WorkFolder, 'high-format.mat', project);

            testCase.verifyError(@() load_new_session(filePath), ...
                'C2837xBlock:Project:UnsupportedVersion');
        end

        function testRejectsZeroAndInvalidFormatVersion(testCase)
            zeroProject = c2837x_block_create_default_project();
            zeroProject.format_version = uint16(0);
            invalidProject = c2837x_block_create_default_project();
            invalidProject.format_version = '2';
            zeroPath = write_project(testCase.WorkFolder, 'zero-format.mat', zeroProject);
            invalidPath = write_project(testCase.WorkFolder, 'invalid-format.mat', invalidProject);

            testCase.verifyError(@() load_new_session(zeroPath), ...
                'C2837xBlock:Project:InvalidVersion');
            testCase.verifyError(@() load_new_session(invalidPath), ...
                'C2837xBlock:Project:InvalidVersion');
        end

        function testRejectsInvalidProtocolVersions(testCase)
            highProject = c2837x_block_create_default_project();
            highProject.common.protocol_version = uint16(2);
            zeroProject = c2837x_block_create_default_project();
            zeroProject.common.protocol_version = uint16(0);
            invalidProject = c2837x_block_create_default_project();
            invalidProject.common.protocol_version = struct();
            highPath = write_project(testCase.WorkFolder, 'high-protocol.mat', highProject);
            zeroPath = write_project(testCase.WorkFolder, 'zero-protocol.mat', zeroProject);
            invalidPath = write_project(testCase.WorkFolder, 'invalid-protocol.mat', invalidProject);

            testCase.verifyError(@() load_new_session(highPath), ...
                'C2837xBlock:Project:UnsupportedVersion');
            testCase.verifyError(@() load_new_session(zeroPath), ...
                'C2837xBlock:Project:InvalidVersion');
            testCase.verifyError(@() load_new_session(invalidPath), ...
                'C2837xBlock:Project:InvalidVersion');
        end

        function testRejectsDoubleFormatVersionWithoutChangingSession(testCase)
            project = c2837x_block_create_default_project();
            project.format_version = double(2);

            verify_rejected_load_preserves_session(testCase, ...
                testCase.WorkFolder, 'double-format.mat', project, ...
                'C2837xBlock:Project:InvalidVersion');
        end

        function testRejectsDoubleProtocolVersionWithoutChangingSession(testCase)
            project = c2837x_block_create_default_project();
            project.common.protocol_version = double(1);

            verify_rejected_load_preserves_session(testCase, ...
                testCase.WorkFolder, 'double-protocol.mat', project, ...
                'C2837xBlock:Project:InvalidVersion');
        end

        function testRejectsOtherIntegerVersionTypesWithoutChangingSession(testCase)
            formatProject = c2837x_block_create_default_project();
            formatProject.format_version = int32(2);
            protocolProject = c2837x_block_create_default_project();
            protocolProject.common.protocol_version = uint32(1);

            verify_rejected_load_preserves_session(testCase, ...
                testCase.WorkFolder, 'int32-format.mat', formatProject, ...
                'C2837xBlock:Project:InvalidVersion');
            verify_rejected_load_preserves_session(testCase, ...
                testCase.WorkFolder, 'uint32-protocol.mat', protocolProject, ...
                'C2837xBlock:Project:InvalidVersion');
        end

        function testRejectsUntypedEmptyInstancesWithoutChangingSession(testCase)
            project = c2837x_block_create_default_project();
            project.instances = struct([]);

            verify_rejected_load_preserves_session(testCase, ...
                testCase.WorkFolder, 'untyped-empty-instances.mat', project, ...
                'C2837xBlock:Project:InvalidStructure');
        end

        function testRejectsIncompleteEmptyInstanceSchemaWithoutChangingSession(testCase)
            project = c2837x_block_create_default_project();
            project.instances = struct('display_name', {});

            verify_rejected_load_preserves_session(testCase, ...
                testCase.WorkFolder, 'incomplete-empty-instances.mat', project, ...
                'C2837xBlock:Project:InvalidStructure');
        end

        function testTypedEmptyInstancesRoundTrip(testCase)
            project = c2837x_block_create_default_project();
            filePath = fullfile(testCase.WorkFolder, 'typed-empty-instances.mat');
            source = c2837x_block_project_session(project);
            target = c2837x_block_project_session();

            source.saveProject(filePath);
            target.loadProject(filePath);

            testCase.verifyEmpty(target.Project.instances);
            testCase.verifyEqual(target.Project, project);
        end

        function testRejectsMissingProjectAndCriticalField(testCase)
            missingProjectPath = fullfile(testCase.WorkFolder, 'missing-project.mat');
            other = struct();
            save(missingProjectPath, 'other');
            project = c2837x_block_create_default_project();
            project.common = rmfield(project.common, 'network');
            missingFieldPath = write_project(testCase.WorkFolder, ...
                'missing-field.mat', project);

            testCase.verifyError(@() load_new_session(missingProjectPath), ...
                'C2837xBlock:Project:MissingProject');
            testCase.verifyError(@() load_new_session(missingFieldPath), ...
                'C2837xBlock:Project:InvalidStructure');
        end

        function testFailedLoadPreservesSession(testCase)
            currentPath = fullfile(testCase.WorkFolder, 'current.mat');
            invalidProject = c2837x_block_create_default_project();
            invalidProject.output = rmfield(invalidProject.output, 'sfun_root');
            invalidPath = write_project(testCase.WorkFolder, 'invalid.mat', invalidProject);
            session = saved_dirty_session(currentPath);
            before = snapshot(session);

            testCase.verifyError(@() session.loadProject(invalidPath, 'Don''t Save'), ...
                'C2837xBlock:Project:InvalidStructure');

            verify_snapshot(testCase, session, before);
        end
    end
end

function project = populated_project(dspRoot)
project = c2837x_block_create_default_project();
project.output.dsp_root = project_path(dspRoot);
project.instances = c2837x_block_create_default_instance();
project.instances.display_name = 'Instance';
project.instances.internal_name = 'instance';
project.instances.inputs = struct( ...
    'name', 'input_value', 'type', 'single', 'dim', 1);
project.instances.outputs = struct( ...
    'name', 'output_value', 'type', 'single', 'dim', 1);
[~, project.instances.interface_hash] = ...
    c2837x_block_build_interface_hash(project, 1);
end

function project = multi_instance_project(dspRoot)
project = populated_project(dspRoot);
second = project.instances;
second.display_name = 'Second';
second.internal_name = 'second';
second.iodevice.settings.socket_number = uint16(1);
second.iodevice.settings.tcp_port = uint16(5001);
project.instances(2) = second;
for index = 1:numel(project.instances)
    [~, project.instances(index).interface_hash] = ...
        c2837x_block_build_interface_hash(project, index);
end
end

function path = project_path(name)
path = c2837x_block_normalize_absolute_path(fullfile(tempdir, ['c2837x-' name]));
end

function filePath = write_project(folder, name, project)
filePath = fullfile(folder, name);
save(filePath, 'project');
end

function session = dirty_session(value)
session = c2837x_block_project_session();
session.updateProject(populated_project(value));
end

function session = saved_dirty_session(filePath)
session = c2837x_block_project_session(populated_project('original'));
session.saveProject(filePath);
session.updateProject(populated_project('dirty'));
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

function verify_rejected_load_preserves_session(testCase, folder, name, ...
        project, errorID)
filePath = write_project(folder, name, project);
currentPath = fullfile(folder, ['current-' name]);
session = saved_dirty_session(currentPath);
before = snapshot(session);

testCase.verifyError(@() session.loadProject(filePath, 'Don''t Save'), errorID);
verify_snapshot(testCase, session, before);
end

function load_new_session(filePath)
session = c2837x_block_project_session();
session.loadProject(filePath);
end
