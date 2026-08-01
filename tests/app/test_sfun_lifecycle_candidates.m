classdef test_sfun_lifecycle_candidates < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppPath(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testGeneratedLifecycleAgainstMockTcp(testCase)
            root = c2837x_block_normalize_absolute_path(tempname);
            mkdir(root);
            testCase.addTeardown(@() rmdir(root, 's'));
            port = free_port();
            project = lifecycle_project(root, port);
            candidates = c2837x_block_build_sfun_candidates(project);
            testCase.verifyNumElements(candidates, 20);
            alphaSource = candidate_text(candidates, 'axis_alpha_sfun.c');
            alphaConfig = candidate_text(candidates, 'axis_alpha_sfun_config.h');
            betaConfig = candidate_text(candidates, 'axis_beta_sfun_config.h');
            testCase.verifySubstring(alphaConfig, '#define AXIS_ALPHA_SFUN_DSP_IP_ADDRESS "127.0.0.1"');
            testCase.verifySubstring(alphaConfig, sprintf('#define AXIS_ALPHA_SFUN_TCP_PORT %uu', port));
            testCase.verifySubstring(alphaConfig, '#define AXIS_ALPHA_SFUN_PROTOCOL_VERSION 1u');
            testCase.verifySubstring(alphaConfig, '#define AXIS_ALPHA_SFUN_INTERFACE_HASH 0x12345678u');
            testCase.verifyFalse(contains(betaConfig, sprintf('TCP_PORT %uu', port)));
            testCase.verifyFalse(contains([alphaConfig betaConfig], ...
                {'CONNECT_TIMEOUT_MS', 'STEP_TIMEOUT_MS', 'TERMINATE_TIMEOUT_MS'}));
            testCase.verifyEqual(numel(strfind(alphaSource, 'CONNECT_TIMEOUT_MS, &context->error')), 1);
            testCase.verifyEqual(numel(strfind(alphaSource, 'STEP_TIMEOUT_MS, &context->error')), 2);
            testCase.verifyEqual(numel(strfind(alphaSource, 'STEP_TIMEOUT_MS,')), 4);
            testCase.verifyEqual(numel(strfind(alphaSource, 'TERMINATE_TIMEOUT_MS, &context->error')), 1);
            write_candidates(candidates);
            folder = fullfile(project.output.sfun_root, 'axis_alpha');
            write_fixture(folder, 'axis_alpha_sfun_user_config.h', sprintf([ ...
                '#ifndef CONNECT_TIMEOUT_MS\n#define CONNECT_TIMEOUT_MS 500u\n#endif\n' ...
                '#define STEP_TIMEOUT_MS 100u\n#define TERMINATE_TIMEOUT_MS 50u\n']));
            write_fixture(project.output.sfun_root, 'simstruc.h', simstruc_stub());
            write_fixture(project.output.sfun_root, 'simulink.c', '/* host stub */');
            support = fullfile(fileparts(mfilename('fullpath')), 'support');
            executable = fullfile(root, 's4_03_client');
            python = pyenv;
            command = sprintf('"%s" "%s" "%s" "%s" %u 2>&1', ...
                python.Executable, fullfile(support, 'run_s4_03_lifecycle.py'), ...
                executable, folder, port);
            [status, output] = system(command);
            testCase.verifyEqual(status, 0, output);
            testCase.verifySubstring(output, 'SUMMARY passed=8 failed=0');
        end
    end
end

function text = candidate_text(candidates, name)
index = find(endsWith({candidates.target_path}, name), 1);
assert(~isempty(index));
text = native2unicode(candidates(index).content_bytes, 'UTF-8');
end

function project = lifecycle_project(root, port)
project = c2837x_block_create_default_project();
project.common.network.ip = '127.0.0.1';
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
first = c2837x_block_create_default_instance();
first.display_name = 'Axis Alpha'; first.internal_name = 'axis_alpha';
first.inputs = struct('name', 'command', 'type', 'uint16', 'dim', 1);
first.outputs = struct('name', 'feedback', 'type', 'uint16', 'dim', 1);
first.iodevice.settings.tcp_port = uint16(port);
second = first; second.display_name = 'Axis Beta'; second.internal_name = 'axis_beta';
second.iodevice.settings.socket_number = uint16(1);
second.iodevice.settings.tcp_port = uint16(port + (port < 65535) - (port == 65535));
project.instances = [first second];
for index = 1:2
    [~, project.instances(index).interface_hash] = c2837x_block_build_interface_hash(project, index);
end
project.instances(1).interface_hash = uint32(hex2dec('12345678'));
end

function port = free_port()
server = java.net.ServerSocket(0);
cleanup = onCleanup(@() server.close());
port = server.getLocalPort();
clear cleanup
end

function write_candidates(candidates)
for index = 1:numel(candidates)
    folder = fileparts(candidates(index).target_path);
    if ~isfolder(folder), mkdir(folder); end
    write_bytes(candidates(index).target_path, candidates(index).content_bytes);
end
end

function write_fixture(folder, name, text)
if ~isfolder(folder), mkdir(folder); end
write_bytes(fullfile(folder, name), unicode2native([text newline], 'UTF-8'));
end

function write_bytes(path, bytes)
file = fopen(path, 'wb'); assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); fwrite(file, bytes, 'uint8'); clear cleanup
end

