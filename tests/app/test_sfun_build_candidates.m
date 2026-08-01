classdef test_sfun_build_candidates < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            repositoryRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repositoryRoot, 'app')));
        end
    end

    methods (TestMethodSetup)
        function createWorkFolder(testCase)
            testCase.WorkFolder = c2837x_block_normalize_absolute_path(tempname);
            mkdir(testCase.WorkFolder);
            testCase.addTeardown(@() rmdir(testCase.WorkFolder, 's'));
        end
    end

    methods (Test)
        function testOutputModelOrderCategoryAndOwner(testCase)
            model = c2837x_block_build_sfun_output_model( ...
                build_project(testCase.WorkFolder));

            testCase.verifyNumElements(model.files, 20);
            testCase.verifyEqual({model.files.relative_path}, expected_paths());
            testCase.verifyEqual([model.files.instance_index], ...
                [ones(1, 10) 2 * ones(1, 10)]);
            testCase.verifyEqual({model.files.category}, expected_categories());
            testCase.verifyNumElements(unique({model.files.owner}), 20);
            alphaUser = model.files(5);
            alphaBuild = model.files(10);
            testCase.verifyEqual(alphaUser.category, 'user');
            testCase.verifyEqual(alphaUser.owner, ...
                'sfun-instance:axis_alpha:axis_alpha/axis_alpha_sfun_user_config.h');
            testCase.verifyEqual(alphaBuild.category, 'auto_generated');
            testCase.verifyEqual(alphaBuild.owner, ...
                'sfun-instance:axis_alpha:axis_alpha/build_axis_alpha_sfun.m');
        end

        function testUserConfigContract(testCase)
            candidates = c2837x_block_build_sfun_candidates( ...
                build_project(testCase.WorkFolder));
            alpha = candidate_text(candidates, 'axis_alpha_sfun_user_config.h');
            beta = candidate_text(candidates, 'axis_beta_sfun_user_config.h');

            testCase.verifySubstring(alpha, 'USER-EDITABLE FILE');
            testCase.verifySubstring(alpha, '#define CONNECT_TIMEOUT_MS     5000u');
            testCase.verifySubstring(alpha, '#define STEP_TIMEOUT_MS        1000u');
            testCase.verifySubstring(alpha, '#define TERMINATE_TIMEOUT_MS    200u');
            testCase.verifyEqual(numel(regexp(alpha, '(?m)^#define\s+', 'match')), 4);
            testCase.verifyEmpty(regexpi(alpha, ...
                ['(IP_ADDRESS|TCP_PORT|PROTOCOL_VERSION|INTERFACE_HASH|PAYLOAD|' ...
                 'RETRY|RECONNECT|DSP_TIMEOUT|MEX_STATUS)'], 'once'));
            alphaGuard = regexp(alpha, '(?m)^#ifndef\s+(\w+)', 'tokens', 'once');
            betaGuard = regexp(beta, '(?m)^#ifndef\s+(\w+)', 'tokens', 'once');
            testCase.verifyNotEqual(alphaGuard{1}, betaGuard{1});
        end

        function testBuildScriptContractAndIsolation(testCase)
            candidates = c2837x_block_build_sfun_candidates( ...
                build_project(testCase.WorkFolder));
            alpha = candidate_text(candidates, 'build_axis_alpha_sfun.m');
            beta = candidate_text(candidates, 'build_axis_beta_sfun.m');

            testCase.verifySubstring(alpha, 'AUTO-GENERATED FILE');
            testCase.verifySubstring(alpha, 'mfilename(''fullpath'')');
            testCase.verifyEmpty(regexp(alpha, ...
                '(?m)\b(pwd|cd|addpath|rmpath|savepath|restoredefaultpath|setenv)\s*\(', 'once'));
            testCase.verifyEmpty(strfind(alpha, 'dir(''*.c'')'));
            testCase.verifyEqual(numel(regexp(alpha, ...
                'fullfile\(script_dir, ''axis_alpha_[^'']+\.c''\)', 'match')), 4);
            testCase.verifySubstring(alpha, '''-outdir'', script_dir');
            testCase.verifySubstring(alpha, '''-output'', mex_name');
            testCase.verifySubstring(alpha, ...
                'fullfile(compiler.Location,');
            testCase.verifySubstring(alpha, ...
                'mex_args{end + 1} = [''-L'' mingw_library_dir];');
            testCase.verifySubstring(alpha, ...
                '[~, mex_paths] = inmem(''-completenames'');');
            testCase.verifySubstring(alpha, ...
                '[~, mex_paths_after_clear] = inmem(''-completenames'');');
            testCase.verifyEmpty(regexp(alpha, ...
                '(?m)^\s*\w*paths\s*=\s*inmem\(', 'once'));
            testCase.verifySubstring(alpha, 'clear axis_alpha_sfun');
            testCase.verifySubstring(alpha, 'delete(mex_path)');
            testCase.verifySubstring(alpha, 'mex(mex_args{:})');
            testCase.verifyEqual(numel(strfind(alpha, 'mislocked(mex_name)')), 1);
            testCase.verifyEmpty(regexp(alpha, ...
                '(?m)^\s*clear\s+(mex|all)\s*$', 'once'));
            testCase.verifySubstring(alpha, 'MEX Name:');
            testCase.verifySubstring(alpha, 'MEX Path:');
            testCase.verifySubstring(alpha, 'Protocol Version: 1');
            testCase.verifySubstring(alpha, 'Interface Hash: 0x12345678');
            verify_order(testCase, alpha, {'required_files =', ...
                '[~, mex_paths] = inmem', 'foreign_paths =', ...
                'clear axis_alpha_sfun', '[~, mex_paths_after_clear] = inmem', ...
                'mislocked(mex_name)', 'delete(mex_path)', 'mex(mex_args{:})'});
            testCase.verifyEmpty(strfind(alpha, 'axis_beta'));
            testCase.verifyEmpty(strfind(beta, 'axis_alpha'));
            testCase.verifyEmpty(regexp([alpha beta], ...
                '(c2837x_block_.*\.c|manifest|\.bak|\.old)', 'once'));
        end

        function testUserKeepAndBuildReplaceDefaults(testCase)
            candidates = c2837x_block_build_sfun_candidates( ...
                build_project(testCase.WorkFolder));
            user = select_candidate(candidates, 'axis_alpha_sfun_user_config.h');
            build = select_candidate(candidates, 'build_axis_alpha_sfun.m');
            write_text(user.target_path, 'user edit');
            write_text(build.target_path, 'generated edit');

            comparisons = c2837x_block_compare_candidate_files([user build]);

            testCase.verifyEqual({comparisons.target_state}, ...
                {'different', 'different'});
            testCase.verifyEqual({comparisons.default_action}, {'keep', 'replace'});
            testCase.verifyEqual([comparisons.action_mandatory], [false true]);
        end

        function testGeneratedTextIsDeterministicUtf8Lf(testCase)
            project = build_project(testCase.WorkFolder);
            first = c2837x_block_build_sfun_candidates(project);
            second = c2837x_block_build_sfun_candidates(project);
            user = select_candidate(first, 'axis_alpha_sfun_user_config.h');
            build = select_candidate(first, 'build_axis_alpha_sfun.m');

            testCase.verifyEqual(second, first);
            verify_text_bytes(testCase, user.content_bytes);
            verify_text_bytes(testCase, build.content_bytes);
        end

        function testMissingHeaderPreflightPreservesTargetAndSession(testCase)
            project = build_project(testCase.WorkFolder);
            candidates = c2837x_block_build_sfun_candidates(project);
            write_candidates(candidates);
            instanceFolder = fullfile(project.output.sfun_root, 'axis_alpha');
            buildScript = fullfile(instanceFolder, 'build_axis_alpha_sfun.m');
            testCase.verifyEmpty(checkcode(buildScript, '-struct'));
            missingHeader = fullfile(instanceFolder, 'axis_alpha_sfun_user_config.h');
            delete(missingHeader);
            mexPath = fullfile(instanceFolder, ['axis_alpha_sfun.' mexext]);
            oldBytes = uint8('existing target');
            write_bytes(mexPath, oldBytes);
            unrelatedFolder = fullfile(testCase.WorkFolder, 'unrelated');
            mkdir(unrelatedFolder);
            testCase.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture( ...
                unrelatedFolder));
            originalFolder = pwd;
            originalPath = path;
            originalEnvironment = getenv('PATH');

            failure = captured_run(buildScript);

            testCase.verifyEqual(failure.identifier, ...
                'C2837xBlock:MexBuild:MissingFile');
            testCase.verifySubstring(failure.message, missingHeader);
            testCase.verifyEqual(read_bytes(mexPath), oldBytes);
            testCase.verifyEqual(pwd, originalFolder);
            testCase.verifyEqual(path, originalPath);
            testCase.verifyEqual(getenv('PATH'), originalEnvironment);
            testCase.verifyEmpty(dir(fullfile(instanceFolder, '*.tmp')));
            testCase.verifyEmpty(dir(fullfile(instanceFolder, '*.bak')));
            testCase.verifyEmpty(dir(fullfile(instanceFolder, '*.old')));
        end

        function testActualDualBuildAndFailureSemantics(testCase)
            project = build_project(testCase.WorkFolder);
            candidates = c2837x_block_build_sfun_candidates(project);
            write_candidates(candidates);
            simulinkInfo = ver('simulink');
            compiler = mex.getCompilerConfigurations('C', 'Selected');
            environmentReady = ~isMATLABReleaseOlderThan('R2024b') && ...
                ~isempty(simulinkInfo) && ~isempty(compiler);
            fprintf('MATLAB_VERSION=%s\n', version);
            if isempty(simulinkInfo)
                fprintf('SIMULINK_VERSION=UNAVAILABLE\n');
            else
                fprintf('SIMULINK_VERSION=%s\n', simulinkInfo.Version);
            end
            fprintf('COMPUTER=%s\n', computer);
            fprintf('MEXEXT=%s\n', mexext);
            if isempty(compiler)
                fprintf('C_MEX_COMPILER=NONE_SELECTED\n');
            else
                fprintf('C_MEX_COMPILER_NAME=%s\n', compiler.Name);
                fprintf('C_MEX_COMPILER_VERSION=%s\n', compiler.Version);
            end
            if ~environmentReady
                fprintf(2, 'S4-05_MEX_VALIDATION=BLOCKED\n');
            end
            testCase.assertTrue(environmentReady, ...
                ['MATLAB R2024b or newer, Simulink, and a selected supported ' ...
                 'C compiler are required. Run mex -setup C if needed.']);

            alphaFolder = fullfile(project.output.sfun_root, 'axis_alpha');
            betaFolder = fullfile(project.output.sfun_root, 'axis_beta');
            alphaScript = fullfile(alphaFolder, 'build_axis_alpha_sfun.m');
            betaScript = fullfile(betaFolder, 'build_axis_beta_sfun.m'); %#ok<NASGU>
            alphaMex = fullfile(alphaFolder, ['axis_alpha_sfun.' mexext]);
            betaMex = fullfile(betaFolder, ['axis_beta_sfun.' mexext]);
            unrelatedFolder = fullfile(testCase.WorkFolder, 'unrelated');
            mkdir(unrelatedFolder);
            testCase.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture( ...
                unrelatedFolder));
            originalFolder = pwd;
            originalPath = path;
            originalEnvironment = getenv('PATH');

            alphaLog = evalc('run(alphaScript)');
            betaLog = evalc('run(betaScript)');

            testCase.verifyTrue(isfile(alphaMex));
            testCase.verifyTrue(isfile(betaMex));
            testCase.verifyNotEqual(alphaMex, betaMex);
            testCase.verifyEmpty(dir(fullfile(unrelatedFolder, ['*.' mexext])));
            verify_session(testCase, originalFolder, originalPath, originalEnvironment);
            verify_build_log(testCase, alphaLog, alphaMex, project, 1);
            verify_build_log(testCase, betaLog, betaMex, project, 2);
            fprintf('ALPHA_MEX_PATH=%s\n', alphaMex);
            fprintf('BETA_MEX_PATH=%s\n', betaMex);

            alphaBytes = read_bytes(alphaMex);
            betaBytes = read_bytes(betaMex);
            missingHeader = fullfile(alphaFolder, 'axis_alpha_sfun_user_config.h');
            heldHeader = fullfile(testCase.WorkFolder, 'axis_alpha_sfun_user_config.h');
            movefile(missingHeader, heldHeader);
            headerCleanup = onCleanup(@() restore_file(heldHeader, missingHeader));

            preflightFailure = captured_run(alphaScript);

            testCase.verifyEqual(preflightFailure.identifier, ...
                'C2837xBlock:MexBuild:MissingFile');
            testCase.verifyEqual(read_bytes(alphaMex), alphaBytes);
            testCase.verifyEqual(read_bytes(betaMex), betaBytes);
            verify_no_backups(testCase, alphaFolder);
            verify_session(testCase, originalFolder, originalPath, originalEnvironment);
            fprintf('PREFLIGHT_OLD_ALPHA_BYTES_PRESERVED=%u\n', numel(alphaBytes));
            movefile(heldHeader, missingHeader);
            clear headerCleanup

            alphaSource = fullfile(alphaFolder, 'axis_alpha_sfun.c');
            sourceBytes = read_bytes(alphaSource);
            sourceCleanup = onCleanup(@() write_bytes(alphaSource, sourceBytes));
            compileError = unicode2native(sprintf( ...
                '#error "S4-05 deterministic compile failure"\n'), 'UTF-8');
            write_bytes(alphaSource, [reshape(compileError, 1, []) sourceBytes]);

            compileFailure = captured_run(alphaScript);

            testCase.verifyNotEmpty(compileFailure);
            testCase.verifySubstring(getReport(compileFailure, 'extended', ...
                'hyperlinks', 'off'), 'S4-05 deterministic compile failure');
            testCase.verifyFalse(isfile(alphaMex));
            testCase.verifyTrue(isfile(betaMex));
            testCase.verifyEqual(read_bytes(betaMex), betaBytes);
            verify_no_backups(testCase, alphaFolder);
            verify_session(testCase, originalFolder, originalPath, originalEnvironment);
            fprintf('COMPILE_FAILURE_ALPHA_MEX_EXISTS=0\n');
            fprintf('COMPILE_FAILURE_BETA_BYTES_PRESERVED=%u\n', numel(betaBytes));
            clear sourceCleanup

            fprintf(['FOREIGN_LOADED_MEX_RUNTIME=NOT_EXECUTED ' ...
                '(normal-mode S-Function loading requires Simulink)\n']);
            fprintf(['REAL_LOCKED_SFUNCTION_REBUILD=NOT_EXECUTED ' ...
                '(no real Simulink model run in S4-05)\n']);
        end
    end
