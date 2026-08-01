classdef test_sfun_pc_integration < matlab.unittest.TestCase
    properties
        WorkFolder
        RepositoryRoot
        Python
    end

    methods (TestClassSetup)
        function setup(testCase)
            testCase.RepositoryRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'app')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'tests', 'pc')));
            configured = pyenv;
            testCase.Python = configured.Executable;
            testCase.assertTrue(isfile(testCase.Python), 'A real Python executable is required.');
        end
    end

    methods (TestMethodSetup)
        function createFolder(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.WorkFolder = fixture.Folder;
        end
    end

    methods (Test)
        function testMockRepeatability(testCase)
            script = fullfile(testCase.RepositoryRoot, 'tests', 'pc', ...
                'run_sfun_pc_matrix.py');
            cacheFolder = fullfile(testCase.RepositoryRoot, 'tests', 'pc', ...
                '__pycache__');
            source = fileread(script);
            disablePosition = strfind(source, 'sys.dont_write_bytecode = True');
            importPosition = strfind(source, 'from sfun_mock_endpoint import');
            testCase.assertFalse(isfolder(cacheFolder), ...
                'The test must start without a repository Python cache.');
            testCase.verifyNotEmpty(disablePosition);
            testCase.verifyNotEmpty(importPosition);
            testCase.verifyLessThan(disablePosition(1), importPosition(1));

            verify_mock_run(testCase, script, cacheFolder);
            verify_mock_run(testCase, script, cacheFolder);
        end

        function testAppCommitDualBuildAndNormalMode(testCase)
            project = integration_project(testCase.WorkFolder);
            session = c2837x_block_project_session(project);
            coordinator = c2837x_block_app_coordinator(session, ...
                @c2837x_block_build_project_candidates);
            [view, previewIssues] = coordinator.createPreview();
            testCase.assertEqual(view.status, 'valid', issue_text(previewIssues));
            [commit, commitIssues] = coordinator.commitPreview();
            testCase.assertTrue(commit.success, issue_text(commitIssues));
            testCase.verifyEqual(sum(contains({commit.files.target_path}, ...
                project.output.sfun_root)), 20);

            compiler = mex.getCompilerConfigurations('C', 'Selected');
            simulinkInfo = ver('simulink');
            testCase.assertFalse(isempty(compiler));
            testCase.assertFalse(isempty(simulinkInfo));
            fprintf('MATLAB_VERSION=%s\nSIMULINK_VERSION=%s\nCOMPUTER=%s\n', ...
                version, simulinkInfo.Version, computer);
            fprintf('OS=%s\nMEXEXT=%s\nCOMPILER_NAME=%s\nCOMPILER_VERSION=%s\n', ...
                system_dependent('getos'), mexext, compiler.Name, compiler.Version);
            fprintf('COMPILER_LOCATION=%s\n', compiler.Location);

            originalFolder = pwd; originalPath = path; originalEnvironment = getenv('PATH');
            unrelated = fullfile(testCase.WorkFolder, 'unrelated'); mkdir(unrelated);
            folderCleanup = onCleanup(@() cd(originalFolder)); cd(unrelated);
            loadedModels = cell(1, 2);
            for index = 1:2
                name = project.instances(index).internal_name;
                folder = fullfile(project.output.sfun_root, name);
                script = fullfile(folder, ['build_' name '_sfun.m']); %#ok<NASGU>
                evalc('run(script)');
                evalc('run(script)');
                mexPath = fullfile(folder, [name '_sfun.' mexext]);
                testCase.verifyTrue(isfile(mexPath));
                info = dir(mexPath);
                fprintf('%s_MEX_PATH=%s\n%s_MEX_SIZE=%u\n', ...
                    upper(name), mexPath, upper(name), info.bytes);
            end
            testCase.verifyEqual(pwd, unrelated);
            testCase.verifyEqual(path, originalPath);
            testCase.verifyEqual(getenv('PATH'), originalEnvironment);
            clear folderCleanup

            verify_foreign_loaded(testCase, project, testCase.WorkFolder);
            verify_locked_rebuild(testCase, project);

            for index = 1:2
                instance = project.instances(index);
                name = instance.internal_name;
                transcript = fullfile(testCase.WorkFolder, [name '.json']);
                fprintf('SIMULINK_INSTANCE=%s PORT=%u HASH=0x%08X\n%s\n', ...
                    name, instance.iodevice.settings.tcp_port, ...
                    instance.interface_hash, fileread(fullfile( ...
                    project.output.sfun_root, name, [name '_sfun_config.h'])));
                simulation = run_simulink_case(fullfile(project.output.sfun_root, name), ...
                    name, instance.iodevice.settings.tcp_port, ...
                    instance.interface_hash, transcript, testCase.Python, true);
                loadedModels{index} = simulation.model;
                fprintf('NORMAL_SIMULINK_%s=PASS\n', upper(extractAfter(name, 'axis_')));
            end
            loadedCleanup = onCleanup(@() close_models(loadedModels));
            testCase.verifyTrue(all(cellfun(@bdIsLoaded, loadedModels)));
            [~, loadedPaths] = inmem('-completenames');
            testCase.verifyTrue(any(endsWith(loadedPaths, ['axis_alpha_sfun.' mexext])));
            testCase.verifyTrue(any(endsWith(loadedPaths, ['axis_beta_sfun.' mexext])));
            fprintf('DUAL_MODEL_ISOLATION=PASS (both models and MEX files loaded)\n');
            clear loadedCleanup

            matlabExecutable = fullfile(matlabroot, 'bin', 'matlab.exe');
            pcFolder = fullfile(testCase.RepositoryRoot, 'tests', 'pc');
            for index = 1:2
                instance = project.instances(index);
                name = instance.internal_name;
                transcript = fullfile(testCase.WorkFolder, [name '_process.json']);
                expression = sprintf(['addpath(''%s''); ' ...
                    'run_simulink_case(''%s'',''%s'',%u,uint32(%u),''%s'',''%s'');'], ...
                    quote_matlab(pcFolder), ...
                    quote_matlab(fullfile(project.output.sfun_root, name)), ...
                    name, instance.iodevice.settings.tcp_port, ...
                    instance.interface_hash, quote_matlab(transcript), ...
                    quote_matlab(testCase.Python));
                [status, output] = system(sprintf('"%s" -batch "%s"', ...
                    matlabExecutable, strrep(expression, '"', '\"')));
                testCase.verifyEqual(status, 0, output);
                fprintf('SEPARATE_PROCESS_%s=PASS\n', ...
                    upper(extractAfter(name, 'axis_')));
            end

            scenarios = {'response_error', 'response_zero', 'wrong_type', ...
                'short_length', 'long_length', 'odd_length', 'wrong_step', ...
                'header_truncated', 'payload_truncated', 'timeout', 'disconnect'};
            alpha = project.instances(1);
            for index = 1:numel(scenarios)
                scenario = scenarios{index};
                transcript = fullfile(testCase.WorkFolder, ...
                    ['actual_' scenario '.json']);
                errorRun = run_simulink_case(fullfile(project.output.sfun_root, ...
                    alpha.internal_name), alpha.internal_name, ...
                    alpha.iodevice.settings.tcp_port, alpha.interface_hash, ...
                    transcript, testCase.Python, false, scenario);
                testCase.verifyNotEmpty(errorRun.failure);
                testCase.verifyEqual(errorRun.transcript.accepted_connection_count, 1);
                testCase.verifyEqual(errorRun.transcript.extra_reconnect_count, 0);
                testCase.verifyFalse(errorRun.transcript.sim_stop_observed);
                fprintf('NORMAL_SIMULINK_ERROR_%s=PASS\n', upper(scenario));
            end
        end
    end
end

function verify_mock_run(testCase, script, cacheFolder)
[status, output] = system(sprintf('"%s" "%s" 2>&1', ...
    testCase.Python, script));
testCase.verifyEqual(status, 0, output);
testCase.verifySubstring(output, ...
    'MOCK_REPEATABILITY=PASS scenarios=13 repeats=2');
testCase.verifyFalse(isfolder(cacheFolder), ...
    'Mock matrix created a repository Python cache.');
end

function project = integration_project(root)
project = c2837x_block_create_default_project();
project.common.network.ip = '127.0.0.1';
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
first = c2837x_block_create_default_instance();
first.display_name = 'Axis Alpha'; first.internal_name = 'axis_alpha';
types = {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'};
first.inputs = struct('name', strcat('input_', types), 'type', types, ...
    'dim', {2, 1, 1, 1, 1, 2});
first.outputs = struct('name', strcat('output_', types), 'type', types, ...
    'dim', {1, 1, 1, 1, 2, 1});
first.iodevice.settings.tcp_port = uint16(free_port());
second = first; second.display_name = 'Axis Beta'; second.internal_name = 'axis_beta';
for index = 1:6
    second.inputs(index).name = ['beta_' second.inputs(index).name];
    second.outputs(index).name = ['beta_' second.outputs(index).name];
end
second.iodevice.settings.socket_number = uint16(1);
second.iodevice.settings.tcp_port = uint16(free_port());
project.instances = [first second];
for index = 1:2
    [~, project.instances(index).interface_hash] = ...
        c2837x_block_build_interface_hash(project, index);
end
end

function port = free_port()
server = java.net.ServerSocket(0);
cleanup = onCleanup(@() server.close());
port = server.getLocalPort();
clear cleanup
end

function text = issue_text(issues)
if isempty(issues), text = ''; else, text = jsonencode(issues); end
end

function text = quote_matlab(text)
text = strrep(text, '''', '''''');
end

function close_models(models)
for index = 1:numel(models)
    if ~isempty(models{index}) && bdIsLoaded(models{index})
        close_system(models{index}, 0);
    end
end
clear axis_alpha_sfun axis_beta_sfun
end

function verify_foreign_loaded(testCase, project, root)
name = 'axis_alpha';
targetFolder = fullfile(project.output.sfun_root, name);
targetMex = fullfile(targetFolder, [name '_sfun.' mexext]);
targetBytes = read_bytes(targetMex);
foreignFolder = fullfile(root, 'foreign'); mkdir(foreignFolder);
foreignMex = fullfile(foreignFolder, [name '_sfun.' mexext]);
copyfile(targetMex, foreignMex);
oldPath = path; addpath(foreignFolder, '-begin'); clear axis_alpha_sfun
model = load_only_model(name);
cleanup = onCleanup(@() cleanup_loaded_model(model, oldPath, name));
[~, loaded] = inmem('-completenames');
testCase.verifyTrue(any(strcmpi(loaded, foreignMex)));
failure = captured_run(fullfile(targetFolder, 'build_axis_alpha_sfun.m'));
testCase.verifyEqual(failure.identifier, 'C2837xBlock:MexBuild:ForeignMexLoaded');
testCase.verifyEqual(read_bytes(targetMex), targetBytes);
testCase.verifyEqual(read_bytes(foreignMex), targetBytes);
fprintf('FOREIGN_LOADED_MEX_RUNTIME=PASS\n');
end

function verify_locked_rebuild(testCase, project)
name = 'axis_alpha';
folder = fullfile(project.output.sfun_root, name);
mexPath = fullfile(folder, [name '_sfun.' mexext]);
bytes = read_bytes(mexPath);
oldPath = path; addpath(folder, '-begin'); clear axis_alpha_sfun
model = load_only_model(name);
cleanup = onCleanup(@() cleanup_loaded_model(model, oldPath, name));
failure = captured_run(fullfile(folder, 'build_axis_alpha_sfun.m'));
if isempty(failure)
    testCase.verifyTrue(isfile(mexPath));
    fprintf(['REAL_LOCKED_SFUNCTION_REBUILD=INCOMPLETE ' ...
        '(updated model did not retain a MEX lock)\n']);
    return;
end
testCase.verifyTrue(strcmp(failure.identifier, ...
    'C2837xBlock:MexBuild:MexStillLoaded') || ...
    contains(failure.message, 'clear', 'IgnoreCase', true));
testCase.verifyEqual(read_bytes(mexPath), bytes);
fprintf('REAL_LOCKED_SFUNCTION_REBUILD=PASS identifier=%s\n', failure.identifier);
end

function model = load_only_model(name)
model = matlab.lang.makeValidName(['s406_loaded_' char(java.util.UUID.randomUUID)]);
new_system(model);
add_block('simulink/User-Defined Functions/S-Function', ...
    [model '/S-Function'], 'FunctionName', [name '_sfun']);
set_param(model, 'SimulationCommand', 'update');
end

function cleanup_loaded_model(model, oldPath, name)
if bdIsLoaded(model), close_system(model, 0); end
clear([name '_sfun']);
path(oldPath);
end

function failure = captured_run(scriptPath)
failure = [];
command = sprintf('run(''%s'')', strrep(scriptPath, '''', ''''''));
try
    evalc(command);
catch failure
end
end

function bytes = read_bytes(path)
file = fopen(path, 'rb'); assert(file >= 0);
cleanup = onCleanup(@() fclose(file));
bytes = reshape(fread(file, Inf, '*uint8'), 1, []);
clear cleanup
end
