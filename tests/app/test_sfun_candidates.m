classdef test_sfun_candidates < matlab.unittest.TestCase
    properties
        WorkFolder
        RepositoryRoot
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            testCase.RepositoryRoot = fileparts(fileparts(fileparts( ...
                mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'app')));
        end
    end

    methods (TestMethodSetup)
        function createWorkFolder(testCase)
            testCase.WorkFolder = c2837x_block_normalize_absolute_path(tempname);
            mkdir(testCase.WorkFolder);
            testCase.addTeardown(@() rmdir(testCase.WorkFolder, 's'));
        end
    end

    methods (Test)
        function testDualInstanceCandidateTreeAndDeterminism(testCase)
            project = two_instance_project(testCase.WorkFolder);
            [first, dependencies, issues] = ...
                c2837x_block_build_sfun_candidates(project);
            second = c2837x_block_build_sfun_candidates(project);

            testCase.verifyEmpty(issues);
            testCase.verifyEqual(second, first);
            testCase.verifyNumElements(first, 8);
            testCase.verifyEqual([first.instance_index], [ones(1, 4) 2 * ones(1, 4)]);
            testCase.verifyEqual({first.category}, repmat({'auto_generated'}, 1, 8));
            testCase.verifyNumElements(unique({first.owner}), 8);
            testCase.verifyEqual(candidate_names(first), { ...
                'axis_alpha_sfun.c', 'axis_alpha_sfun.h', ...
                'axis_alpha_sfun_io.c', 'axis_alpha_sfun_config.h', ...
                'axis_beta_sfun.c', 'axis_beta_sfun.h', ...
                'axis_beta_sfun_io.c', 'axis_beta_sfun_config.h'});
            testCase.verifyTrue(all(cellfun(@(path) contains(path, ...
                [project.output.sfun_root filesep]), {first.target_path})));
            testCase.verifyFalse(isfolder(project.output.sfun_root));
            testCase.verifyNumElements(dependencies, 4);
            testCase.verifyTrue(all(cellfun(@isfile, {dependencies.source_path})));
            testCase.verifyEmpty(c2837x_block_validate_candidate_files(first));
            [comparisons, comparisonIssues] = ...
                c2837x_block_compare_candidate_files(first);
            testCase.verifyEmpty(comparisonIssues);
            testCase.verifyEqual({comparisons.target_state}, repmat({'missing'}, 1, 8));
            testCase.verifyFalse(any(contains({first.target_path}, { ...
                '_protocol.', '_pc_socket.', '_sfun_user_config.h', 'build_'}), 'all'));
        end

        function testNamesContextNormalModeAndUnimplementedStep(testCase)
            candidates = c2837x_block_build_sfun_candidates( ...
                two_instance_project(testCase.WorkFolder));
            alpha = instance_text(candidates, 1);
            beta = instance_text(candidates, 2);

            testCase.verifySubstring(alpha.source, ...
                '#define S_FUNCTION_NAME axis_alpha_sfun');
            testCase.verifySubstring(beta.source, ...
                '#define S_FUNCTION_NAME axis_beta_sfun');
            testCase.verifySubstring(alpha.header, 'AxisAlphaSfunContext');
            testCase.verifySubstring(beta.header, 'AxisBetaSfunContext');
            testCase.verifySubstring(alpha.source, 'ssSetPWorkValue(S, 0, context)');
            testCase.verifySubstring(alpha.source, 'ssGetPWorkValue(S, 0)');
            testCase.verifySubstring(alpha.source, ...
                'communication is not implemented by S4-01');
            testCase.verifySubstring(alpha.source, '#ifndef MATLAB_MEX_FILE');
            testCase.verifySubstring(alpha.source, 'Normal mode only');
            testCase.verifyEmpty(regexp([alpha.source alpha.header alpha.io alpha.config], ...
                ['(g_c2837x_block_instance_count|Only one instance allowed|cg_sfun\.h|' ...
                'SIM_START|INPUT_DATA|OUTPUT_DATA|SIM_STOP|step_index|socket|TCP)'], 'once'));
            testCase.verifyEqual(numel(regexp(alpha.source, ...
                '(?m)^static void mdl(InitializeSizes|InitializeSampleTimes|Start|Outputs|Terminate)', ...
                'match')), 5);
        end

        function testPortsSampleTimeAndTextContract(testCase)
            candidates = c2837x_block_build_sfun_candidates( ...
                two_instance_project(testCase.WorkFolder));
            alpha = instance_text(candidates, 1);
            expectedTypes = {'SS_INT16', 'SS_UINT16', 'SS_INT32', ...
                'SS_UINT32', 'SS_SINGLE', 'SS_DOUBLE'};

            testCase.verifySubstring(alpha.source, 'ssSetNumSFcnParams(S, 0);');
            testCase.verifySubstring(alpha.source, 'ssSetNumSampleTimes(S, 1);');
            testCase.verifySubstring(alpha.source, ...
                'ssSetSampleTime(S, 0, AXIS_ALPHA_SFUN_SAMPLE_TIME_SEC);');
            testCase.verifySubstring(alpha.source, 'ssSetOffsetTime(S, 0, 0.0);');
            sampleToken = regexp(alpha.config, ...
                'AXIS_ALPHA_SFUN_SAMPLE_TIME_SEC \(([^)]+)\)', 'tokens', 'once');
            testCase.verifyEqual(str2double(sampleToken{1}), 2.5e-4);
            testCase.verifySubstring(alpha.config, ...
                '#define AXIS_ALPHA_SFUN_INPUT_PORT_COUNT 6u');
            testCase.verifySubstring(alpha.config, ...
                '#define AXIS_ALPHA_SFUN_OUTPUT_PORT_COUNT 6u');
            testCase.verifyEmpty(strfind(alpha.config, 'sample_time_positive'));
            testCase.verifyEmpty(regexp(alpha.config, ...
                'SFUN_STATIC_ASSERT\([^\n]*SAMPLE_TIME', 'once'));
            testCase.verifySubstring(alpha.config, ...
                'AXIS_ALPHA_SFUN_STATIC_ASSERT(AXIS_ALPHA_SFUN_INPUT_PORT_COUNT > 0u');
            testCase.verifySubstring(alpha.config, ...
                'AXIS_ALPHA_SFUN_STATIC_ASSERT(AXIS_ALPHA_SFUN_OUTPUT_PORT_COUNT > 0u');
            testCase.verifyEqual(numel(regexp(alpha.io, ...
                'ssSetInputPortDirectFeedThrough\(S, \d+, 1\);', 'match')), 6);
            verify_order(testCase, alpha.io, ...
                {'Port 0: i_int16', 'Port 1: i_uint16', 'Port 2: i_int32', ...
                'Port 3: i_uint32', 'Port 4: i_single', 'Port 5: i_double'});
            verify_order(testCase, alpha.io, ...
                {'Port 0: o_int16', 'Port 1: o_uint16', 'Port 2: o_int32', ...
                'Port 3: o_uint32', 'Port 4: o_single', 'Port 5: o_double'});
            for index = 1:6
                port = index - 1;
                testCase.verifySubstring(alpha.config, sprintf( ...
                    'AXIS_ALPHA_SFUN_INPUT_%u_WIDTH %uu', port, index));
                testCase.verifySubstring(alpha.config, sprintf( ...
                    'AXIS_ALPHA_SFUN_INPUT_%u_DATA_TYPE %s', ...
                    port, expectedTypes{index}));
                testCase.verifySubstring(alpha.config, sprintf( ...
                    'AXIS_ALPHA_SFUN_OUTPUT_%u_WIDTH %uu', port, index));
                testCase.verifySubstring(alpha.config, sprintf( ...
                    'AXIS_ALPHA_SFUN_OUTPUT_%u_DATA_TYPE %s', ...
                    port, expectedTypes{index}));
                testCase.verifySubstring(alpha.config, sprintf( ...
                    'AXIS_ALPHA_SFUN_INPUT_%u_WIDTH > 0u, input_%u_width_positive', ...
                    port, port));
                testCase.verifySubstring(alpha.config, sprintf( ...
                    'AXIS_ALPHA_SFUN_OUTPUT_%u_WIDTH > 0u, output_%u_width_positive', ...
                    port, port));
            end
            testCase.verifyEmpty(regexp(alpha.source, ...
                '(CONTINUOUS_SAMPLE_TIME|INHERITED_SAMPLE_TIME|VARIABLE_SAMPLE_TIME)', 'once'));

            for index = 1:numel(candidates)
                bytes = candidates(index).content_bytes;
                text = native2unicode(bytes, 'UTF-8');
                expectedHeader = sprintf([ ...
                    '/*\n * AUTO-GENERATED FILE\n' ...
                    ' * Manual changes will be overwritten.\n */\n\n']);
                testCase.verifyTrue(startsWith(text, expectedHeader));
                testCase.verifyFalse(any(bytes == 13));
                testCase.verifyFalse(numel(bytes) >= 3 && ...
                    isequal(bytes(1:3), uint8([239 187 191])));
                testCase.verifyEqual(bytes(end), uint8(10));
                testCase.verifyTrue(isscalar(bytes) || bytes(end - 1) ~= 10);
                testCase.verifyEmpty(regexp(text, '[ \t]+\n', 'once'));
                testCase.verifyEmpty(regexp(text, ...
                    '(Generated on|timestamp|20\d\d[-/][01]\d[-/][0-3]\d)', 'once'));
            end
        end

        function testExternalSymbolsAndMacrosAreDisjoint(testCase)
            candidates = c2837x_block_build_sfun_candidates( ...
                two_instance_project(testCase.WorkFolder));
            write_candidates(candidates);
            write_simstruc_stub(testCase.WorkFolder);
            alphaSymbols = compiled_symbols(testCase, project_folder(candidates, 1));
            betaSymbols = compiled_symbols(testCase, project_folder(candidates, 2));
            testCase.verifyEqual(sort(alphaSymbols), sort({ ...
                'axis_alpha_sfun_create_context', ...
                'axis_alpha_sfun_destroy_context', ...
                'axis_alpha_sfun_setup_input_ports', ...
                'axis_alpha_sfun_setup_output_ports'}));
            testCase.verifyEqual(sort(betaSymbols), sort({ ...
                'axis_beta_sfun_create_context', ...
                'axis_beta_sfun_destroy_context', ...
                'axis_beta_sfun_setup_input_ports', ...
                'axis_beta_sfun_setup_output_ports'}));
            testCase.verifyEmpty(intersect(alphaSymbols, betaSymbols));

            alpha = instance_text(candidates, 1);
            beta = instance_text(candidates, 2);
            testCase.verifyEmpty(intersect(defined_macros(alpha), defined_macros(beta)));
        end

        function testRejectsInvalidSampleTime(testCase)
            project = two_instance_project(testCase.WorkFolder);
            invalidValues = {0, -1, NaN, Inf};
            identifiers = { ...
                'C2837xBlock:SfunRender:InvalidSampleTime', ...
                'C2837xBlock:SfunRender:InvalidSampleTime', ...
                'C2837xBlock:Project:InvalidStructure', ...
                'C2837xBlock:Project:InvalidStructure'};
            for index = 1:numel(invalidValues)
                project.instances(1).sample_time_sec = invalidValues{index};
                testCase.verifyError( ...
                    @() c2837x_block_build_sfun_candidates(project), ...
                    identifiers{index});
            end
        end
    end