end

function project = build_project(root)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
first = c2837x_block_create_default_instance();
first.display_name = 'Axis Alpha';
first.internal_name = 'axis_alpha';
first.inputs = struct('name', 'command', 'type', 'uint16', 'dim', 1);
first.outputs = struct('name', 'feedback', 'type', 'uint16', 'dim', 1);
second = first;
second.display_name = 'Axis Beta';
second.internal_name = 'axis_beta';
second.iodevice.settings.socket_number = uint16(1);
second.iodevice.settings.tcp_port = uint16(5001);
project.instances = [first second];
for index = 1:2
    [~, project.instances(index).interface_hash] = ...
        c2837x_block_build_interface_hash(project, index);
end
project.instances(1).interface_hash = uint32(hex2dec('12345678'));
end

function paths = expected_paths()
names = {'axis_alpha', 'axis_beta'};
paths = cell(1, 20);
for instanceIndex = 1:2
    name = names{instanceIndex};
    files = {[name '_sfun.c'], [name '_sfun.h'], [name '_sfun_io.c'], ...
        [name '_sfun_config.h'], [name '_sfun_user_config.h'], ...
        [name '_pc_socket.c'], [name '_pc_socket.h'], ...
        [name '_protocol.c'], [name '_protocol.h'], ['build_' name '_sfun.m']};
    for fileIndex = 1:10
        paths{(instanceIndex - 1) * 10 + fileIndex} = [name '/' files{fileIndex}];
    end
