classdef test_s2_02_platform_init < matlab.unittest.TestCase
    methods (Test)
        function testPlatformInitializationAndFailures(testCase)
            [status, output] = compileAndRun('platform_init_test.c', ...
                {'c2837x_block_platform.c'});
            testCase.verifyEqual(status, 0, output);
        end

        function testTimer2MicrosecondSource(testCase)
            [status, output] = compileAndRun('timer2_test.c', ...
                {'c2837x_block_timer2.c'});
            testCase.verifyEqual(status, 0, output);
        end

        function testResetTimingAndScope(testCase)
            root = repositoryRoot();
            halHeader = fileread(fullfile(root, 'dsp', 'inc', ...
                'c2837x_w5300_hal.h'));
            halSource = fileread(fullfile(root, 'dsp', 'src', ...
                'c2837x_w5300_hal.c'));
            platformSource = fileread(fullfile(root, 'dsp', 'src', ...
                'c2837x_block_platform.c'));
            testCase.verifyNotEmpty(regexp(halHeader, ...
                'RESET_ASSERT_US\s+2u', 'once'));
            testCase.verifyNotEmpty(regexp(halHeader, ...
                'RESET_SETTLE_US\s+10000u', 'once'));
            testCase.verifyNotEmpty(regexp(halSource, ...
                ['GPIO_WritePin\([^;]+,\s*0\);\s*' ...
                 'DELAY_US\(C2837X_W5300_RESET_ASSERT_US\);\s*' ...
                 'GPIO_WritePin\([^;]+,\s*1\);\s*' ...
                 'DELAY_US\(C2837X_W5300_RESET_SETTLE_US\);'], 'once'));
            testCase.verifyEmpty(regexp(platformSource, ...
                '\<Sn_CR_(OPEN|LISTEN)\>', 'once'));
        end
    end
end

function [status, output] = compileAndRun(fixture, sources)
root = repositoryRoot();
folder = fileparts(mfilename('fullpath'));
[~, executableName] = fileparts(fixture);
executable = fullfile(tempdir, [executableName '.exe']);
sourceArguments = cellfun(@(name) sprintf('"%s"', ...
    fullfile(root, 'dsp', 'src', name)), sources, 'UniformOutput', false);
command = sprintf(['gcc -std=c11 -Wall -Wextra -Werror -I"%s" -I"%s" ' ...
    '-I"%s" "%s" %s -o "%s" 2>&1'], fullfile(folder, 'include'), ...
    fullfile(root, 'dsp', 'inc'), fullfile(root, 'dsp', 'src'), ...
    fullfile(folder, fixture), strjoin(sourceArguments, ' '), executable);
[compileStatus, compileOutput] = system(command);
if compileStatus ~= 0
    status = compileStatus;
    output = compileOutput;
    return;
end
[status, output] = system(sprintf('"%s"', executable));
end

function root = repositoryRoot()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
