function tests = test_s2_03_w5300_udp_send
tests = functiontests(localfunctions);
end

function testAtomicUdpDatagramTx(testCase)
[status, output, executable] = compile_binary();
verifyEqual(testCase, status, 0, output);
[status, output] = system(sprintf('"%s"', executable));
verifyEqual(testCase, status, 0, output);
end

function testUdpTxPrimitiveStaysSeparateAndBounded(testCase)
root = repository_root();
socket = fileread(fullfile(root, 'dsp', 'src', ...
    'c2837x_w5300_socket.c'));
udp = extract_c_function_body(socket, 'c2837x_w5300_socket_udp_send');
tcp = extract_c_function_body(socket, 'c2837x_w5300_socket_send');
verifyNotEmpty(testCase, regexp(socket, ...
    'c2837x_w5300_socket_udp_send\s*\(', 'once'));
verifyEmpty(testCase, regexp(udp, ...
    '\bwhile\s*\(|\bdo\s*\{|\<DELAY_US\>', 'once'));
verifyEmpty(testCase, regexp(udp, ...
    '\<c2837x_w5300_socket_send\s*\(', 'once'));
verifyNotEmpty(testCase, regexp(tcp, 'wire_byte_count\s*&=\s*~1u', ...
    'once'));
verifyEmpty(testCase, regexp(udp, 'wire_byte_count\s*&=\s*~1u', ...
    'once'));
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
executable = fullfile(tempdir, 'w5300_udp_send_test.exe');
command = sprintf([ ...
    'gcc -std=c11 -Wall -Wextra -Werror -Wno-unknown-pragmas ' ...
    '-Wno-int-to-pointer-cast -DC2837X_W5300_HOST_TEST ' ...
    '-I"%s" -I"%s" "%s" "%s" "%s" -o "%s" 2>&1'], ...
    fullfile(folder, 'include'), fullfile(root, 'dsp', 'inc'), ...
    fullfile(folder, 'w5300_udp_send_test.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_hal.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_w5300_socket.c'), executable);
[status, output] = system(command);
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