end
end

function categories = expected_categories()
perInstance = [repmat({'auto_generated'}, 1, 4), {'user'}, ...
    repmat({'auto_generated'}, 1, 5)];
categories = [perInstance perInstance];
end

function candidate = select_candidate(candidates, name)
candidate = candidates(endsWith({candidates.target_path}, name));
assert(isscalar(candidate));
end

function text = candidate_text(candidates, name)
candidate = select_candidate(candidates, name);
text = native2unicode(candidate.content_bytes, 'UTF-8');
end

function verify_order(testCase, text, tokens)
positions = cellfun(@(token) strfind(text, token), tokens, 'UniformOutput', false);
testCase.assertTrue(all(cellfun(@(value) ~isempty(value), positions)));
testCase.verifyTrue(issorted(cellfun(@(value) value(1), positions)));
end

function verify_text_bytes(testCase, bytes)
text = native2unicode(bytes, 'UTF-8');
testCase.verifyFalse(any(bytes == 13));
testCase.verifyFalse(numel(bytes) >= 3 && isequal(bytes(1:3), uint8([239 187 191])));
testCase.verifyEqual(bytes(end), uint8(10));
testCase.verifyNotEqual(bytes(end - 1), uint8(10));
testCase.verifyEmpty(regexp(text, '[ \t]+\n', 'once'));
testCase.verifyEmpty(regexpi(text, '(Generated on|timestamp|username|machine name)', 'once'));
end

