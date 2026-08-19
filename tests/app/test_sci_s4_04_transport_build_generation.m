classdef test_sci_s4_04_transport_build_generation < matlab.unittest.TestCase
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
        function testW5300OutputContainsSocketOnly(testCase)
            project = build_project(testCase.WorkFolder);
            model = c2837x_block_build_sfun_output_model(project);
            files = model.files(1:11);
            names = file_names(files);

            testCase.verifyNumElements(files, 11);
            testCase.verifyEqual(names, expected_names('axis_socket', ...
                'pc_socket'));
            testCase.verifyFalse(any(contains(names, 'pc_serial.')));
            testCase.verifyEqual(sum(contains(names, 'pc_socket.')), 2);
        end

        function testSciCandidateContainsSerialOnlyAndIsSelfContained(testCase)
            project = build_project(testCase.WorkFolder);
            [candidates, dependencies] = ...
                c2837x_block_build_sfun_candidates(project);
            files = instance_candidates(candidates, 2);
            names = file_names(files);
            serialSource = candidate_text(files, 'axis_serial_pc_serial.c');
            serialHeader = candidate_text(files, 'axis_serial_pc_serial.h');
            protocolHeader = candidate_text(files, 'axis_serial_protocol.h');
            dependencyPaths = {dependencies.source_path};

            testCase.verifyNumElements(files, 11);
            testCase.verifyFalse(any(contains(names, 'pc_socket.')));
            testCase.verifyEqual(sum(contains(names, 'pc_serial.')), 2);
            testCase.verifySubstring(serialSource, ...
                '#include "axis_serial_pc_serial.h"');
            testCase.verifyEmpty(strfind(serialSource, ...
                'c2837x_block_pc_serial.h'));
            testCase.verifySubstring(serialHeader, ...
                '#include "axis_serial_pc_error.h"');
            testCase.verifyEmpty(strfind(serialHeader, ...
                'c2837x_block_pc_error.h'));
            testCase.verifySubstring(protocolHeader, ...
                '#include "axis_serial_pc_serial.h"');
            testCase.verifyEmpty(strfind(protocolHeader, ...
                'c2837x_block_pc_serial.h'));
            testCase.verifyFalse(contains(serialSource, repository_root()));
            testCase.verifyTrue(any(endsWith(dependencyPaths, ...
                fullfile('simulink', 'c2837x_block_pc_serial.c'))));
            testCase.verifyTrue(any(endsWith(dependencyPaths, ...
                fullfile('simulink', 'c2837x_block_pc_serial.h'))));
        end

        function testMixedGenerationIsDeterministicAndIsolated(testCase)
            project = build_project(testCase.WorkFolder);
            first = c2837x_block_build_sfun_candidates(project);
            second = c2837x_block_build_sfun_candidates(project);
            socketNames = file_names(instance_candidates(first, 1));
            serialNames = file_names(instance_candidates(first, 2));

            testCase.verifyEqual(second, first);
            testCase.verifyEqual(sum(contains(socketNames, 'pc_socket.')), 2);
            testCase.verifyFalse(any(contains(socketNames, 'pc_serial.')));
            testCase.verifyEqual(sum(contains(serialNames, 'pc_serial.')), 2);
            testCase.verifyFalse(any(contains(serialNames, 'pc_socket.')));
        end

        function testBuildScriptsUseExplicitTransportLists(testCase)
            project = build_project(testCase.WorkFolder);
            candidates = c2837x_block_build_sfun_candidates(project);
            w5300 = candidate_text(instance_candidates(candidates, 1), ...
                'build_axis_socket_sfun.m');
            sci = candidate_text(instance_candidates(candidates, 2), ...
                'build_axis_serial_sfun.m');

            testCase.verifySubstring(w5300, ...
                'fullfile(script_dir, ''axis_socket_pc_socket.c'')');
            testCase.verifyEmpty(strfind(w5300, 'pc_serial'));
            testCase.verifySubstring(w5300, 'ws2_32');
            testCase.verifyEmpty(strfind(w5300, 'dir(''*.c'')'));
            testCase.verifySubstring(sci, ...
                'fullfile(script_dir, ''axis_serial_pc_serial.c'')');
            testCase.verifySubstring(sci, ...
                'fullfile(script_dir, ''axis_serial_pc_serial.h'')');
            testCase.verifyEmpty(strfind(sci, 'pc_socket'));
            testCase.verifyEmpty(strfind(sci, 'ws2_32'));
            testCase.verifyEmpty(strfind(sci, 'dir(''*.c'')'));
            testCase.verifySubstring(sci, 'if ~ispc');
            testCase.verifySubstring(sci, ...
                'C2837xBlock:MexBuild:UnsupportedPlatform');
            verify_order(testCase, sci, {'required_files =', 'if ~ispc', ...
                '[~, mex_paths] = inmem', 'clear axis_serial_sfun', ...
                'delete(mex_path)', 'mex(mex_args{:})'});
        end

        function testSciPreflightPreservesExistingMex(testCase)
            testCase.assumeTrue(ispc, ...
                'SCI generated build is intentionally Windows-only.');
            project = build_project(testCase.WorkFolder);
            candidates = c2837x_block_build_sfun_candidates(project);
            write_candidates(candidates);
            instanceFolder = fullfile(project.output.sfun_root, 'axis_serial');
            buildScript = fullfile(instanceFolder, ...
                'build_axis_serial_sfun.m');
            missingHeader = fullfile(instanceFolder, ...
                'axis_serial_pc_serial.h');
            delete(missingHeader);
            mexPath = fullfile(instanceFolder, ...
                ['axis_serial_sfun.' mexext]);
            oldBytes = uint8('existing SCI target');
            write_bytes(mexPath, oldBytes);
            originalFolder = pwd;
            originalPath = path;
            originalEnvironment = getenv('PATH');

            failure = capture_failure(buildScript);

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
    end
