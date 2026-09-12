classdef test_s3_01_w5300_udp_channel < matlab.unittest.TestCase
    methods (Test)
        function testUdpChannelLifecycleAndCandidate(testCase)
            executable = fullfile(tempdir, ...
                'w5300_udp_channel_test.exe');
            testCase.addTeardown(@() delete_if_exists(executable));
            [status, output] = compile_binary(executable);
            testCase.verifyEqual(status, 0, output);
            [status, output] = system(sprintf('"%s"', executable));
            testCase.verifyEqual(status, 0, output);
        end

        function testUdpChannelS301Scope(testCase)
            root = repository_root();
            header = fileread(fullfile(root, 'dsp', 'inc', ...
                'c2837x_w5300_udp_channel.h'));
            source = fileread(fullfile(root, 'dsp', 'src', ...
                'c2837x_w5300_udp_channel.c'));

            testCase.verifyNotEmpty(regexp(header, ...
                'C2837xW5300UdpChannel', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'c2837x_w5300_socket_udp_open\s*\(', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'c2837x_w5300_socket_udp_read_packet_info\s*\(', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'c2837x_w5300_socket_udp_read_data\s*\(', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'c2837x_w5300_socket_udp_drop_data\s*\(', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'c2837x_w5300_socket_udp_commit_recv\s*\(', 'once'));
            testCase.verifyFalse(contains(source, ...
                'c2837x_w5300_socket_listen'));
            testCase.verifyFalse(contains(source, 'Sn_CR_LISTEN'));
            testCase.verifyFalse(contains(source, 'SIM_START'));
            testCase.verifyFalse(contains(source, 'Message'));
            testCase.verifyFalse(contains(source, 'Protocol'));
            testCase.verifyFalse(contains(source, ...
                'c2837x_w5300_socket_check_close_erratum'));
            testCase.verifyFalse(contains(source, ...
                'c2837x_w5300_socket_dummy_tx_ready'));
            testCase.verifyFalse(contains(source, ...
                'c2837x_w5300_socket_issue_udp_open'));
            testCase.verifyFalse(contains(source, ...
                'c2837x_w5300_socket_issue_dummy_send'));
            testCase.verifyFalse(contains(source, 'while'));
            testCase.verifyFalse(contains(source, 'do {'));
            testCase.verifyFalse(contains(source, 'DELAY_US'));
            testCase.verifyFalse(contains(source, 'malloc'));
            testCase.verifyFalse(contains(source, 'calloc'));
            testCase.verifyFalse(contains(source, 'realloc'));
            testCase.verifyFalse(contains(source, 'free('));

            stateBody = extract_c_function_body(source, ...
                'get_connection_state');
            testCase.verifyFalse(contains(stateBody, ...
                'c2837x_w5300_socket_udp_read_data'));
            testCase.verifyFalse(contains(stateBody, ...
                'c2837x_w5300_read_stream'));
            testCase.verifyFalse(contains(stateBody, ...
                'C2837xBlock_Protocol'));
            testCase.verifyFalse(contains(stateBody, 'SIM_START'));
        end
    end
end

function body = extract_c_function_body(source, functionName)
pattern = ['(?m)^\s*(?:static\s+)?(?:C2837xBlock_IoConnectionState|int16|int32|void)\s+' ...
    functionName '\s*\([^;]*\)\s*\{'];
[~, signatureEnd] = regexp(source, pattern, 'once');
if isempty(signatureEnd)
    error('C function definition not found: %s', functionName);
end

depth = 1;
for index = signatureEnd + 1:numel(source)
    if source(index) == '{'
        depth = depth + 1;
    elseif source(index) == '}'
        depth = depth - 1;
        if depth == 0
            body = source(signatureEnd + 1:index - 1);
            return;
        end
    end
end
error('Unbalanced C function body: %s', functionName);
end

function [status, output] = compile_binary(executable)
root = repository_root();
folder = fileparts(mfilename('fullpath'));
command = sprintf([ ...
    'gcc -std=c11 -Wall -Wextra -Werror -Wno-unknown-pragmas ' ...
    '-Wno-int-to-pointer-cast -DC2837X_W5300_HOST_TEST ' ...
    '-I"%s" -I"%s" -I"%s" "%s" "%s" "%s" "%s" -o "%s" 2>&1'], ...
    fullfile(folder, 'include'), fullfile(root, 'dsp', 'inc'), ...
    fullfile(root, 'dsp', 'src'), ...
    fullfile(folder, 'w5300_udp_channel_test.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_hal.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_socket.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_udp_channel.c'), executable);
[status, output] = system(command);
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end

function delete_if_exists(path)
if isfile(path)
    delete(path);
end
end
