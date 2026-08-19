classdef test_sci_s4_05_software_loop < matlab.unittest.TestCase
    properties
        RepositoryRoot
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            testCase.RepositoryRoot = fileparts(fileparts(fileparts( ...
                mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'app')));
        end
    end

    methods (Test)
        function testDirectProductionSoftwareLoop(testCase)
            evidence = run_production_loop(testCase, testCase.RepositoryRoot);
            fprintf('%s', evidence.output);
            testCase.verifyEqual(evidence.status, 0, evidence.output);
            testCase.verifySubstring(evidence.output, ...
                'SCI_PRODUCTION_LOOP happy_path=PASS');
            testCase.verifySubstring(evidence.output, ...
                'SCI_PRODUCTION_LOOP deadline_timeout=PASS');
            testCase.verifySubstring(evidence.output, ...
                'SCI_PRODUCTION_LOOP serial_error=PASS');
            testCase.verifySubstring(evidence.output, ...
                'SCI_PRODUCTION_LOOP protocol_error=PASS');
            testCase.verifySubstring(evidence.output, ...
                'SUMMARY passed=4 failed=0');
        end

        function testGeneratedSciMexBuild(testCase)
            evidence = run_generated_sci_mex(testCase);
            fprintf('%s', evidence.output);
            verify_mex_evidence(testCase, evidence);
        end
    end
end

function evidence = run_production_loop(testCase, repositoryRoot)
root = c2837x_block_normalize_absolute_path(tempname);
mkdir(root);
testCase.addTeardown(@() rmdir(root, 's'));
project = representative_project(root);
sfun = c2837x_block_render_sfun_files(project);
pc = c2837x_block_render_pc_files(project);
generated = fullfile(root, 'generated');
mkdir(generated);
write_bytes(fullfile(generated, 'axis_alpha_protocol.c'), ...
    pc.protocol_source_bytes);
write_bytes(fullfile(generated, 'axis_alpha_protocol.h'), ...
    pc.protocol_header_bytes);
write_bytes(fullfile(generated, 'axis_alpha_pc_serial.c'), ...
    pc.serial_source_bytes);
write_bytes(fullfile(generated, 'axis_alpha_pc_serial.h'), ...
    pc.serial_header_bytes);
write_bytes(fullfile(generated, 'axis_alpha_pc_error.h'), ...
    pc.pc_error_header_bytes);
write_bytes(fullfile(generated, 'axis_alpha_sfun_config.h'), ...
    sfun.config_header_bytes);

gcc = 'E:\\Mingw_w64\\mingw64\\bin\\gcc.exe';
testCase.assertTrue(isfile(gcc), 'The configured MinGW gcc is required.');
fixture = fullfile(repositoryRoot, 'tests', 'app', 'support', 'sci_s4_05', ...
    'sci_production_loop_fixture.c');
executable = fullfile(root, 'sci_production_loop_fixture.exe');
command = sprintf([ ...
    '"%s" -std=c11 -Wall -Wextra -Werror -Wno-unused-function ' ...
    '-pedantic-errors -DC2837X_PC_SERIAL_TEST_SEAM -I"%s" ' ...
    '"%s" "%s" "%s" -o "%s" 2>&1'], gcc, generated, ...
    fullfile(generated, 'axis_alpha_protocol.c'), ...
    fullfile(generated, 'axis_alpha_pc_serial.c'), fixture, executable);
[compileStatus, compileOutput] = system(command);
runCommand = sprintf('"%s" 2>&1', executable);
if compileStatus == 0
    [runStatus, runOutput] = system(runCommand);
else
    runStatus = compileStatus;
    runOutput = 'fixture execution skipped because compilation failed';
end
evidence = struct('status', runStatus, 'output', sprintf([ ...
    'COMPILE_COMMAND: %s\n%s\n' ...
    'GENERATED_PROTOCOL_SOURCE: %s\n' ...
    'GENERATED_SERIAL_SOURCE: %s\n' ...
    'FIXTURE_SOURCE: %s\n' ...
    'RUN_COMMAND: %s\n%s'], command, compileOutput, ...
    fullfile(generated, 'axis_alpha_protocol.c'), ...
    fullfile(generated, 'axis_alpha_pc_serial.c'), fixture, runCommand, ...
    runOutput));
end

function evidence = run_generated_sci_mex(testCase)
compiler = mex.getCompilerConfigurations('C', 'Selected');
simulinkInfo = ver('simulink');
evidence = struct('status', '', 'compiler_selected', ~isempty(compiler), ...
    'mex_exists', false, 'output', '');
if isempty(compiler)
    evidence.status = 'NOT_EXECUTED / CAPABILITY';
    evidence.output = sprintf([ ...
        'MATLAB_VERSION=%s\nSIMULINK_VERSION=%s\nCOMPUTER=%s\n' ...
        'MEXEXT=%s\nC_MEX_COMPILER=NONE_SELECTED\n' ...
        'SCI_MEX_BUILD=NOT_EXECUTED / CAPABILITY\n'], ...
        version, simulinkInfo.Version, computer, mexext);
    return
