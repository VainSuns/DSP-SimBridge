function tests = test_s2_01_core_api
tests = functiontests(localfunctions);
end

function testPublicApiAndVersionCompile(testCase)
[status, output] = compile_fixture('core_api_compile.c');
verifyEqual(testCase, status, 0, output);
end

function testVersionMismatchIsExplicit(testCase)
[status, output] = compile_fixture('core_api_version_mismatch.c');
verifyNotEqual(testCase, status, 0);
verifyNotEmpty(testCase, strfind(output, ...
    'C2837xBlock Core API version mismatch')); %#ok<STREMP>
end

function testPublicTypeIsOpaque(testCase)
[status, ~] = compile_fixture('core_api_opaque.c');
verifyNotEqual(testCase, status, 0);
end

function testInstancesAndNullBehavior(testCase)
[status, output, executable] = compile_core_binary();
verifyEqual(testCase, status, 0, output);
[status, output] = system(sprintf('"%s"', executable));
verifyEqual(testCase, status, 0, output);
end

function testRetiredSingletonApiAndNoDynamicMemory(testCase)
root = repository_root();
source = fileread(fullfile(root, 'dsp', 'src', 'c2837x_block.c'));
header = fileread(fullfile(root, 'dsp', 'inc', 'c2837x_block.h'));
verifyEmpty(testCase, regexp(source, '\<g_ctx\>', 'once'));
verifyEmpty(testCase, regexp(source, 'static\s+Uint16\s+first_connected', 'once'));
verifyEmpty(testCase, regexp(header, 'C2837xBlock_(Init|Run)\s*\(\s*void\s*\)', 'once'));
verifyEmpty(testCase, regexp([source header], '\<(malloc|calloc|realloc|free)\s*\(', 'once'));
end

function [status, output] = compile_fixture(name)
root = repository_root();
folder = fileparts(mfilename('fullpath'));
outputFile = fullfile(tempdir, 'c2837x_s2_01_fixture.exe');
command = sprintf('gcc -std=c11 -Wall -Wextra -c -I"%s" -I"%s" "%s" -o "%s" 2>&1', ...
    fullfile(folder, 'include'), fullfile(root, 'dsp', 'inc'), ...
    fullfile(folder, name), outputFile);
[status, output] = system(command);
end

function [status, output, executable] = compile_core_binary()
root = repository_root();
folder = fileparts(mfilename('fullpath'));
executable = fullfile(tempdir, 'c2837x_s2_01_core_test.exe');
command = sprintf(['gcc -std=c11 -Wall -Wextra -I"%s" -I"%s" -I"%s" ' ...
    '"%s" "%s" -o "%s" 2>&1'], fullfile(folder, 'include'), ...
    fullfile(root, 'dsp', 'inc'), fullfile(root, 'dsp', 'src'), ...
    fullfile(folder, 'core_instance_test.c'), ...
    fullfile(root, 'dsp', 'src', 'c2837x_block.c'), executable);
[status, output] = system(command);
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