end

function project = two_instance_project(root)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
types = {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'};
dims = num2cell(1:6);
inputNames = cellfun(@(type) ['i_' type], types, 'UniformOutput', false);
outputNames = cellfun(@(type) ['o_' type], types, 'UniformOutput', false);
template = c2837x_block_create_default_instance();
template.inputs = struct('name', inputNames, 'type', types, 'dim', dims);
template.outputs = struct('name', outputNames, 'type', types, 'dim', dims);
template.sample_time_sec = 2.5e-4;
template.display_name = 'Axis Alpha';
template.internal_name = 'axis_alpha';
second = template;
second.display_name = 'Axis Beta';
second.internal_name = 'axis_beta';
second.sample_time_sec = 1e-3;
second.iodevice.settings.socket_number = uint16(1);
second.iodevice.settings.tcp_port = uint16(5001);
project.instances = [template second];
for index = 1:numel(project.instances)
    [~, project.instances(index).interface_hash] = ...
        c2837x_block_build_interface_hash(project, index);
end
end

function names = candidate_names(candidates)
names = cell(size(candidates));
for index = 1:numel(candidates)
    [~, name, extension] = fileparts(candidates(index).target_path);
    names{index} = [name extension];
end
end

function value = instance_text(candidates, instanceIndex)
selected = candidates([candidates.instance_index] == instanceIndex);
value = struct('source', '', 'header', '', 'io', '', 'config', '');
for index = 1:numel(selected)
    [~, name, extension] = fileparts(selected(index).target_path);
    text = native2unicode(selected(index).content_bytes, 'UTF-8');
    if endsWith(name, '_sfun_io')
        value.io = text;
    elseif endsWith(name, '_sfun_config')
        value.config = text;
    elseif strcmp(extension, '.c')
        value.source = text;
    else
        value.header = text;
    end
end
end

function verify_order(testCase, text, tokens)
positions = cellfun(@(token) strfind(text, token), tokens, 'UniformOutput', false);
testCase.assertTrue(all(cellfun(@isscalar, positions)));
testCase.verifyTrue(issorted(cellfun(@(value) value(1), positions)));
end

function write_candidates(candidates)
for index = 1:numel(candidates)
    folder = fileparts(candidates(index).target_path);
    if ~isfolder(folder), mkdir(folder); end
    fileID = fopen(candidates(index).target_path, 'wb');
    assert(fileID >= 0);
    cleanup = onCleanup(@() fclose(fileID));
    fwrite(fileID, candidates(index).content_bytes, 'uint8');
    clear cleanup
end
end

function folder = project_folder(candidates, instanceIndex)
selected = candidates([candidates.instance_index] == instanceIndex);
folder = fileparts(selected(1).target_path);
end

function symbols = compiled_symbols(testCase, folder)
[~, name] = fileparts(folder);
source = fullfile(folder, [name '_sfun.c']);
ioSource = fullfile(folder, [name '_sfun_io.c']);
objects = {fullfile(folder, 'sfun.o'), fullfile(folder, 'io.o')};
for index = 1:2
    sources = {source, ioSource};
    [status, output] = system(sprintf( ...
        'gcc -std=c11 -pedantic-errors -DMATLAB_MEX_FILE -I"%s" -c "%s" -o "%s" 2>&1', ...
        fileparts(fileparts(folder)), sources{index}, objects{index}));
    testCase.assertEqual(status, 0, output);
end
[status, output] = system(sprintf('nm -g --defined-only "%s" "%s" 2>&1', ...
    objects{1}, objects{2}));
testCase.assertEqual(status, 0, output);
symbols = regexp(output, '(?m)^[0-9A-Fa-f]+\s+[A-Za-z]\s+(_?[A-Za-z]\w*)\s*$', ...
    'tokens');
symbols = cellfun(@(token) regexprep(token{1}, '^_', ''), symbols, ...
    'UniformOutput', false);
end

function macros = defined_macros(value)
text = [value.source value.header value.io value.config];
tokens = regexp(text, '(?m)^#define\s+([A-Za-z_]\w*)', 'tokens');
macros = unique(cellfun(@(token) token{1}, tokens, 'UniformOutput', false));
macros = macros(~ismember(macros, {'S_FUNCTION_NAME', 'S_FUNCTION_LEVEL', 'MDL_START'}));
end

function write_simstruc_stub(root)
text = sprintf([ ...
    '#ifndef SIMSTRUC_H\n#define SIMSTRUC_H\n' ...
    '#include <stddef.h>\n' ...
    'typedef int int_T;\ntypedef struct SimStruct_tag { void *pwork; } SimStruct;\n' ...
    '#define SS_INT16 1\n#define SS_UINT16 2\n#define SS_INT32 3\n' ...
    '#define SS_UINT32 4\n#define SS_SINGLE 5\n#define SS_DOUBLE 6\n' ...
    '#define SS_OPTION_EXCEPTION_FREE_CODE 0\n' ...
    '#define ssSetNumSFcnParams(S,n) ((void)(S),(void)(n))\n' ...
    '#define ssGetNumSFcnParams(S) (0)\n#define ssGetSFcnParamsCount(S) (0)\n' ...
    '#define ssSetNumInputPorts(S,n) ((void)(S),(void)(n),1)\n' ...
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
    '#define ssSetOptions(S,o) ((void)(S),(void)(o))\n' ...
    '#define ssSetErrorStatus(S,m) ((void)(S),(void)(m))\n' ...
    '#define ssSetPWorkValue(S,i,v) ((void)(i),(S)->pwork=(v))\n' ...
    '#define ssGetPWorkValue(S,i) ((void)(i),(S)->pwork)\n' ...
    '#endif\n']);
write_text(fullfile(root, 'simstruc.h'), text);
write_text(fullfile(root, 'simulink.c'), sprintf('/* host compile stub */\n'));
end

function write_text(path, text)
fileID = fopen(path, 'wb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fwrite(fileID, unicode2native(text, 'UTF-8'), 'uint8');
clear cleanup
end
