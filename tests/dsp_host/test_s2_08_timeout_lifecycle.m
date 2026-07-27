classdef test_s2_08_timeout_lifecycle < matlab.unittest.TestCase
    methods (Test)
        function testTimeoutAndLifecycleFixture(testCase)
            [status, output] = test_s2_08_timeout_lifecycle.compileAndRun( ...
                'core_timeout_lifecycle_test.c', true);
            testCase.verifyEqual(status, 0, output);
        end

        function testTwoInstanceTimeoutIsolation(testCase)
            [status, output] = test_s2_08_timeout_lifecycle.compileAndRun( ...
                'core_instance_test.c', false);
            testCase.verifyEqual(status, 0, output);
        end

        function testCoreTimeoutImplementationIsBounded(testCase)
            root = test_s2_08_timeout_lifecycle.repositoryRoot();
            core = fileread(fullfile(root, 'dsp', 'src', ...
                'c2837x_block.c'));
            internal = fileread(fullfile(root, 'dsp', 'src', ...
                'c2837x_block_internal.h'));
            testCase.verifyEmpty(regexp([core internal], ...
                '(tick_counter|TIMEOUT_TICKS|W5300|Sn_|SOCK_|SEND_OK|ERRATUM)', ...
                'once'));
            testCase.verifyEmpty(regexp(core, '\<while\>|\<do\>', 'once'));
            testCase.verifyNotEmpty(regexp(core, ...
                'elapsed_us\s*=\s*now_us\s*-\s*start_us', 'once'));
            for field = {'progress_start_us', 'receive_wait_kind', ...
                    'primary_error_latched', 'normal_end_pending'}
                testCase.verifyNotEmpty(regexp(internal, ...
                    ['\<' field{1} '\>'], 'once'), field{1});
            end
        end

        function testSampleTimeoutBindingIsUnique(testCase)
            root = test_s2_08_timeout_lifecycle.repositoryRoot();
            header = fileread(fullfile(root, 'dsp', 'inc', ...
                'c2837x_block_config.h'));
            config = fileread(fullfile(root, 'dsp', 'src', ...
                'c2837x_block_config.c'));
            testCase.verifyNotEmpty(regexp(header, ...
                'INTERACTION_TIMEOUT\s+5000u', 'once'));
            testCase.verifyNotEmpty(regexp(header, ...
                'TRANSFER_TIMEOUT\s+1000u', 'once'));
            testCase.verifyNotEmpty(regexp(config, ...
                'C2837X_BLOCK_TIMEOUT_MS_TO_US', 'once'));
            testCase.verifyEmpty(regexp(config, ...
                'SAMPLE_TRANSFER_TIMEOUT_US|5000000u|1000000u', 'once'));
            testCase.verifyNotEmpty(regexp(config, ...
                'INTERACTION_TIMEOUT\s*<=\s*2147483u', 'once'));
            testCase.verifyNotEmpty(regexp(config, ...
                'TRANSFER_TIMEOUT\s*<=\s*2147483u', 'once'));
        end
    end

    methods (Static, Access = private)
        function [status, output] = compileAndRun(fixture, linkProtocol)
            root = test_s2_08_timeout_lifecycle.repositoryRoot();
            folder = fileparts(mfilename('fullpath'));
            executable = fullfile(tempdir, ...
                ['c2837x_s2_08_' erase(fixture, '.c') '.exe']);
            protocolSource = '';
            if linkProtocol
                protocolSource = sprintf(' "%s"', fullfile(root, ...
                    'dsp', 'src', 'c2837x_block_protocol.c'));
            end
            command = sprintf([ ...
                'gcc -std=c11 -Wall -Wextra -Werror -I"%s" -I"%s" -I"%s" ' ...
                '"%s" "%s"%s -o "%s" 2>&1'], ...
                fullfile(folder, 'include'), fullfile(root, 'dsp', 'inc'), ...
                fullfile(root, 'dsp', 'src'), fullfile(folder, fixture), ...
                fullfile(root, 'dsp', 'src', 'c2837x_block.c'), ...
                protocolSource, executable);
            [status, output] = system(command);
            if status == 0
                [status, runOutput] = system(sprintf('"%s" 2>&1', executable));
                output = [output runOutput];
            end
        end

        function root = repositoryRoot()
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        end
    end
end
