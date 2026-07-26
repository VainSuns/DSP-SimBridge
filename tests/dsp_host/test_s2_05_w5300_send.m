function tests = test_s2_05_w5300_send
tests = functiontests(localfunctions);
end

function testSendCompletionSemantics(testCase)
[status, output, executable] = compile_binary();
verifyEqual(testCase, status, 0, output);
[status, output] = system(sprintf('"%s"', executable));
verifyEqual(testCase, status, 0, output);
end

function testCoreCommitsOnlyPositiveProgress(testCase)
root = repository_root();
source = fileread(fullfile(root, 'dsp', 'src', 'c2837x_block.c'));
zeroBranch = regexp(source, ...
    'if\s*\(sent_octets\s*==\s*0\)(?<body>[\s\S]*?return\s*;\s*\})', ...
    'names', 'once');
verifyNotEmpty(testCase, zeroBranch);
verifyEmpty(testCase, regexp(zeroBranch.body, ...
    'tx_sent_octets\s*\+=|tx_done_action\s*=|expected_step_index\s*\+\+', ...
    'once'));
verifyNotEmpty(testCase, regexp(zeroBranch.body, 'return\s*;', 'once'));
end

function testRunSourcesRemainBoundedAndS205Scoped(testCase)
root = repository_root();
socket = fileread(fullfile(root, 'dsp', 'src', 'c2837x_w5300_socket.c'));
channel = fileread(fullfile(root, 'dsp', 'src', 'c2837x_w5300_channel.c'));
sources = [socket newline channel];
verifyEmpty(testCase, regexp(sources, ...
    '\bwhile\s*\(|\bdo\s*\{|\<DELAY_US\>|\<socket_send_to\>', 'once'));
verifyEmpty(testCase, regexp(sources, ...
    '\<(malloc|calloc|realloc|free)\s*\(', 'once'));
end

function [status, output, executable] = compile_binary()
root = repository_root();
folder = fileparts(mfilename('fullpath'));
executable = fullfile(tempdir, 'w5300_send_completion_test.exe');
command = sprintf([ ...
    'gcc -std=c11 -Wall -Wextra -Werror -Wno-unknown-pragmas ' ...
    '-Wno-int-to-pointer-cast -DC2837X_W5300_HOST_TEST ' ...
    '-I"%s" -I"%s" -I"%s" "%s" "%s" "%s" "%s" -o "%s" 2>&1'], ...
    fullfile(folder, 'include'), fullfile(root, 'dsp', 'inc'), ...
    fullfile(root, 'dsp', 'src'), ...
    fullfile(folder, 'w5300_send_completion_test.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_hal.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_socket.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_channel.c'), executable);
[status, output] = system(command);
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
