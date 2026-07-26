function tests = test_s2_06_w5300_close
tests = functiontests(localfunctions);
end

function testCloseErratumStateMachine(testCase)
[status, output, executable] = compile_binary();
verifyEqual(testCase, status, 0, output);
[status, output] = system(sprintf('"%s"', executable));
verifyEqual(testCase, status, 0, output);
end

function testRunPathRemainsBoundedAndPrivate(testCase)
root = repository_root();
socket = fileread(fullfile(root, 'dsp', 'src', 'c2837x_w5300_socket.c'));
channel = fileread(fullfile(root, 'dsp', 'src', 'c2837x_w5300_channel.c'));
sources = [socket newline channel];
verifyEmpty(testCase, regexp(sources, ...
    '\bwhile\s*\(|\bdo\s*\{|\<DELAY_US\>|\<socket_send_to\>', 'once'));
verifyEmpty(testCase, regexp(sources, ...
    '\<(malloc|calloc|realloc|free)\s*\(', 'once'));
verifyEmpty(testCase, regexp(channel, ...
    '\<(SIPR|SUBR|GAR|SHAR)\>', 'once'));
core = fileread(fullfile(root, 'dsp', 'src', 'c2837x_block.c'));
verifyEmpty(testCase, regexp(core, 'C2837X_W5300_CLOSE_', 'once'));
end

function [status, output, executable] = compile_binary()
root = repository_root();
folder = fileparts(mfilename('fullpath'));
executable = fullfile(tempdir, 'w5300_close_erratum_test.exe');
command = sprintf([ ...
    'gcc -std=c11 -Wall -Wextra -Werror -Wno-unknown-pragmas ' ...
    '-Wno-int-to-pointer-cast -DC2837X_W5300_HOST_TEST ' ...
    '-I"%s" -I"%s" -I"%s" "%s" "%s" "%s" "%s" -o "%s" 2>&1'], ...
    fullfile(folder, 'include'), fullfile(root, 'dsp', 'inc'), ...
    fullfile(root, 'dsp', 'src'), ...
    fullfile(folder, 'w5300_close_erratum_test.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_hal.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_socket.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_channel.c'), executable);
[status, output] = system(command);
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
