function tests = test_s2_04_w5300_nonblocking
tests = functiontests(localfunctions);
end

function testBoundedHalAndSocketOperations(testCase)
[status, output, executable] = compile_binary();
verifyEqual(testCase, status, 0, output);
[status, output] = system(sprintf('"%s"', executable));
verifyEqual(testCase, status, 0, output);
end

function testRunReachableSourcesHaveNoWaitLoops(testCase)
root = repository_root();
hal = fileread(fullfile(root, 'dsp', 'src', 'c2837x_w5300_hal.c'));
socket = fileread(fullfile(root, 'dsp', 'src', 'c2837x_w5300_socket.c'));
channel = fileread(fullfile(root, 'dsp', 'src', 'c2837x_w5300_channel.c'));
runSources = [hal newline socket newline channel];

verifyEmpty(testCase, regexp(runSources, ...
    '\<c2837x_w5300_set_sn_cr\>|\<c2837x_w5300_socket_send_to\>', 'once'));
verifyEmpty(testCase, regexp(socket, ...
    '\<DELAY_US\>|\bwhile\s*\(|\bdo\s*\{', 'once'));
verifyEmpty(testCase, regexp([socket newline channel], ...
    '\<(malloc|calloc|realloc|free)\s*\(', 'once'));
verifyNotEmpty(testCase, regexp(hal, ...
    'for\s*\([^;]+;[^;]+C2837X_W5300_STABLE_READ_ATTEMPTS', 'once'));
verifyEmpty(testCase, regexp(hal, '\bwhile\s*\(|\bdo\s*\{', 'once'));
end

function testHotPathDoesNotUseGenericSocketValidation(testCase)
root = repository_root();
socket = fileread(fullfile(root, 'dsp', 'src', 'c2837x_w5300_socket.c'));
hotFunctions = { ...
    'c2837x_w5300_socket_send', ...
    'c2837x_w5300_socket_recv', ...
    'c2837x_w5300_socket_advance_send_command', ...
    'c2837x_w5300_socket_advance_recv_command'};

for index = 1:numel(hotFunctions)
    body = extract_c_function_body(socket, hotFunctions{index});
    verifyEmpty(testCase, regexp(body, 'socket_is_valid\s*\(', 'once'));
end

openBody = extract_c_function_body(socket, 'c2837x_w5300_socket_open');
closeBody = extract_c_function_body(socket, ...
    'c2837x_w5300_socket_complete_close_command');
verifyNotEmpty(testCase, regexp([openBody closeBody], ...
    'socket_is_valid\s*\(', 'once'));
end

function body = extract_c_function_body(source, functionName)
pattern = ['(?m)^\s*(?:static\s+)?(?:int16|int32|void)\s+' ...
    functionName '\s*\([^;]*\)\s*\{'];
[~, signatureEnd] = regexp(source, pattern, 'once');
assert(~isempty(signatureEnd), ...
    'C function definition not found: %s', functionName);

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

function [status, output, executable] = compile_binary()
root = repository_root();
folder = fileparts(mfilename('fullpath'));
executable = fullfile(tempdir, 'w5300_nonblocking_test.exe');
command = sprintf([ ...
    'gcc -std=c11 -Wall -Wextra -Werror -Wno-unknown-pragmas ' ...
    '-Wno-int-to-pointer-cast -DC2837X_W5300_HOST_TEST ' ...
    '-I"%s" -I"%s" "%s" "%s" "%s" -o "%s" 2>&1'], ...
    fullfile(folder, 'include'), fullfile(root, 'dsp', 'inc'), ...
    fullfile(folder, 'w5300_nonblocking_test.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_hal.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_socket.c'), executable);
[status, output] = system(command);
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
