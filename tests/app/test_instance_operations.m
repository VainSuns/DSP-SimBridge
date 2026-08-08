classdef test_instance_operations < matlab.unittest.TestCase
    properties (TestParameter)
        invalidName = struct( ...
            'underscore', '_motor', ...
            'digit', '1motor', ...
            'space', 'motor speed', ...
            'hyphen', 'motor-speed', ...
            'nonAscii', 'motor电机', ...
            'empty', '')
        reservedName = struct( ...
            'keyword', 'while', ...
            'stepIndex', 'step_index', ...
            'generator', 'c2837x_block_input', ...
            'publicApi', 'C2837xBlock_Init')
        supportedType = {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'}
        invalidDim = struct( ...
            'zero', 0, ...
            'negative', -1, ...
            'fraction', 1.5, ...
            'vector', [1 2], ...
            'nan', NaN, ...
            'inf', Inf)
    end

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
        function testValidInternalName(testCase)
            [valid, message] = c2837x_block_validate_name('motor_1', {});

            testCase.verifyTrue(valid);
            testCase.verifyEmpty(message);
        end

        function testInvalidInternalNames(testCase, invalidName)
            [valid, message] = c2837x_block_validate_name(invalidName, {});

            testCase.verifyFalse(valid);
            testCase.verifyNotEmpty(message);
        end

        function testReservedNames(testCase, reservedName)
            [valid, message] = c2837x_block_validate_name(reservedName, {});

            testCase.verifyFalse(valid);
            testCase.verifyNotEmpty(message);
        end

        function testCaseInsensitiveNameConflicts(testCase)
            [sameCase, ~] = c2837x_block_validate_name('motor', {'motor'});
            [mixedCase, ~] = c2837x_block_validate_name('MOTOR', {'Motor'});

            testCase.verifyFalse(sameCase);
            testCase.verifyFalse(mixedCase);
        end

        function testInputOutputShareNameScope(testCase)
            session = c2837x_block_project_session();
            instance = valid_instance('motor', 0, 5000);
            instance.outputs(1).name = 'COMMAND';
            instance.inputs(1).name = 'command';

            testCase.verifyError(@() session.addInstance(instance), ...
                'C2837xBlock:Instance:InvalidName');
        end

        function testInputAndOutputDuplicates(testCase)
            inputSession = c2837x_block_project_session();
            inputInstance = valid_instance('input_dup', 0, 5000);
            inputInstance.inputs(2).name = 'COMMAND';
            outputSession = c2837x_block_project_session();
            outputInstance = valid_instance('output_dup', 1, 5001);
            outputInstance.outputs(2).name = 'STATUS';

            testCase.verifyError(@() inputSession.addInstance(inputInstance), ...
                'C2837xBlock:Instance:InvalidName');
            testCase.verifyError(@() outputSession.addInstance(outputInstance), ...
                'C2837xBlock:Instance:InvalidName');
        end

        function testSupportedTypes(testCase, supportedType)
            session = c2837x_block_project_session();
            instance = valid_instance('typed', 0, 5000);
            instance.inputs(1).type = supportedType;

            session.addInstance(instance);

            testCase.verifyEqual(session.Project.instances.inputs(1).type, supportedType);
        end

        function testUnsupportedType(testCase)
            session = c2837x_block_project_session();
            instance = valid_instance('bad_type', 0, 5000);
            instance.inputs(1).type = 'boolean';

            testCase.verifyError(@() session.addInstance(instance), ...
                'C2837xBlock:Instance:InvalidVariables');
        end

        function testInvalidDimensions(testCase, invalidDim)
            session = c2837x_block_project_session();
            instance = valid_instance('bad_dim', 0, 5000);
            instance.inputs(1).dim = invalidDim;

            testCase.verifyError(@() session.addInstance(instance), ...
                'C2837xBlock:Instance:InvalidVariables');
        end

        function testRequiresInputAndOutput(testCase)
            noInputSession = c2837x_block_project_session();
            noInput = valid_instance('no_input', 0, 5000);
            noInput.inputs = noInput.inputs([]);
            noOutputSession = c2837x_block_project_session();
            noOutput = valid_instance('no_output', 1, 5001);
            noOutput.outputs = noOutput.outputs([]);

            testCase.verifyError(@() noInputSession.addInstance(noInput), ...
                'C2837xBlock:Instance:InvalidVariables');
            testCase.verifyError(@() noOutputSession.addInstance(noOutput), ...
                'C2837xBlock:Instance:InvalidVariables');
        end

        function testAddPreservesOrderAndMarksDirty(testCase)
            project = project_with_instances({'first'}, 0, 5000);
            session = c2837x_block_project_session(project);

            session.addInstance(valid_instance('second', 1, 5001));

            testCase.verifyEqual({session.Project.instances.internal_name}, ...
                {'first', 'second'});
            testCase.verifyTrue(session.Dirty);
        end

        function testAddConflictsAreAtomic(testCase)
            project = project_with_instances({'motor'}, 0, 5000);
            nameSession = c2837x_block_project_session(project);
            socketSession = c2837x_block_project_session(project);
            portSession = c2837x_block_project_session(project);
            nameBefore = snapshot(nameSession);
            socketBefore = snapshot(socketSession);
            portBefore = snapshot(portSession);

            testCase.verifyError(@() nameSession.addInstance( ...
                valid_instance('MOTOR', 1, 5001)), ...
                'C2837xBlock:Instance:DuplicateName');
            testCase.verifyError(@() socketSession.addInstance( ...
                valid_instance('socket_dup', 0, 5001)), ...
                'C2837xBlock:Instance:DuplicateSocket');
            testCase.verifyError(@() portSession.addInstance( ...
                valid_instance('port_dup', 1, 5000)), ...
                'C2837xBlock:Instance:DuplicatePort');
            verify_snapshot(testCase, nameSession, nameBefore);
            verify_snapshot(testCase, socketSession, socketBefore);
            verify_snapshot(testCase, portSession, portBefore);
        end

        function testAddInstanceRejectsCrossClassSocketConflict(testCase)
            project = project_with_instances({'motor'}, 0, 5000);
            session = c2837x_block_project_session(project);
            session.saveProject(fullfile(testCase.WorkFolder, 'project.mat'));
            session.renameInstance(1, 'Motor renamed', 'motor_renamed');
            candidate = valid_instance('candidate', 1, 5001);
            candidate.iodevice.settings.socket_number = double(0);
            before = snapshot(session);

            testCase.verifyError(@() session.addInstance(candidate), ...
                'C2837xBlock:Instance:DuplicateSocket');

            verify_snapshot(testCase, session, before);
        end

        function testEditPreservesPositionAndUnchangedFields(testCase)
            project = project_with_instances({'first', 'second'}, [0 1], [5000 5001]);
            session = c2837x_block_project_session(project);
            unchanged = session.Project.instances(2);

            session.updateInstance(1, struct('display_name', 'Edited', ...
                'sample_time_sec', 2e-4));

            testCase.verifyEqual(session.Project.instances(1).display_name, 'Edited');
            testCase.verifyEqual(session.Project.instances(1).internal_name, 'first');
            testCase.verifyEqual(session.Project.instances(2), unchanged);
            testCase.verifyTrue(session.Dirty);
        end

        function testFailedInternalRenamePreservesCompleteSession(testCase)
            project = project_with_instances({'first', 'second'}, [0 1], [5000 5001]);
            session = c2837x_block_project_session(project);
            session.saveProject(fullfile(testCase.WorkFolder, 'project.mat'));
            session.renameInstance(1, 'First renamed', 'renamed_first');
            before = snapshot(session);

            testCase.verifyError(@() session.updateInstance(1, ...
                struct('internal_name', 'SECOND')), ...
                'C2837xBlock:Instance:DuplicateName');

            verify_snapshot(testCase, session, before);
        end

        function testUpdateInstanceRejectsCrossClassPortConflict(testCase)
            project = project_with_instances({'first', 'second'}, [0 1], [5000 5001]);
            session = c2837x_block_project_session(project);
            session.saveProject(fullfile(testCase.WorkFolder, 'project.mat'));
            session.renameInstance(1, 'First renamed', 'first_renamed');
            changes = struct('iodevice', struct('settings', ...
                struct('tcp_port', double(5000))));
            before = snapshot(session);

            testCase.verifyError(@() session.updateInstance(2, changes), ...
                'C2837xBlock:Instance:DuplicatePort');

            verify_snapshot(testCase, session, before);
        end

        function testCopyPreservesAllowedFieldsAndResetsState(testCase)
            source = valid_instance('source', 0, 5000);
            source.sample_time_sec = 3e-4;
            source.max_payload_size_bytes = uint32(2048);
            source.algorithm.mode = 'external_copy';
            source.algorithm.source_path = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'old_algorithm.c'));
            source.interface_hash = uint32(123);
            project = c2837x_block_create_default_project();
            project.instances = source;
            session = c2837x_block_project_session(project);

            session.copyInstance(1, 'Copy', 'copy', uint16(1), uint16(5001));
            copy = session.Project.instances(2);

            testCase.verifyEqual(copy.display_name, 'Copy');
            testCase.verifyEqual(copy.internal_name, 'copy');
            testCase.verifyEqual(copy.iodevice.settings.socket_number, uint16(1));
            testCase.verifyEqual(copy.iodevice.settings.tcp_port, uint16(5001));
            testCase.verifyEqual(copy.inputs, source.inputs);
            testCase.verifyEqual(copy.outputs, source.outputs);
            testCase.verifyEqual(copy.sample_time_sec, source.sample_time_sec, AbsTol=eps(3e-4));
            testCase.verifyEqual(copy.max_payload_size_bytes, source.max_payload_size_bytes);
            testCase.verifyEqual(copy.iodevice.type, source.iodevice.type);
            testCase.verifyEqual(copy.algorithm.mode, 'external_copy');
            testCase.verifyEmpty(copy.algorithm.source_path);
            testCase.verifyEqual(copy.interface_hash, uint32(0));
            testCase.verifyEqual(session.Project.instances(1), source);
            testCase.verifyTrue(session.Dirty);
        end

        function testCopyConflictIsAtomic(testCase)
            project = project_with_instances({'source'}, 0, 5000);
            session = c2837x_block_project_session(project);
            before = snapshot(session);

            testCase.verifyError(@() session.copyInstance(1, ...
                'Copy', 'copy', double(0), double(5001)), ...
                'C2837xBlock:Instance:DuplicateSocket');

            verify_snapshot(testCase, session, before);
        end

        function testUpdateDisplayNameAddsNoLegacyRisk(testCase)
            session = c2837x_block_project_session( ...
                project_with_instances({'motor'}, 0, 5000));

            session.updateInstance(1, struct('display_name', 'Motor display'));

            testCase.verifyEqual(session.Project.instances.display_name, 'Motor display');
            testCase.verifyEmpty(session.LegacyFileRisks);
            testCase.verifyTrue(session.Dirty);
        end

        function testUpdateOrdinaryFieldAddsNoLegacyRisk(testCase)
            session = c2837x_block_project_session( ...
                project_with_instances({'motor'}, 0, 5000));

            session.updateInstance(1, struct('sample_time_sec', 2e-4));

            testCase.verifyEmpty(session.LegacyFileRisks);
            testCase.verifyTrue(session.Dirty);
        end

        function testUpdateSameInternalNameAddsNoLegacyRisk(testCase)
            session = c2837x_block_project_session( ...
                project_with_instances({'motor'}, 0, 5000));

            session.updateInstance(1, struct('internal_name', 'motor'));

            testCase.verifyEmpty(session.LegacyFileRisks);
            testCase.verifyTrue(session.Dirty);
        end

        function testUpdateInternalNameAddsLegacyRisk(testCase)
            filePath = fullfile(testCase.WorkFolder, 'project.mat');
            session = c2837x_block_project_session( ...
                project_with_instances({'motor'}, 0, 5000));
            session.saveProject(filePath);

            session.updateInstance(1, struct('internal_name', 'motor_new'));

            testCase.verifyEqual(session.Project.instances.internal_name, 'motor_new');
            testCase.verifyTrue(session.Dirty);
            testCase.verifyEqual(session.FilePath, filePath);
            testCase.verifyNumElements(session.LegacyFileRisks, 1);
            testCase.verifyEqual(session.LegacyFileRisks.action, 'rename');
            testCase.verifyEqual(session.LegacyFileRisks.internal_name, 'motor');
            testCase.verifyNotEmpty(session.LegacyFileRisks.reason);
        end

        function testRenameInstanceAddsOnlyOneLegacyRisk(testCase)
            session = c2837x_block_project_session( ...
                project_with_instances({'motor'}, 0, 5000));

            session.renameInstance(1, 'Motor', 'motor_new');

            testCase.verifyEqual(session.Project.instances.internal_name, 'motor_new');
            testCase.verifyNumElements(session.LegacyFileRisks, 1);
            testCase.verifyEqual(session.LegacyFileRisks.action, 'rename');
            testCase.verifyEqual(session.LegacyFileRisks.internal_name, 'motor');
            testCase.verifyNotEmpty(session.LegacyFileRisks.reason);
        end

        function testCaseOnlyInternalRenameAddsLegacyRisk(testCase)
            session = c2837x_block_project_session( ...
                project_with_instances({'motor'}, 0, 5000));

            session.updateInstance(1, struct('internal_name', 'Motor'));

            testCase.verifyEqual(session.Project.instances.internal_name, 'Motor');
            testCase.verifyNumElements(session.LegacyFileRisks, 1);
            testCase.verifyEqual(session.LegacyFileRisks.action, 'rename');
            testCase.verifyEqual(session.LegacyFileRisks.internal_name, 'motor');
        end

        function testDeletePreservesOrderAndAddsLegacyRisk(testCase)
            session = c2837x_block_project_session( ...
                project_with_instances({'first', 'middle', 'last'}, ...
                [0 1 2], [5000 5001 5002]));

            session.deleteInstance(2);

            testCase.verifyEqual({session.Project.instances.internal_name}, ...
                {'first', 'last'});
            testCase.verifyEqual(session.LegacyFileRisks.action, 'delete');
            testCase.verifyEqual(session.LegacyFileRisks.internal_name, 'middle');
            testCase.verifyTrue(session.Dirty);
        end

        function testRenameAndDeleteDoNotTouchDisk(testCase)
            marker = fullfile(testCase.WorkFolder, 'motor_generated.c');
            fileID = fopen(marker, 'w');
            fclose(fileID);
            session = c2837x_block_project_session( ...
                project_with_instances({'motor', 'other'}, [0 1], [5000 5001]));

            session.renameInstance(1, 'Motor', 'motor_new');
            session.deleteInstance(2);

            testCase.verifyEqual({dir(testCase.WorkFolder).name}, ...
                {'.', '..', 'motor_generated.c'});
        end

        function testLegacyRisksAreSessionOnlyAndClearOnLoad(testCase)
            filePath = fullfile(testCase.WorkFolder, 'project.mat');
            targetProject = project_with_instances({'target'}, 2, 5002);
            target = c2837x_block_project_session(targetProject);
            target.saveProject(filePath);
            session = c2837x_block_project_session( ...
                project_with_instances({'motor'}, 0, 5000));
            session.renameInstance(1, 'Motor', 'motor_new');
            session.saveProject(fullfile(testCase.WorkFolder, 'saved.mat'));
            saved = load(fullfile(testCase.WorkFolder, 'saved.mat'), 'project');

            [~, targetHash] = c2837x_block_build_interface_hash(targetProject, 1);
            targetProject.instances(1).interface_hash = targetHash;

            session.loadProject(filePath);

            testCase.verifyFalse(isfield(saved.project, 'LegacyFileRisks'));
            testCase.verifyEmpty(session.LegacyFileRisks);
            testCase.verifyEqual(session.Project, targetProject);
            testCase.verifyTrue(session.Dirty);
        end
    end