function verify_build_log(testCase, output, mexPath, project, instanceIndex)
[~, mexName, mexExtension] = fileparts(mexPath);
testCase.verifySubstring(output, sprintf('MEX Name: %s%s', mexName, mexExtension));
testCase.verifySubstring(output, sprintf('MEX Path: %s', mexPath));
testCase.verifySubstring(output, sprintf('Protocol Version: %u', ...
    project.common.protocol_version));
testCase.verifySubstring(output, sprintf('Interface Hash: 0x%08X', ...
    project.instances(instanceIndex).interface_hash));
end

function verify_session(testCase, folder, matlabPath, environmentPath)
testCase.verifyEqual(pwd, folder);
testCase.verifyEqual(path, matlabPath);
testCase.verifyEqual(getenv('PATH'), environmentPath);
end

function verify_no_backups(testCase, folder)
testCase.verifyEmpty(dir(fullfile(folder, '*.bak')));
testCase.verifyEmpty(dir(fullfile(folder, '*.old')));
testCase.verifyFalse(isfolder(fullfile(folder, 'backup')));
end

function restore_file(source, destination)
if isfile(source)
    movefile(source, destination);
end
end

function write_text(path, text)
folder = fileparts(path);
if ~isfolder(folder), mkdir(folder); end
file = fopen(path, 'wb');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file));
fwrite(file, unicode2native([text newline], 'UTF-8'), 'uint8');
clear cleanup
end

function write_candidates(candidates)
for index = 1:numel(candidates)
    write_bytes(candidates(index).target_path, candidates(index).content_bytes);
end
end

function write_bytes(path, bytes)
folder = fileparts(path);
if ~isfolder(folder), mkdir(folder); end
file = fopen(path, 'wb');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file));
fwrite(file, bytes, 'uint8');
clear cleanup
end

function bytes = read_bytes(path)
file = fopen(path, 'rb');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file));
bytes = reshape(fread(file, Inf, '*uint8'), 1, []);
clear cleanup
end

function failure = captured_run(script)
failure = [];
try
    run(script);
catch failure
end
end
