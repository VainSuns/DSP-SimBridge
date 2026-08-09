classdef test_sfun_step_candidates < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppPath(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testSynchronousStepAndAtomicOutputs(testCase)
            root = c2837x_block_normalize_absolute_path(tempname);
            mkdir(root);
            testCase.addTeardown(@() rmdir(root, 's'));
            port = free_port();
            project = step_project(root, port);
            candidates = c2837x_block_build_sfun_candidates(project);
            testCase.verifyNumElements(candidates, 20);
            write_candidates(candidates);
            write_fixture(project.output.sfun_root, 'simstruc.h', simstruc_stub());
            write_fixture(project.output.sfun_root, 'simulink.c', '/* host stub */');
            folder = fullfile(project.output.sfun_root, 'axis_alpha');
            write_fixture(folder, 'axis_alpha_sfun_user_config.h', sprintf([ ...
                '#define CONNECT_TIMEOUT_MS 500u\n' ...
                '#define STEP_TIMEOUT_MS 100u\n' ...
                '#define TERMINATE_TIMEOUT_MS 50u\n']));

            config = candidate_text(candidates, 'axis_alpha_sfun_config.h');
            source = candidate_text(candidates, 'axis_alpha_sfun.c');
            header = candidate_text(candidates, 'axis_alpha_sfun.h');
            io = candidate_text(candidates, 'axis_alpha_sfun_io.c');
            betaConfig = candidate_text(candidates, 'axis_beta_sfun_config.h');
            betaIo = candidate_text(candidates, 'axis_beta_sfun_io.c');
            testCase.verifySubstring(config, '#define AXIS_ALPHA_SFUN_INPUT_PAYLOAD_OCTETS 102u');
            testCase.verifySubstring(config, '#define AXIS_ALPHA_SFUN_OUTPUT_PAYLOAD_OCTETS 100u');
            testCase.verifySubstring(config, '#define AXIS_ALPHA_SFUN_INPUT_DATA_OCTETS 98u');
            testCase.verifySubstring(config, '#define AXIS_ALPHA_SFUN_OUTPUT_DATA_OCTETS 96u');
            testCase.verifySubstring(config, '#define AXIS_ALPHA_SFUN_STEP_INDEX_OCTETS 4u');
            testCase.verifySubstring(config, '#define AXIS_ALPHA_SFUN_MAX_PAYLOAD_OCTETS 1024u');
            testCase.verifySubstring(config, '#define AXIS_ALPHA_SFUN_INPUT_0_WIRE_OFFSET 4u');
            testCase.verifySubstring(config, '#define AXIS_ALPHA_SFUN_OUTPUT_5_WIRE_OCTETS 56u');
            testCase.verifySubstring(config, 'FLT_MANT_DIG == 24 && FLT_MAX_EXP == 128');
            testCase.verifySubstring(config, 'DBL_MANT_DIG == 53 && DBL_MAX_EXP == 1024');
            testCase.verifySubstring(header, 'AxisAlphaSfunOutputTemp output_temp;');
            testCase.verifySubstring(header, ...
                'uint8_t tx_frame[AXIS_ALPHA_HEADER_SIZE + AXIS_ALPHA_SFUN_INPUT_PAYLOAD_OCTETS];');
            testCase.verifyEmpty(strfind(header, 'tx_payload['));
            testCase.verifySubstring(source, 'STEP_TIMEOUT_MS, &context->error');
            testCase.verifySubstring(io, 'ssGetInputPortSignal(S, 0)');
            testCase.verifySubstring(io, 'ssGetOutputPortSignal(S, 0)');
            testCase.verifyEmpty(regexp(io, 'for \([^\n]*(port|element)', 'once'));
            testCase.verifySubstring(betaConfig, '#define AXIS_BETA_SFUN_INPUT_PAYLOAD_OCTETS 38u');
            testCase.verifySubstring(betaConfig, '#define AXIS_BETA_SFUN_OUTPUT_PAYLOAD_OCTETS 40u');
            testCase.verifySubstring(betaConfig, '#define AXIS_BETA_SFUN_INPUT_5_WIRE_OFFSET 30u');
            testCase.verifySubstring(betaConfig, '#define AXIS_BETA_SFUN_OUTPUT_5_WIRE_OFFSET 32u');
            testCase.verifySubstring(betaIo, 'ssGetInputPortSignal(S, 5)');
            testCase.verifySubstring(betaIo, 'ssGetOutputPortSignal(S, 5)');
            testCase.verifyEmpty(regexp(betaIo, 'for \([^\n]*(port|element)', 'once'));
            writeLe64 = c_function_text(io, ...
                'static void axis_alpha_sfun_write_le64');
            readLe64 = c_function_text(io, ...
                'static uint64_t axis_alpha_sfun_read_le64');
            testCase.verifyEmpty(regexp([writeLe64 readLe64], ...
                '\<(for|while)\s*\(', 'once'));
            testCase.verifyEmpty(regexp([writeLe64 readLe64], ...
                '\<index\>', 'once'));
            testCase.verifySubstring(writeLe64, 'value >> 56');
            testCase.verifySubstring(readLe64, '(uint64_t)buffer[7] << 56');
            testCase.verifyEmpty(regexp(io, 'memcpy\([^\n]*tx_payload', 'once'));
            outputsStart = strfind(source, 'static void mdlOutputs');
            terminateStart = strfind(source, 'static void mdlTerminate');
            testCase.verifyTrue(isscalar(outputsStart) && isscalar(terminateStart));
            stepBody = source(outputsStart:terminateStart - 1);
            testCase.verifyEqual(numel(strfind(stepBody, 'pc_error_reset')), 1);
            testCase.verifyEmpty(strfind(io, 'pc_error_reset'));

            support = fullfile(fileparts(mfilename('fullpath')), 'support');
            executable = fullfile(root, 's4_04_step');
            python = pyenv;
            command = sprintf('"%s" "%s" "%s" "%s" %u 2>&1', ...
                python.Executable, fullfile(support, 'run_s4_04_step.py'), ...
                executable, folder, port);
            [status, output] = system(command);
            testCase.verifyEqual(status, 0, output);
            testCase.verifySubstring(output, 'BETA_COMPLEMENTARY_IO=PASS');
            testCase.verifySubstring(output, 'SUMMARY passed=16 failed=0');
        end
    end
end

function project = step_project(root, port)
project = c2837x_block_create_default_project();
project.common.network.ip = '127.0.0.1';
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
types = {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'};
inputDims = {2, 1, 1, 1, 7, 7};
outputDims = {1, 1, 1, 1, 7, 7};
inputNames = cellfun(@(type) ['i_' type], types, 'UniformOutput', false);
outputNames = cellfun(@(type) ['o_' type], types, 'UniformOutput', false);
first = c2837x_block_create_default_instance();
first.display_name = 'Axis Alpha'; first.internal_name = 'axis_alpha';
first.inputs = struct('name', inputNames, 'type', types, 'dim', inputDims);
first.outputs = struct('name', outputNames, 'type', types, 'dim', outputDims);
first.iodevice.settings.tcp_port = uint16(port);
second = first; second.display_name = 'Axis Beta'; second.internal_name = 'axis_beta';
second.inputs = struct('name', inputNames, 'type', types, ...
    'dim', {1, 2, 2, 2, 1, 1});
second.outputs = struct('name', outputNames, 'type', types, ...
    'dim', {2, 2, 2, 2, 1, 1});
second.iodevice.settings.socket_number = uint16(1);
second.iodevice.settings.tcp_port = uint16(port + (port < 65535) - (port == 65535));
project.instances = [first second];
for index = 1:2
    [~, project.instances(index).interface_hash] = c2837x_block_build_interface_hash(project, index);
end
project.instances(1).interface_hash = uint32(hex2dec('12345678'));
end

function text = candidate_text(candidates, name)
index = find(endsWith({candidates.target_path}, name), 1);
assert(~isempty(index));
text = native2unicode(candidates(index).content_bytes, 'UTF-8');
end

function text = c_function_text(source, signature)
startPosition = strfind(source, signature);
assert(isscalar(startPosition));
tail = source(startPosition:end);
[~, endPosition] = regexp(tail, '(?m)^\}\n', 'start', 'end', 'once');
assert(~isempty(endPosition));
text = tail(1:endPosition);
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
    'const void *inputs[6]; void *outputs[6]; uint32_t options; size_t dwork_width; } SimStruct;\n' ...
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
    '#define ssGetPWork(S) (&(S)->pwork)\n' ...
    '#define ssGetPWorkValue(S,i) ((void)(i),(S)->pwork)\n' ...
    '#define ssGetDWork(S,i) ((void)(i),(void *)(S)->dwork)\n' ...
    '#define ssGetInputPortSignal(S,p) ((S)->inputs[(p)])\n' ...
    '#define ssGetOutputPortSignal(S,p) ((S)->outputs[(p)])\n#endif\n']);
end
