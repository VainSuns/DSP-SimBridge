classdef test_s2_07_core_protocol < matlab.unittest.TestCase
    methods (Test)
        function testProtocolStateMachine(testCase)
            [status, output] = test_s2_07_core_protocol.compileAndRun( ...
                'core_protocol_state_test.c', true);
            testCase.verifyEqual(status, 0, output);
        end

        function testIoDeviceLifecycle(testCase)
            [status, output] = test_s2_07_core_protocol.compileAndRun( ...
                'core_iodevice_lifecycle_test.c', true);
            testCase.verifyEqual(status, 0, output);
        end

        function testTwoInstanceIsolationRegression(testCase)
            [status, output] = test_s2_07_core_protocol.compileAndRun( ...
                'core_instance_test.c', false);
            testCase.verifyEqual(status, 0, output);
        end

        function testCoreIsDeviceIndependent(testCase)
            source = test_s2_07_core_protocol.coreText();
            banned = '(W5300|Sn_|SOCK_|Sn_CR|Sn_SSR|SEND_OK|ERRATUM)';
            testCase.verifyEmpty(regexp(source, banned, 'once'));
        end

        function testCoreHasBoundedGenericStates(testCase)
            source = test_s2_07_core_protocol.coreText();
            testCase.verifyEmpty(regexp(source, '\<while\>|\<do\>', 'once'));
            testCase.verifyEmpty(regexp(source, ...
                '(tick_counter|STATE_TIMEOUT_TICKS|FRAME_TIMEOUT_TICKS)', 'once'));
            testCase.verifyNotEmpty(strfind(source, ...
                'C2837X_BLOCK_STATE_WAIT_CONNECTION')); %#ok<STREMP>
            testCase.verifyNotEmpty(strfind(source, ...
                'C2837X_BLOCK_PROTOCOL_WAIT_SIM_START')); %#ok<STREMP>
            testCase.verifyNotEmpty(strfind(source, 'close_pending')); %#ok<STREMP>
        end

        function testRunDoesNotRepeatStaticConfigValidation(testCase)
            root = test_s2_07_core_protocol.repositoryRoot();
            source = fileread(fullfile(root, 'dsp', 'src', ...
                'c2837x_block.c'));
            init = regexp(source, ...
                'void C2837xBlock_Init\([\s\S]*?(?=\nvoid C2837xBlock_Run\()', ...
                'match', 'once');
            run = regexp(source, ...
                'void C2837xBlock_Run\([\s\S]*?(?=\nC2837xBlock_Error C2837xBlock_GetLastError\()', ...
                'match', 'once');
            testCase.verifyNotEmpty(init);
            testCase.verifyNotEmpty(run);
            testCase.verifyNotEmpty(regexp(init, ...
                'c2837x_block_config_is_valid\s*\(', 'once'));
            testCase.verifyEmpty(regexp(run, ...
                'c2837x_block_config_is_valid\s*\(', 'once'));
        end
    end

    methods (Static, Access = private)
        function [status, output] = compileAndRun(fixture, linkProtocol)
            root = test_s2_07_core_protocol.repositoryRoot();
            folder = fileparts(mfilename('fullpath'));
            executable = fullfile(tempdir, ...
                ['c2837x_s2_07_' erase(fixture, '.c') '.exe']);
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

        function source = coreText()
            root = test_s2_07_core_protocol.repositoryRoot();
            source = [fileread(fullfile(root, 'dsp', 'src', ...
                'c2837x_block.c')) newline fileread(fullfile(root, ...
                'dsp', 'src', 'c2837x_block_internal.h'))];
        end

        function root = repositoryRoot()
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        end
    end
end
