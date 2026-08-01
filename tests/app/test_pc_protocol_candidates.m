classdef test_pc_protocol_candidates < matlab.unittest.TestCase
    properties
        WorkFolder
        RepositoryRoot
        Candidates
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            testCase.RepositoryRoot = fileparts(fileparts(fileparts( ...
                mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'app')));
        end
    end

    methods (TestMethodSetup)
        function createCandidates(testCase)
            testCase.WorkFolder = c2837x_block_normalize_absolute_path(tempname);
            mkdir(testCase.WorkFolder);
            testCase.addTeardown(@() rmdir(testCase.WorkFolder, 's'));
            project = two_instance_project(testCase.WorkFolder);
            testCase.Candidates = c2837x_block_build_sfun_candidates(project);
            write_candidates(testCase.Candidates);
        end
    end

    methods (Test)
        function testTenFilesPerInstanceAndDeterminism(testCase)
            project = two_instance_project(testCase.WorkFolder);
            second = c2837x_block_build_sfun_candidates(project);
            testCase.verifyEqual(second, testCase.Candidates);
            for instance = 1:2
                selected = testCase.Candidates( ...
                    [testCase.Candidates.instance_index] == instance);
                testCase.verifyNumElements(selected, 10);
                names = candidate_names(selected);
                testCase.verifyEqual(sum(contains(names, '_protocol.')), 2);
                testCase.verifyEqual(sum(contains(names, '_pc_socket.')), 2);
                testCase.verifyEqual(sum(contains(names, '_sfun_user_config.h')), 1);
                testCase.verifyEqual(sum(startsWith(names, 'build_')), 1);
            end
        end

        function testHostCompileAndExternalSymbolIsolation(testCase)
            alpha = compile_pc(testCase, 1);
            beta = compile_pc(testCase, 2);
            testCase.verifyTrue(all(startsWith(alpha.symbols, 'axis_alpha_')));
            testCase.verifyTrue(all(startsWith(beta.symbols, 'axis_beta_')));
            testCase.verifyEmpty(intersect(alpha.symbols, beta.symbols));
            testCase.verifyEmpty(alpha.dataSymbols);
            testCase.verifyEmpty(beta.dataSymbols);
            testCase.verifyFalse(any(startsWith(alpha.symbols, 'c2837x_')));
            alphaMacros = pc_macros(testCase.Candidates, 1);
            betaMacros = pc_macros(testCase.Candidates, 2);
            testCase.verifyEmpty(intersect(alphaMacros, betaMacros));
        end

        function testPosixFeatureMacroPrecedesAllIncludes(testCase)
            for instance = 1:2
                selected = testCase.Candidates( ...
                    [testCase.Candidates.instance_index] == instance & ...
                    endsWith({testCase.Candidates.target_path}, '_pc_socket.c'));
                testCase.assertNumElements(selected, 1);
                text = native2unicode(selected.content_bytes, 'UTF-8');
                macroPosition = strfind(text, '#define _POSIX_C_SOURCE 200809L');
                includePosition = regexp(text, '(?m)^#include\s', 'once');
                testCase.verifyTrue(isscalar(macroPosition) && ...
                    macroPosition < includePosition);
            end
            if ispc
                fprintf('POSIX_STRICT_COMPILE=NOT_EXECUTED (Windows host)\n');
            else
                fprintf('POSIX_STRICT_COMPILE=PASS (actual candidates)\n');
            end
        end

        function testFocusedMockTcpAndGoldenVectors(testCase)
            folder = instance_folder(testCase.Candidates, 1);
            if ispc
                executable = fullfile(testCase.WorkFolder, 's4_02_client.exe');
                socketLibrary = '-lws2_32';
            else
                executable = fullfile(testCase.WorkFolder, 's4_02_client');
                socketLibrary = '';
            end
            support = fullfile(testCase.RepositoryRoot, 'tests', 'app', 'support');
            command = sprintf([ ...
                'gcc -std=c11 -Wall -Wextra -Werror -pedantic-errors -I"%s" "%s" "%s" ' ...
                '"%s" -o "%s" %s 2>&1'], folder, ...
                fullfile(folder, 'axis_alpha_pc_socket.c'), ...
                fullfile(folder, 'axis_alpha_protocol.c'), ...
                fullfile(support, 's4_02_client.c'), executable, socketLibrary);
            [status, output] = system(command);
            testCase.assertEqual(status, 0, output);
            python = pyenv;
            testCase.assertTrue(isfile(python.Executable), ...
                'A configured Python executable is required for this focused test.');
            command = sprintf('"%s" "%s" "%s" "%s" 2>&1', ...
                python.Executable, fullfile(support, 'run_s4_02_mock_tcp.py'), ...
                executable, folder);
            [status, output] = system(command);
            testCase.verifyEqual(status, 0, output);
            testCase.verifySubstring(output, 'SUMMARY passed=24 failed=0');
        end
    end