end

root = c2837x_block_normalize_absolute_path(tempname);
mkdir(root);
testCase.addTeardown(@() rmdir(root, 's'));
project = representative_project(root);
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));
[candidates, ~, issues] = c2837x_block_build_sfun_candidates(project);
testCase.assertEmpty(issues);
write_candidates(candidates);

instanceFolder = fullfile(project.output.sfun_root, 'axis_alpha');
buildScript = fullfile(instanceFolder, 'build_axis_alpha_sfun.m');
mexPath = fullfile(instanceFolder, ['axis_alpha_sfun.' mexext]);
scriptText = native2unicode(candidate_bytes(candidates, ...
    'build_axis_alpha_sfun.m'), 'UTF-8');
testCase.assertTrue(contains(scriptText, ...
    'fullfile(script_dir, ''axis_alpha_pc_serial.c'')'));
testCase.assertEmpty(strfind(scriptText, 'pc_socket'));
testCase.assertEmpty(strfind(scriptText, 'ws2_32'));
originalFolder = pwd;
originalPath = path;
originalEnvironment = getenv('PATH');
buildLog = evalc('run(buildScript)');
sameSession = isequal(pwd, originalFolder) && isequal(path, originalPath) && ...
    isequal(getenv('PATH'), originalEnvironment);
evidence.status = 0;
evidence.mex_exists = isfile(mexPath);
evidence.output = sprintf([ ...
    'MATLAB_VERSION=%s\nSIMULINK_VERSION=%s\nCOMPUTER=%s\n' ...
    'MEXEXT=%s\nC_MEX_COMPILER=%s\n' ...
    'C_MEX_COMPILER_VERSION=%s\n' ...
    'MEX_BUILD_SCRIPT: %s\n' ...
    'SOURCE_LIST: axis_alpha_sfun.c axis_alpha_sfun_io.c ' ...
    'axis_alpha_pc_serial.c axis_alpha_protocol.c\n' ...
    'MEX_PATH: %s\nMEX_OUTPUT_EXISTS=%d\n' ...
    'SESSION_PATH_PWD_PRESERVED=%d\nBUILD_LOG:\n%s'], ...
    version, simulinkInfo.Version, computer, mexext, compiler.Name, ...
    compiler.Version, buildScript, mexPath, evidence.mex_exists, ...
    sameSession, buildLog);
if ~evidence.mex_exists || ~sameSession
    evidence.status = 1;
end
end

function verify_mex_evidence(testCase, evidence)
if strcmp(evidence.status, 'NOT_EXECUTED / CAPABILITY')
    testCase.verifyFalse(evidence.compiler_selected, evidence.output);
    testCase.verifySubstring(evidence.output, ...
        'C_MEX_COMPILER=NONE_SELECTED');
    return
end
testCase.verifyEqual(evidence.status, 0, evidence.output);
testCase.verifyTrue(evidence.compiler_selected, evidence.output);
testCase.verifyTrue(evidence.mex_exists, evidence.output);
testCase.verifySubstring(evidence.output, ...
    'axis_alpha_pc_serial.c');
testCase.verifyEmpty(strfind(evidence.output, 'pc_socket'));
testCase.verifyEmpty(strfind(evidence.output, 'ws2_32'));
testCase.verifySubstring(evidence.output, ...
    'SESSION_PATH_PWD_PRESERVED=1');
end

function project = representative_project(root)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));
instance = c2837x_block_create_default_instance();
instance.display_name = 'Axis Alpha';
instance.internal_name = 'axis_alpha';
instance.inputs = struct('name', 'command', 'type', 'uint16', 'dim', 1);
instance.outputs = struct('name', 'feedback', 'type', 'uint16', 'dim', 1);
instance.iodevice = c2837x_block_create_iodevice('sci');
instance.iodevice.settings.module = 'SCI-B';
instance.iodevice.settings.rx_gpio = 'GPIO19';
instance.iodevice.settings.tx_gpio = 'GPIO14';
instance.iodevice.settings.baud = uint32(115200);
project.instances = instance;
[~, project.instances.interface_hash] = ...
    c2837x_block_build_interface_hash(project, 1);
end

function bytes = candidate_bytes(candidates, suffix)
matches = endsWith({candidates.target_path}, suffix);
assert(nnz(matches) == 1);
bytes = candidates(matches).content_bytes;
end

function write_candidates(candidates)
for index = 1:numel(candidates)
    write_bytes(candidates(index).target_path, candidates(index).content_bytes);
end
end

function write_bytes(path, bytes)
folder = fileparts(path);
if ~isfolder(folder)
    mkdir(folder);
end
file = fopen(path, 'wb');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file));
fwrite(file, bytes, 'uint8');
clear cleanup
end
