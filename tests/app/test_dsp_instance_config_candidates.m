classdef test_dsp_instance_config_candidates < matlab.unittest.TestCase
    properties
        WorkFolder
        RepositoryRoot
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.RepositoryRoot = fileparts(fileparts(fileparts( ...
                mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'app')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'tests', 'app', 'fixtures')));
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
        function testCandidateCountsOrderAndAvailability(testCase)
            one = make_project(testCase.WorkFolder, {'axis_x'});
            two = make_project(testCase.WorkFolder, {'axis_x', 'axis_y'});
            three = make_project(testCase.WorkFolder, ...
                {'axis_x', 'axis_y', 'thermal_monitor'});

            oneCandidates = c2837x_block_build_dsp_candidates(one);
            twoCandidates = c2837x_block_build_dsp_candidates(two);
            threeCandidates = c2837x_block_build_dsp_candidates(three);

            testCase.verifyNumElements(oneCandidates, 24);
            testCase.verifyNumElements(twoCandidates, 29);
            testCase.verifyNumElements(threeCandidates, 34);
            verify_instance_files(testCase, three, threeCandidates);
        end

        function testNamingHashSizesAndStaticBindings(testCase)
            project = make_project(testCase.WorkFolder, ...
                {'axis_x', 'thermal_monitor'});

            rendered = c2837x_block_render_dsp_instance_config_files(project);
            axisHeader = text_of(rendered(1).config_header_bytes);
            axisSource = text_of(rendered(1).config_source_bytes);
            thermalHeader = text_of(rendered(2).config_header_bytes);
            thermalSource = text_of(rendered(2).config_source_bytes);

            testCase.verifyNotEmpty(strfind(axisHeader, ...
                'C2837X_BLOCK_AXIS_X_CONFIG_H'));
            testCase.verifyNotEmpty(strfind(axisHeader, ...
                '#define AXIS_X_INPUT_DATA_OCTETS          4u'));
            testCase.verifyNotEmpty(strfind(axisHeader, ...
                '#define AXIS_X_OUTPUT_DATA_OCTETS         8u'));
            testCase.verifyNotEmpty(strfind(axisHeader, ...
                '#define AXIS_X_INPUT_PAYLOAD_OCTETS       8u'));
            testCase.verifyNotEmpty(strfind(axisHeader, ...
                '#define AXIS_X_OUTPUT_PAYLOAD_OCTETS      12u'));
            testCase.verifyNotEmpty(strfind(axisHeader, ...
                '#define AXIS_X_RX_FRAME_WORDS             6u'));
            testCase.verifyNotEmpty(strfind(axisHeader, ...
                '#define AXIS_X_TX_FRAME_WORDS             8u'));
            testCase.verifyNotEmpty(strfind(axisSource, 'AxisX_InputData'));
            testCase.verifyNotEmpty(strfind(thermalSource, ...
                'ThermalMonitor_OutputData'));
            testCase.verifyEqual(hash_literal(axisHeader), ...
                hash_literal(thermalHeader));
            verify_instance_symbols(testCase, axisSource, 'axis_x');
            verify_instance_symbols(testCase, thermalSource, 'thermal_monitor');
            testCase.verifyEmpty(regexp([axisHeader axisSource thermalHeader thermalSource], ...
                '(current_loop|voltage_loop)', 'once'));
        end

        function testHashRecomputedAndRelevantInterfaceChanges(testCase)
            project = make_project(testCase.WorkFolder, {'axis_x'});
            first = render_texts(project, 1);
            project.instances(1).interface_hash = uint32(1);
            savedHashChanged = render_texts(project, 1);
            project.instances(1).inputs(1).dim = 2;
            inputChanged = render_texts(project, 1);
            project.instances(1).inputs(1).dim = 1;
            project.instances(1).max_payload_size_bytes = uint32(2048);
            maxPayloadChanged = render_texts(project, 1);

            testCase.verifyEqual(savedHashChanged, first);
            testCase.verifyNotEqual(hash_literal(inputChanged.header), ...
                hash_literal(first.header));
            testCase.verifyNotEqual(hash_literal(maxPayloadChanged.header), ...
                hash_literal(first.header));
            testCase.verifyNotEmpty(strfind(inputChanged.header, ...
                'AXIS_X_INPUT_DATA_OCTETS          8u'));
            testCase.verifyNotEmpty(strfind(maxPayloadChanged.header, ...
                'AXIS_X_MAX_PAYLOAD_OCTETS         2048u'));
            testCase.verifyNotEmpty(strfind(maxPayloadChanged.header, ...
                'AXIS_X_RX_FRAME_WORDS             6u'));
        end

        function testIgnoredInputsAndRootDoNotChangeBytes(testCase)
            project = make_project(testCase.WorkFolder, {'axis_x'});
            first = render_texts(project, 1);
            ignored = project;
            ignored.instances(1).display_name = 'Changed';
            ignored.instances(1).sample_time_sec = 0.25;
            ignored.common.network.ip = '10.0.0.2';
            ignored.common.abi = 'coffabi';
            ignored.instances(1).algorithm.mode = 'external_reference';
            ignored.instances(1).algorithm.source_path = ...
                c2837x_block_normalize_absolute_path(fullfile( ...
                testCase.WorkFolder, 'ignored.c'));
            ignored.instances(1).interface_hash = uint32(123);
            ignored.selected_instance = 1;
            otherRoot = project;
            otherRoot.output.dsp_root = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'other-dsp'));

            testCase.verifyEqual(render_texts(ignored, 1), first);
            testCase.verifyEqual(render_texts(otherRoot, 1), first);
            firstCandidates = c2837x_block_build_dsp_candidates(project);
            otherCandidates = c2837x_block_build_dsp_candidates(otherRoot);
            testCase.verifyNotEqual({otherCandidates.target_path}, ...
                {firstCandidates.target_path});
            testCase.verifyEqual({otherCandidates.content_bytes}, ...
                {firstCandidates.content_bytes});
        end

        function testProviderOwnsInstanceRouting(testCase)
            project = make_project(testCase.WorkFolder, {'axis_x', 'axis_y'});
            project.instances(1).iodevice.type = 'test_provider';
            project.instances(1).iodevice.settings = struct('channel_id', 42);

            rendered = c2837x_block_render_dsp_instance_config_files(project);
            providerHeader = text_of(rendered(1).config_header_bytes);
            providerSource = text_of(rendered(1).config_source_bytes);
            w5300Header = text_of(rendered(2).config_header_bytes);
            rendererSource = fileread(which( ...
                'c2837x_block_render_dsp_instance_config_files'));

            testCase.verifyNotEmpty(strfind(providerHeader, ...
                '#define AXIS_X_TEST_CHANNEL_ID  42u'));
            testCase.verifyNotEmpty(strfind(providerSource, ...
                '&test_provider_iodevice_ops'));
            testCase.verifyNotEmpty(strfind(providerSource, ...
                '#include "test_provider_channel.h"'));
            testCase.verifyNotEmpty(strfind(w5300Header, ...
                '#define AXIS_Y_W5300_SOCKET_NUMBER  1u'));
            testCase.verifyNotEmpty(strfind(w5300Header, ...
                '#define AXIS_Y_TCP_PORT             5001u'));
            testCase.verifyEmpty(regexp(rendererSource, ...
                '(w5300_tcp|socket_number|tcp_port|C2837xW5300Channel|c2837x_w5300_iodevice_ops)', ...
                'once'));
        end

        function testProviderRoutingChangesOnlyItsInstance(testCase)
            project = make_project(testCase.WorkFolder, {'axis_x', 'axis_y'});
            first = c2837x_block_render_dsp_instance_config_files(project);
            changed = project;
            changed.instances(1).iodevice.settings.socket_number = uint16(7);
            changed.instances(1).iodevice.settings.tcp_port = uint16(6000);

            second = c2837x_block_render_dsp_instance_config_files(changed);

            testCase.verifyNotEqual(second(1).config_header_bytes, ...
                first(1).config_header_bytes);
            testCase.verifyEqual(second(1).user_config_header_bytes, ...
                first(1).user_config_header_bytes);
            testCase.verifyEqual(second(1).config_source_bytes, ...
                first(1).config_source_bytes);
            testCase.verifyEqual(second(2), first(2));
            testCase.verifyEqual(hash_literal(text_of( ...
                second(1).config_header_bytes)), hash_literal(text_of( ...
                first(1).config_header_bytes)));
        end

        function testRejectsInvalidProviderSupport(testCase)
            folder = fullfile(testCase.WorkFolder, 'bad-providers');
            mkdir(folder);
            write_bad_provider(folder, 'missing_support', ...
                'struct(''header_definitions'', '''')');
            write_bad_provider(folder, 'wrong_support', '42');
            addpath(folder, '-begin');
            testCase.addTeardown(@() cleanup_dynamic_path(folder));
            clear c2837x_block_iodevice_missing_support_definition
            clear c2837x_block_iodevice_wrong_support_definition
            rehash;
            missing = make_project(testCase.WorkFolder, {'axis_x'});
            missing.instances(1).iodevice.type = 'missing_support';
            missing.instances(1).iodevice.settings = struct('channel_id', 1);
            wrong = missing;
            wrong.instances(1).iodevice.type = 'wrong_support';

            testCase.verifyError( ...
                @() c2837x_block_render_dsp_instance_config_files(missing), ...
                'C2837xBlock:IoDevice:InvalidInstanceConfigSupport');
            testCase.verifyError( ...
                @() c2837x_block_render_dsp_instance_config_files(wrong), ...
                'C2837xBlock:IoDevice:InvalidInstanceConfigSupport');
        end

        function testCandidateBuilderRejectsMissingAndDuplicateRender(testCase)
            folder = fullfile(testCase.WorkFolder, 'shadow-renderer');
            mkdir(folder);
            addpath(folder, '-begin');
            testCase.addTeardown(@() cleanup_renderer_path(folder));
            project = make_project(testCase.WorkFolder, {'axis_x'});
            write_shadow_renderer(folder, 0);
            clear c2837x_block_render_dsp_instance_config_files
            rehash;

            testCase.verifyError(@() c2837x_block_build_dsp_candidates(project), ...
                'C2837xBlock:Generation:InstanceRenderMismatch');
            write_shadow_renderer(folder, 2);
            clear c2837x_block_render_dsp_instance_config_files
            rehash;
            testCase.verifyError(@() c2837x_block_build_dsp_candidates(project), ...
                'C2837xBlock:Generation:InstanceRenderMismatch');
        end

        function testUserConfigDefaultsAndProtection(testCase)
            project = make_project(testCase.WorkFolder, {'axis_x'});
            candidates = c2837x_block_build_dsp_candidates(project);
            user = candidates(endsWith({candidates.target_path}, ...
                'axis_x_user_config.h'));
            header = text_of(user.content_bytes);
            mkdir(fileparts(user.target_path));

            missing = c2837x_block_compare_candidate_files(user);
            write_bytes(user.target_path, user.content_bytes);
            same = c2837x_block_compare_candidate_files(user);
            write_bytes(user.target_path, uint8('custom'));
            different = c2837x_block_compare_candidate_files(user);

            testCase.verifyNotEmpty(strfind(header, 'USER-EDITABLE FILE'));
            testCase.verifyEqual(numel(regexp(header, '^#define (INTERACTION_TIMEOUT|TRANSFER_TIMEOUT)', ...
                'lineanchors')), 2);
            testCase.verifyNotEmpty(strfind(header, ...
                '#define INTERACTION_TIMEOUT  5000u'));
            testCase.verifyNotEmpty(strfind(header, ...
                '#define TRANSFER_TIMEOUT     1000u'));
            testCase.verifyEqual({missing.target_state, same.target_state, ...
                different.target_state}, {'missing', 'same', 'different'});
            testCase.verifyEqual({missing.default_action, same.default_action, ...
                different.default_action}, {'create', 'skip', 'keep'});
            testCase.verifyEqual([missing.action_mandatory, same.action_mandatory, ...
                different.action_mandatory], [true true false]);
        end

        function testTextDeterminismEncodingAndNoOutputDirectories(testCase)
            project = make_project(testCase.WorkFolder, ...
                {'axis_x', 'thermal_monitor'});
            strings = project;
            strings.instances(1).internal_name = "axis_x";
            strings.instances(2).internal_name = "thermal_monitor";

            first = c2837x_block_render_dsp_instance_config_files(project);
            second = c2837x_block_render_dsp_instance_config_files(project);
            stringResult = c2837x_block_render_dsp_instance_config_files(strings);

            testCase.verifyEqual(second, first);
            testCase.verifyEqual(stringResult, first);
            verify_rendered_bytes(testCase, first, project.output.dsp_root);
            testCase.verifyFalse(isfolder(project.output.dsp_root));
        end

        function testGeneratedObjectsAndTimeoutMatrixCompile(testCase)
            project = make_project(testCase.WorkFolder, ...
                {'axis_x', 'thermal_monitor'});

            compile_generated_objects(testCase, project);
            compile_timeout_matrix(testCase, project);
        end
    end
end

function verify_instance_files(testCase, project, candidates)
model = c2837x_block_build_dsp_output_model(project);
available = model.files([model.files.candidate_available]);
testCase.verifyEqual({candidates.target_path}, {available.target_path});
for index = 1:numel(project.instances)
    name = project.instances(index).internal_name;
    instance = model.files([model.files.instance_index] == index);
    testCase.verifyEqual({instance([instance.candidate_available]).relative_path}, ...
        {['inc/' name '_config.h'], ['inc/' name '_user_config.h'], ...
        ['inc/' name '_algorithm.h'], ['src/' name '_config.c'], ...
        ['src/' name '_algorithm.c']});
    testCase.verifyEqual({instance.category}, {'auto_generated', 'user', ...
        'auto_generated', 'auto_generated', 'auto_generated', 'user'});
    testCase.verifyEqual([instance.instance_index], index * ones(1, 6));
end
end

function verify_instance_symbols(testCase, source, name)
symbols = {['c2837x_block_' name '_config'], ...
    ['c2837x_block_' name '_algorithm_adapter'], ...
    ['c2837x_block_' name '_iodevice_channel'], ...
    ['c2837x_block_' name '_rx_frame_words'], ...
    ['c2837x_block_' name '_tx_frame_words'], ...
    ['c2837x_block_' name '_input_object'], ...
    ['c2837x_block_' name '_output_object'], ...
    ['c2837x_block_' name '_reset_io'], ...
    ['c2837x_block_' name '_on_start'], ...
    ['c2837x_block_' name '_decode_input'], ...
    ['c2837x_block_' name '_on_step'], ...
    ['c2837x_block_' name '_encode_output'], ...
    ['c2837x_block_' name '_on_stop']};
testCase.verifyTrue(all(cellfun(@(symbol) contains(source, symbol), symbols)));
end

function project = make_project(root, names)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([0 8 220 1 2 3]);
project.common.network.ip = '192.168.1.100';
project.common.network.gateway = '192.168.1.1';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));
template = c2837x_block_create_default_instance();
template.inputs = struct('name', 'command', 'type', 'single', 'dim', 1);
template.outputs = struct('name', 'feedback', 'type', 'double', 'dim', 1);
instances = repmat(template, 1, numel(names));
for index = 1:numel(names)
    instances(index).display_name = strrep(names{index}, '_', ' ');
    instances(index).internal_name = names{index};
    instances(index).iodevice.settings.socket_number = uint16(index - 1);
    instances(index).iodevice.settings.tcp_port = uint16(4999 + index);
end
project.instances = instances;
end

function value = render_texts(project, index)
rendered = c2837x_block_render_dsp_instance_config_files(project);
value = struct('header', text_of(rendered(index).config_header_bytes), ...
    'user', text_of(rendered(index).user_config_header_bytes), ...
    'source', text_of(rendered(index).config_source_bytes));
end

function value = hash_literal(header)
token = regexp(header, 'INTERFACE_HASH\s+\(\(Uint32\)(0x[0-9A-F]+)UL\)', ...
    'tokens', 'once');
assert(~isempty(token));
value = token{1};
end

function verify_rendered_bytes(testCase, rendered, forbiddenPath)
fields = {'config_header_bytes', 'user_config_header_bytes', ...
    'config_source_bytes'};
for index = 1:numel(rendered)
    for fieldIndex = 1:numel(fields)
        bytes = rendered(index).(fields{fieldIndex});
        text = text_of(bytes);
        testCase.verifyClass(bytes, 'uint8');
        testCase.verifySize(bytes, [1 numel(bytes)]);
        testCase.verifyFalse(starts_with(bytes, uint8([239 187 191])));
        testCase.verifyFalse(any(bytes == 13));
        testCase.verifyEqual(bytes(end), uint8(10));
        testCase.verifyTrue(isscalar(bytes) || bytes(end - 1) ~= uint8(10));
        testCase.verifyEmpty(regexp(text, '[ \t]+\n', 'once'));
        testCase.verifyEmpty(strfind(text, forbiddenPath));
    end
end
end

function compile_generated_objects(testCase, project)
[candidates, ~, issues] = c2837x_block_build_dsp_candidates(project);
testCase.assertEmpty(issues);
generatedInc = fullfile(testCase.WorkFolder, 'generated-inc');
generatedSrc = fullfile(testCase.WorkFolder, 'generated-src');
mkdir(generatedInc); mkdir(generatedSrc);
write_generated_candidates(candidates, generatedInc, generatedSrc);
mainPath = fullfile(testCase.WorkFolder, 'main.c');
write_text(mainPath, sprintf([ ...
    '#include "c2837x_block_project.h"\n' ...
    'void use_project(void) { C2837xBlock_Init(&g_axis_x); }\n']));
flags = include_flags(testCase.RepositoryRoot, generatedInc);
compile_ok(testCase, flags, fullfile(generatedSrc, ...
    'c2837x_block_project.c'), fullfile(testCase.WorkFolder, 'project.o'));
compile_ok(testCase, flags, mainPath, fullfile(testCase.WorkFolder, 'main.o'));
for index = 1:numel(project.instances)
    name = project.instances(index).internal_name;
    compile_ok(testCase, flags, fullfile(generatedSrc, [name '_config.c']), ...
        fullfile(testCase.WorkFolder, [name '.o']));
    compile_ok(testCase, flags, fullfile(generatedSrc, [name '_algorithm.c']), ...
        fullfile(testCase.WorkFolder, [name '-algorithm.o']));
end
end

function compile_timeout_matrix(testCase, project)
candidates = c2837x_block_build_dsp_candidates(project);
generatedInc = fullfile(testCase.WorkFolder, 'timeout-inc');
generatedSrc = fullfile(testCase.WorkFolder, 'timeout-src');
mkdir(generatedInc); mkdir(generatedSrc);
write_generated_candidates(candidates, generatedInc, generatedSrc);
flags = include_flags(testCase.RepositoryRoot, generatedInc);
source = fullfile(generatedSrc, 'axis_x_config.c');
userPath = fullfile(generatedInc, 'axis_x_user_config.h');
valid = {'1', '1000u', '5000u', '2147483u', '(1000u + 1u)'};
invalid = {'0', '-1', '2147484u', '1.5', 'UNDEFINED_TIMEOUT', ...
    '1.0', '1.0f', '1000.0', '(2.0 - 1.0)', '(0.0 / 0.0)'};
transferInvalid = {'1.0', '1.0f'};
for index = 1:numel(valid)
    write_timeout_header(userPath, valid{index}, valid{index});
    compile_ok(testCase, flags, source, fullfile(testCase.WorkFolder, ...
        sprintf('valid-%u.o', index)));
end
for index = 1:numel(invalid)
    write_timeout_header(userPath, invalid{index}, '1000u');
    compile_fails(testCase, flags, source, fullfile(testCase.WorkFolder, ...
        sprintf('invalid-%u.o', index)));
end
for index = 1:numel(transferInvalid)
    write_timeout_header(userPath, '1000u', transferInvalid{index});
    compile_fails(testCase, flags, source, fullfile(testCase.WorkFolder, ...
        sprintf('invalid-transfer-%u.o', index)));
end
write_timeout_header(userPath, '', '1000u');
compile_fails(testCase, flags, source, fullfile(testCase.WorkFolder, ...
    'missing-interaction.o'));
write_timeout_header(userPath, '1000u', '');
compile_fails(testCase, flags, source, fullfile(testCase.WorkFolder, ...
    'missing-transfer.o'));
header = text_of(candidate_bytes(candidates, 'axis_x_config.h'));
testCase.verifyNotEmpty(strfind(header, ...
    '((INTERACTION_TIMEOUT) % 1u) == 0u'));
testCase.verifyNotEmpty(strfind(header, ...
    '((TRANSFER_TIMEOUT) % 1u) == 0u'));
testCase.verifyNotEmpty(strfind(header, ...
    '(Uint32)(INTERACTION_TIMEOUT) * (Uint32)1000u'));
testCase.verifyNotEmpty(strfind(header, ...
    '(Uint32)(TRANSFER_TIMEOUT) * (Uint32)1000u'));
end

function write_generated_candidates(candidates, inc, src)
names = {'c2837x_block_project.h', 'c2837x_block_project.c', ...
    'axis_x_config.h', 'axis_x_user_config.h', 'axis_x_algorithm.h', ...
    'axis_x_config.c', 'axis_x_algorithm.c', ...
    'thermal_monitor_config.h', 'thermal_monitor_user_config.h', ...
    'thermal_monitor_algorithm.h', 'thermal_monitor_config.c', ...
    'thermal_monitor_algorithm.c'};
for index = 1:numel(names)
    bytes = candidate_bytes(candidates, names{index});
    if endsWith(names{index}, '.h')
        folder = inc;
    else
        folder = src;
    end
    write_bytes(fullfile(folder, names{index}), bytes);
end
end

function flags = include_flags(repositoryRoot, generatedInc)
flags = sprintf('-I"%s" -I"%s" -I"%s" -I"%s"', ...
    fullfile(repositoryRoot, 'tests', 'dsp_host', 'include'), ...
    fullfile(repositoryRoot, 'dsp', 'inc'), ...
    fullfile(repositoryRoot, 'dsp', 'src'), generatedInc);
end

function compile_ok(testCase, flags, source, object)
[status, output] = compile(flags, source, object);
testCase.verifyEqual(status, 0, output);
end

function compile_fails(testCase, flags, source, object)
[status, output] = compile(flags, source, object);
testCase.verifyNotEqual(status, 0, output);
end

function [status, output] = compile(flags, source, object)
[status, output] = system(sprintf( ...
    'gcc -std=c11 -Wall -Wextra -Werror %s -c "%s" -o "%s" 2>&1', ...
    flags, source, object));
end

function write_timeout_header(path, interaction, transfer)
text = '/* USER-EDITABLE FILE */';
text = [text newline];
if ~isempty(interaction)
    text = [text sprintf('#define INTERACTION_TIMEOUT %s\n', interaction)];
end
if ~isempty(transfer)
    text = [text sprintf('#define TRANSFER_TIMEOUT %s\n', transfer)];
end
write_text(path, text);
end

function write_bad_provider(folder, type, supportExpression)
text = sprintf([ ...
    'function d=c2837x_block_iodevice_%s_definition()\n' ...
    'd=struct(''type'',''%s'',''max_instance_count'',Inf,...\n' ...
    '''validate_settings'',@(varargin) [],...\n' ...
    '''collect_resource_claims'',@(varargin) [],...\n' ...
    '''render_project_support'',@(varargin) struct(''includes'',{{}},''source'',''''),...\n' ...
    '''render_instance_config_support'',@(varargin) %s);\nend\n'], ...
    type, type, supportExpression);