end

function project = two_instance_project(root)
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
end

function write_candidates(candidates)
for index = 1:numel(candidates)
    folder = fileparts(candidates(index).target_path);
    if ~isfolder(folder), mkdir(folder); end
    fileID = fopen(candidates(index).target_path, 'wb');
    assert(fileID >= 0);
    cleanup = onCleanup(@() fclose(fileID));
    fwrite(fileID, candidates(index).content_bytes, 'uint8');
    clear cleanup
end
end

function names = candidate_names(candidates)
names = cell(size(candidates));
for index = 1:numel(candidates)
    [~, name, extension] = fileparts(candidates(index).target_path);
    names{index} = [name extension];
end
end

function folder = instance_folder(candidates, instance)
selected = candidates([candidates.instance_index] == instance);
folder = fileparts(selected(1).target_path);
end

function result = compile_pc(testCase, instance)
folder = instance_folder(testCase.Candidates, instance);
[~, name] = fileparts(folder);
sources = {fullfile(folder, [name '_pc_socket.c']), ...
    fullfile(folder, [name '_protocol.c'])};
objects = {fullfile(folder, 'socket.o'), fullfile(folder, 'protocol.o')};
for index = 1:2
    [status, output] = system(sprintf( ...
        'gcc -std=c11 -Wall -Wextra -Werror -pedantic-errors -I"%s" -c "%s" -o "%s" 2>&1', ...
        folder, sources{index}, objects{index}));
    testCase.assertEqual(status, 0, output);
end
[status, output] = system(sprintf('nm -g --defined-only "%s" "%s" 2>&1', ...
    objects{1}, objects{2}));
testCase.assertEqual(status, 0, output);
tokens = regexp(output, '(?m)^[0-9A-Fa-f]+\s+([A-Za-z])\s+(_?[A-Za-z]\w*)\s*$', ...
    'tokens');
types = cellfun(@(token) token{1}, tokens, 'UniformOutput', false);
symbols = cellfun(@(token) regexprep(token{2}, '^_', ''), tokens, ...
    'UniformOutput', false);
result = struct('symbols', {symbols}, ...
    'dataSymbols', {symbols(ismember(upper(types), {'B', 'C', 'D', 'G', 'S'}))});
end

function macros = pc_macros(candidates, instance)
selected = candidates([candidates.instance_index] == instance & ...
    contains({candidates.target_path}, {'_protocol.', '_pc_socket.'}));
text = '';
for index = 1:numel(selected)
    text = [text native2unicode(selected(index).content_bytes, 'UTF-8')]; %#ok<AGROW>
end
tokens = regexp(text, '(?m)^#define\s+([A-Za-z_]\w*)', 'tokens');
macros = unique(cellfun(@(token) token{1}, tokens, 'UniformOutput', false));
macros(strcmp(macros, '_POSIX_C_SOURCE')) = [];
end