function text = simstruc_stub()
text = sprintf([ ...
    '#ifndef SIMSTRUC_H\n#define SIMSTRUC_H\n#include <stddef.h>\n#include <stdint.h>\n' ...
    'typedef int int_T;\ntypedef struct { void *pwork; char dwork[512]; const char *error_status; ' ...
    'uint32_t options; size_t dwork_width; } SimStruct;\n' ...
    '#define SS_INT16 1\n#define SS_UINT16 2\n#define SS_INT32 3\n#define SS_UINT32 4\n' ...
    '#define SS_SINGLE 5\n#define SS_DOUBLE 6\n#define SS_UINT8 7\n' ...
    '#define SS_OPTION_EXCEPTION_FREE_CODE 1u\n#define SS_OPTION_CALL_TERMINATE_ON_EXIT 2u\n' ...
    '#define ssSetNumSFcnParams(S,n) ((void)(S),(void)(n))\n#define ssGetNumSFcnParams(S) 0\n' ...
    '#define ssGetSFcnParamsCount(S) 0\n#define ssSetNumInputPorts(S,n) ((void)(S),(void)(n),1)\n' ...
    '#define ssSetNumOutputPorts(S,n) ((void)(S),(void)(n),1)\n' ...
    '#define ssSetInputPortWidth(S,p,w) ((void)(S),(void)(p),(void)(w))\n' ...
    '#define ssSetOutputPortWidth(S,p,w) ((void)(S),(void)(p),(void)(w))\n' ...
    '#define ssSetInputPortDataType(S,p,t) ((void)(S),(void)(p),(void)(t))\n' ...
    '#define ssSetOutputPortDataType(S,p,t) ((void)(S),(void)(p),(void)(t))\n' ...
    '#define ssSetInputPortDirectFeedThrough(S,p,v) ((void)(S),(void)(p),(void)(v))\n' ...
    '#define ssSetInputPortRequiredContiguous(S,p,v) ((void)(S),(void)(p),(void)(v))\n' ...
    '#define ssSetNumSampleTimes(S,n) ((void)(S),(void)(n))\n' ...
    '#define ssSetSampleTime(S,i,t) ((void)(S),(void)(i),(void)(t))\n' ...
    '#define ssSetOffsetTime(S,i,t) ((void)(S),(void)(i),(void)(t))\n' ...
    '#define ssSetNumPWork(S,n) ((void)(S),(void)(n))\n' ...
    '#define ssSetNumDWork(S,n) ((void)(S),(void)(n),1)\n' ...
    '#define ssSetDWorkWidth(S,i,w) ((void)(i),(S)->dwork_width=(w))\n' ...
    '#define ssSetDWorkDataType(S,i,t) ((void)(S),(void)(i),(void)(t))\n' ...
    '#define ssSetDWorkUsedAsDState(S,i,v) ((void)(S),(void)(i),(void)(v))\n' ...
    '#define ssSetOptions(S,o) ((S)->options=(o))\n#define ssSetErrorStatus(S,m) ((S)->error_status=(m))\n' ...
    '#define ssSetPWorkValue(S,i,v) ((void)(i),(S)->pwork=(v))\n' ...
    '#define ssGetPWorkValue(S,i) ((void)(i),(S)->pwork)\n' ...
    '#define ssGetDWork(S,i) ((void)(i),(void *)(S)->dwork)\n' ...
    '#define ssGetInputPortSignal(S,p) ((void)(S),(void)(p),(const void *)0)\n' ...
    '#define ssGetOutputPortSignal(S,p) ((void)(S),(void)(p),(void *)0)\n#endif\n']);
end