end

function instance = valid_instance(name, socketNumber, tcpPort)
instance = c2837x_block_create_default_instance();
instance.display_name = [name ' display'];
instance.internal_name = name;
instance.iodevice.settings.socket_number = uint16(socketNumber);
instance.iodevice.settings.tcp_port = uint16(tcpPort);
instance.inputs = [variable('command', 'int16', 1), ...
    variable('reference', 'single', 2)];
instance.outputs = [variable('status', 'uint16', 1), ...
    variable('feedback', 'double', 2)];
end

function value = variable(name, type, dim)
value = struct('name', name, 'type', type, 'dim', dim);
end

function project = project_with_instances(names, sockets, ports)
project = c2837x_block_create_default_project();
instances = repmat(c2837x_block_create_default_instance(), 1, numel(names));
for index = 1:numel(names)
    instances(index) = valid_instance(names{index}, sockets(index), ports(index));
end
project.instances = instances;
end

function value = snapshot(session)
value = struct('project', session.Project, 'filePath', session.FilePath, ...
    'dirty', session.Dirty, 'risks', session.LegacyFileRisks);
end

function verify_snapshot(testCase, session, expected)
testCase.verifyEqual(session.Project, expected.project);
testCase.verifyEqual(session.FilePath, expected.filePath);
testCase.verifyEqual(session.Dirty, expected.dirty);
testCase.verifyEqual(session.LegacyFileRisks, expected.risks);
end