end

function project = build_project(root)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));
first = c2837x_block_create_default_instance();
first.display_name = 'Axis Socket';
first.internal_name = 'axis_socket';
first.inputs = struct('name', 'command', 'type', 'uint16', 'dim', 1);
first.outputs = struct('name', 'feedback', 'type', 'uint16', 'dim', 1);
second = first;
second.display_name = 'Axis Serial';
second.internal_name = 'axis_serial';
second.iodevice = c2837x_block_create_iodevice('sci');
project.instances = [first second];
for index = 1:2
    [~, project.instances(index).interface_hash] = ...
        c2837x_block_build_interface_hash(project, index);
end
end

function names = expected_names(internalName, transport)
names = {[internalName '_sfun.c'], [internalName '_sfun.h'], ...
    [internalName '_sfun_io.c'], [internalName '_sfun_config.h'], ...
    [internalName '_sfun_user_config.h'], [internalName '_pc_error.h'], ...
    [internalName '_' transport '.c'], ...
    [internalName '_' transport '.h'], ...
    [internalName '_protocol.c'], [internalName '_protocol.h'], ...
    ['build_' internalName '_sfun.m']};
end

function names = file_names(files)
names = cell(1, numel(files));
for index = 1:numel(files)
    [~, name, extension] = fileparts(files(index).target_path);
    names{index} = [name extension];
end
end

function selected = instance_candidates(candidates, instanceIndex)
selected = candidates([candidates.instance_index] == instanceIndex);
end

function text = candidate_text(candidates, name)
selected = candidates(endsWith({candidates.target_path}, name));
assert(isscalar(selected));
text = native2unicode(selected.content_bytes, 'UTF-8');
end

function verify_order(testCase, text, tokens)
positions = cellfun(@(token) strfind(text, token), tokens, ...
    'UniformOutput', false);
testCase.assertTrue(all(cellfun(@(value) ~isempty(value), positions)));
testCase.verifyTrue(issorted(cellfun(@(value) value(1), positions)));
end

function write_candidates(candidates)
for index = 1:numel(candidates)
    folder = fileparts(candidates(index).target_path);
    if ~isfolder(folder)
        mkdir(folder);
    end
    write_bytes(candidates(index).target_path, candidates(index).content_bytes);
end
end

function write_bytes(path, bytes)
fileID = fopen(path, 'wb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fwrite(fileID, bytes, 'uint8');
clear cleanup
end

function bytes = read_bytes(path)
fileID = fopen(path, 'rb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
bytes = fread(fileID, Inf, '*uint8')';
clear cleanup
end

function failure = capture_failure(scriptPath)
failure = [];
try
    run(scriptPath);
catch cause
    failure = cause;
end
assert(~isempty(failure));
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
