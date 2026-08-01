classdef test_project_candidates < matlab.unittest.TestCase
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
        function testDeterministicDspThenSfunAndDependencyMerge(testCase)
            project = two_instance_project(testCase.WorkFolder);
            [dsp, dspDependencies] = c2837x_block_build_dsp_candidates(project);
            [sfun, sfunDependencies] = c2837x_block_build_sfun_candidates(project);

            [first, dependencies, issues] = ...
                c2837x_block_build_project_candidates(project);
            [second, repeatedDependencies, repeatedIssues] = ...
                c2837x_block_build_project_candidates(project);

            testCase.verifyEqual(first, [dsp sfun]);
            testCase.verifyEqual(second, first);
            testCase.verifyEqual(repeatedDependencies, dependencies);
            testCase.verifyEqual(repeatedIssues, issues);
            testCase.verifyEmpty(issues);
            testCase.verifyEqual(numel(dependencies), numel(unique( ...
                {dependencies.source_path})));
            testCase.verifyLessThan(numel(dependencies), ...
                numel(dspDependencies) + numel(sfunDependencies));
            testCase.verifyFalse(isfolder(project.output.dsp_root));
            testCase.verifyFalse(isfolder(project.output.sfun_root));
        end

        function testProjectRootConflictsAreReported(testCase)
            project = two_instance_project(testCase.WorkFolder);
            project.output.sfun_root = project.output.dsp_root;
            [~, ~, issues] = c2837x_block_build_project_candidates(project);
            testCase.verifyTrue(any(strcmp({issues.code}, 'OUTPUT_ROOTS_EQUAL')));

            project = two_instance_project(testCase.WorkFolder);
            project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
                fullfile(project.output.dsp_root, 'child'));
            [~, ~, issues] = c2837x_block_build_project_candidates(project);
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'DSP_ROOT_CONTAINS_SFUN_ROOT')));
        end

        function testRealCoordinatorTransactionAndUserProtection(testCase)
            project = two_instance_project(testCase.WorkFolder);
            userPath = fullfile(project.output.sfun_root, 'axis_alpha', ...
                'axis_alpha_sfun_user_config.h');
            mkdir(fileparts(userPath));
            write_bytes(userPath, uint8('user bytes'));
            session = c2837x_block_project_session(project);
            coordinator = c2837x_block_app_coordinator(session, ...
                @c2837x_block_build_project_candidates);
            before = tree(project.output.dsp_root, project.output.sfun_root);

            [view, issues] = coordinator.createPreview();

            testCase.verifyFalse(has_errors(issues));
            testCase.verifyEqual(view.status, 'valid');
            testCase.verifyEqual(tree(project.output.dsp_root, ...
                project.output.sfun_root), before);
            userIndex = find(endsWith({view.comparisons.target_path}, ...
                'axis_alpha_sfun_user_config.h'), 1);
            buildIndex = find(endsWith({view.comparisons.target_path}, ...
                'build_axis_alpha_sfun.m'), 1);
            testCase.verifyEqual(view.comparisons(userIndex).default_action, 'keep');
            testCase.verifyFalse(view.comparisons(userIndex).action_mandatory);
            testCase.verifyEqual(view.comparisons(buildIndex).default_action, 'create');

            [result, commitIssues] = coordinator.commitPreview();
            testCase.verifyTrue(result.success);
            testCase.verifyFalse(has_errors(commitIssues));
            testCase.verifyEqual(read_bytes(userPath), uint8('user bytes'));
            testCase.verifyTrue(isfile(fullfile(project.output.sfun_root, ...
                'axis_beta', 'build_axis_beta_sfun.m')));

            coordinator.createPreview();
            [second, secondIssues] = coordinator.commitPreview();
            testCase.verifyTrue(second.success);
            testCase.verifyFalse(has_errors(secondIssues));
            testCase.verifyEqual(second.skipped_count + second.kept_count, ...
                numel(second.files));
        end
    end
end

function project = two_instance_project(root)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
first = c2837x_block_create_default_instance();
first.display_name = 'Axis Alpha'; first.internal_name = 'axis_alpha';
first.inputs = struct('name', 'command', 'type', 'uint16', 'dim', 1);
first.outputs = struct('name', 'feedback', 'type', 'uint16', 'dim', 1);
second = first; second.display_name = 'Axis Beta'; second.internal_name = 'axis_beta';
second.iodevice.settings.socket_number = uint16(1);
second.iodevice.settings.tcp_port = uint16(5001);
project.instances = [first second];
for index = 1:2
    [~, project.instances(index).interface_hash] = ...
        c2837x_block_build_interface_hash(project, index);
end
end

function value = tree(varargin)
value = struct('path', {}, 'bytes', {});
for rootIndex = 1:nargin
    root = varargin{rootIndex};
    if ~isfolder(root), continue; end
    files = dir(fullfile(root, '**', '*'));
    files = files(~[files.isdir]);
    for index = 1:numel(files)
        path = fullfile(files(index).folder, files(index).name);
        value(end + 1) = struct('path', path, ...
            'bytes', read_bytes(path)); %#ok<AGROW>
    end
end
end

function write_bytes(path, bytes)
folder = fileparts(path);
if ~isfolder(folder), mkdir(folder); end
file = fopen(path, 'wb'); assert(file >= 0);
cleanup = onCleanup(@() fclose(file));
fwrite(file, bytes, 'uint8'); clear cleanup
end

function bytes = read_bytes(path)
file = fopen(path, 'rb'); assert(file >= 0);
cleanup = onCleanup(@() fclose(file));
bytes = reshape(fread(file, Inf, '*uint8'), 1, []);
clear cleanup
end

function tf = has_errors(issues)
tf = ~isempty(issues) && any(strcmp({issues.severity}, 'Error'));
end