write_text(fullfile(folder, ...
    ['c2837x_block_iodevice_' type '_definition.m']), text);
end

function write_shadow_renderer(folder, count)
text = sprintf([ ...
    'function r=c2837x_block_render_dsp_instance_config_files(~)\n' ...
    'p=struct(''instance_index'',1,''internal_name'',''axis_x'',...\n' ...
    '''config_header_bytes'',uint8(10),''user_config_header_bytes'',uint8(10),...\n' ...
    '''config_source_bytes'',uint8(10));\n' ...
    'r=repmat(p,1,%u);\nend\n'], count);
write_text(fullfile(folder, ...
    'c2837x_block_render_dsp_instance_config_files.m'), text);
end

function cleanup_dynamic_path(folder)
rmpath(folder);
clear c2837x_block_iodevice_missing_support_definition
clear c2837x_block_iodevice_wrong_support_definition
rehash;
end

function cleanup_renderer_path(folder)
rmpath(folder);
clear c2837x_block_render_dsp_instance_config_files
rehash;
end

function bytes = candidate_bytes(candidates, name)
index = find(endsWith({candidates.target_path}, name), 1);
assert(~isempty(index));
bytes = candidates(index).content_bytes;
end

function text = text_of(bytes)
text = native2unicode(bytes, 'UTF-8');
end

function tf = starts_with(bytes, prefix)
tf = numel(bytes) >= numel(prefix) && isequal(bytes(1:numel(prefix)), prefix);
end

function write_text(path, text)
write_bytes(path, reshape(uint8(unicode2native(text, 'UTF-8')), 1, []));
end

function write_bytes(path, bytes)
fileID = fopen(path, 'wb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fwrite(fileID, bytes, 'uint8');
clear cleanup
end
