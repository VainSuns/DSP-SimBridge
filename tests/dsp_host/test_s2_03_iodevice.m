function tests = test_s2_03_iodevice
tests = functiontests(localfunctions);
end

function testCoreLinksAndRunsWithFakeIoDeviceOnly(testCase)
[status, output, executable] = compile_binary('core_instance_test.c', ...
    {'c2837x_block.c'});
verifyEqual(testCase, status, 0, output);
[status, output] = system(sprintf('"%s"', executable));
verifyEqual(testCase, status, 0, output);
end

function testW5300ChannelsAreIndependent(testCase)
[status, output, executable] = compile_binary('w5300_channel_test.c', ...
    {'c2837x_w5300_channel.c'});
verifyEqual(testCase, status, 0, output);
[status, output] = system(sprintf('"%s"', executable));
verifyEqual(testCase, status, 0, output);
end

function testCoreHasNoW5300Dependency(testCase)
root = repository_root();
paths = {fullfile(root, 'dsp', 'src', 'c2837x_block.c'), ...
         fullfile(root, 'dsp', 'src', 'c2837x_block_internal.h')};
source = [fileread(paths{1}) newline fileread(paths{2})];
for pattern = { 'c2837x_w5300', 'C2837xW5300Socket', ...
        'C2837X_W5300_', '\<SOCK_', '\<Sn_' }
    verifyEmpty(testCase, regexp(source, pattern{1}, 'once'), pattern{1});
end
end

function testIoDeviceContractIsInternalAndStatic(testCase)
root = repository_root();
header = fileread(fullfile(root, 'dsp', 'inc', 'c2837x_block_iodevice.h'));
publicHeader = fileread(fullfile(root, 'dsp', 'inc', 'c2837x_block.h'));
source = fileread(fullfile(root, 'dsp', 'src', 'c2837x_block.c'));
for operation = {'channel_init', 'open', 'listen', ...
        'get_connection_state', 'receive', 'send', 'close'}
    verifyNotEmpty(testCase, regexp(header, operation{1}, 'once'));
end
verifyEmpty(testCase, regexp(header, 'PlatformInit', 'once'));
verifyEmpty(testCase, regexp(publicHeader, 'IoDevice|void\s*\*', 'once'));
verifyEmpty(testCase, regexp([header source], ...
    '\<(malloc|calloc|realloc|free)\s*\(', 'once'));
end

function [status, output, executable] = compile_binary(fixture, sources)
root = repository_root();
folder = fileparts(mfilename('fullpath'));
[~, stem] = fileparts(fixture);
executable = fullfile(tempdir, [stem '.exe']);
sourceArgs = cellfun(@(name) sprintf('"%s"', ...
    fullfile(root, 'dsp', 'src', name)), sources, 'UniformOutput', false);
command = sprintf(['gcc -std=c11 -Wall -Wextra -Werror -I"%s" -I"%s" -I"%s" ' ...
    '"%s" %s -o "%s" 2>&1'], fullfile(folder, 'include'), ...
    fullfile(root, 'dsp', 'inc'), fullfile(root, 'dsp', 'src'), ...
    fullfile(folder, fixture), strjoin(sourceArgs, ' '), executable);
[status, output] = system(command);
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
