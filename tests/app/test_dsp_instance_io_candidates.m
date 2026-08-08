classdef test_dsp_instance_io_candidates < matlab.unittest.TestCase
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
        function testWireLayoutAndMemoryReport(testCase)
            project = wire_project(testCase.WorkFolder, {'axis_x', 'axis_y'});
            project.instances(2).inputs = struct( ...
                'name', 'small_in', 'type', 'uint16', 'dim', 1);
            project.instances(2).outputs = struct( ...
                'name', 'small_out', 'type', 'uint16', 'dim', 1);

            layout = c2837x_block_build_dsp_wire_layout(project);
            repeated = c2837x_block_build_dsp_wire_layout(project);

            testCase.verifyEqual(repeated, layout);
            testCase.verifyEqual(layout.schema_version, uint16(1));
            testCase.verifyEqual([layout.instances.input_data_octets], [88 2]);
            testCase.verifyEqual([layout.instances.output_data_octets], [88 2]);
            testCase.verifyEqual([layout.instances.input_payload_octets], [92 6]);
            testCase.verifyEqual([layout.instances.output_payload_octets], [92 6]);
            testCase.verifyEqual([layout.instances.rx_frame_words], [48 5]);
            testCase.verifyEqual([layout.instances.tx_frame_words], [48 5]);
            testCase.verifyEqual([layout.instances.protocol_buffer_words], [96 10]);
            testCase.verifyEqual(layout.project_protocol_buffer_words, 106);
            testCase.verifyEqual([layout.instances(1).input_fields.offset_words], ...
                [0 1 2 6 8 20]);

            changedLimit = project;
            changedLimit.instances(1).max_payload_size_bytes = uint32(2048);
            changedLimit.instances(1).interface_hash = uint32(1);
            changed = c2837x_block_build_dsp_wire_layout(changedLimit);
            testCase.verifyEqual(changed.instances(1).rx_frame_words, 48);
            testCase.verifyEqual(changed.instances(1).tx_frame_words, 48);
            testCase.verifyEqual(changed.project_protocol_buffer_words, 106);
        end

        function testMaximumLegalWireLayout(testCase)
            project = wire_project(testCase.WorkFolder, {'axis_x'});
            project.instances.inputs = struct( ...
                'name', 'maximum_in', 'type', 'uint16', 'dim', 32765);
            project.instances.outputs = struct( ...
                'name', 'maximum_out', 'type', 'uint16', 'dim', 32765);
            project.instances.max_payload_size_bytes = uint32(65534);

            layout = c2837x_block_build_dsp_wire_layout(project);

            testCase.verifyEqual(layout.instances.input_data_octets, 65530);
            testCase.verifyEqual(layout.instances.output_data_octets, 65530);
            testCase.verifyEqual(layout.instances.input_payload_octets, 65534);
            testCase.verifyEqual(layout.instances.output_payload_octets, 65534);
            testCase.verifyEqual(layout.instances.rx_frame_octets, 65538);
            testCase.verifyEqual(layout.instances.tx_frame_octets, 65538);
            testCase.verifyEqual(layout.instances.rx_frame_words, 32769);
            testCase.verifyEqual(layout.instances.tx_frame_words, 32769);
        end

        function testRendererContractAndIsolation(testCase)
            project = wire_project(testCase.WorkFolder, {'axis_x'});
            first = c2837x_block_render_dsp_instance_io_files(project);
            second = c2837x_block_render_dsp_instance_io_files(project);
            text = native2unicode(first.io_source_bytes, 'UTF-8');

            testCase.verifyEqual(second, first);
            testCase.verifyFalse(any(first.io_source_bytes == 13));
            testCase.verifyEqual(first.io_source_bytes(end), uint8(10));
            testCase.verifyNotEmpty(strfind(text, ...
                'sizeof(long double) * CHAR_BIT == 64'));
            testCase.verifyNotEmpty(strfind(text, ...
                '((Uint32)AXIS_X_RX_FRAME_WORDS * (Uint32)2u)'));
            testCase.verifyNotEmpty(strfind(text, ...
                '((Uint32)AXIS_X_TX_FRAME_WORDS * (Uint32)2u)'));
            testCase.verifyEmpty(strfind(text, ...
                'AXIS_X_RX_FRAME_WORDS * 2u =='));
            testCase.verifyEmpty(strfind(text, ...
                'AXIS_X_TX_FRAME_WORDS * 2u =='));
            testCase.verifyNotEmpty(strfind(text, 'TestProviderChannel'));
            testCase.verifyEmpty(regexp(text, ...
                '(W5300|malloc|calloc|realloc|free|uint8_t\s+\w*frame|step_index)', ...
                'once'));

            ignored = project;
            ignored.instances.display_name = 'ignored';
            ignored.instances.sample_time_sec = 0.25;
            ignored.instances.max_payload_size_bytes = uint32(2048);
            ignored.instances.interface_hash = uint32(99);
            ignored.instances.iodevice.settings.channel_id = 99;
            ignored.instances.algorithm.mode = 'external_reference';
            ignored.instances.algorithm.source_path = ...
                c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'ignored.c'));
            ignored.common.abi = 'coffabi';
            ignored.common.network.ip = '10.0.0.1';
            ignored.output.dsp_root = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'other'));
            ignored.output.sfun_root = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'other_sfun'));
            testCase.verifyEqual( ...
                c2837x_block_render_dsp_instance_io_files(ignored), first);

            changed = project;
            changed.instances.outputs(1:2) = changed.instances.outputs([2 1]);
            testCase.verifyNotEqual( ...
                c2837x_block_render_dsp_instance_io_files(changed), first);

            w5300 = project;
            w5300.instances.iodevice.type = 'w5300_tcp';
            w5300.instances.iodevice.settings = struct( ...
                'socket_number', uint16(0), 'tcp_port', uint16(5000));
            firstW5300 = c2837x_block_render_dsp_instance_io_files(w5300);
            w5300.instances.iodevice.settings.socket_number = uint16(7);
            w5300.instances.iodevice.settings.tcp_port = uint16(65535);
            testCase.verifyEqual( ...
                c2837x_block_render_dsp_instance_io_files(w5300), firstW5300);
        end

        function testGeneratedContractsAndSingleEvaluation(testCase)
            project = wire_project(testCase.WorkFolder, {'axis_x'});
            rendered = c2837x_block_render_dsp_instance_io_files(project);
            text = native2unicode(rendered.io_source_bytes, 'UTF-8');

            testCase.verifyTrue(contains(text, ...
                'void c2837x_block_axis_x_decode_input('));
            testCase.verifyTrue(contains(text, ...
                'AxisX_InputData *input = (AxisX_InputData *)input_object;'));
            testCase.verifyTrue(contains(text, ...
                'void c2837x_block_axis_x_encode_output('));
            testCase.verifyTrue(contains(text, ...
                'const AxisX_OutputData *output = (const AxisX_OutputData *)output_object;'));
            testCase.verifyEmpty(regexp(text, [ ...
                'InputData decoded|decoded\.|input_object\s*==|user_data_words\s*==|' ...
                'user_data_octets|user_data_capacity_octets|return -1;|return 0;|' ...
                'memset\s*\(\s*input_object|memcpy\s*\([^;]*input|' ...
                '\*\s*\([^;]*InputData[^;]*\)\s*input_object'], 'once'));

            testCase.verifyTrue(contains(text, 'input->i_i16v'));
            testCase.verifyTrue(contains(text, 'input->i_u16v'));
            testCase.verifyEqual(numel(regexp(text, ...
                'input->i_i32v\[[01]\]', 'match')), 2);
            testCase.verifyTrue(contains(text, 'input->i_u32v'));
            testCase.verifyEqual(numel(regexp(text, ...
                'input->i_f32v\[[0-5]\]', 'match')), 6);
            testCase.verifyEqual(numel(regexp(text, ...
                'input->i_f64v\[[0-5]\]', 'match')), 6);

            testCase.verifyEqual(numel(regexp(text, ...
                'uint32_t bits = c2837x_block_encode_int32\(output->o_i32v\[[01]\]\);', ...
                'match')), 2);
            testCase.verifyEqual(numel(regexp(text, ...
                'uint32_t bits = \(uint32_t\)output->o_u32v;', 'match')), 1);
            testCase.verifyEqual(numel(regexp(text, ...
                'uint32_t bits = c2837x_block_encode_single\(output->o_f32v\[[0-5]\]\);', ...
                'match')), 6);
            testCase.verifyEqual(numel(regexp(text, ...
                'uint64_t bits = c2837x_block_encode_double\(output->o_f64v\[[0-5]\]\);', ...
                'match')), 6);
            testCase.verifyEmpty(regexp(text, ...
                'user_data_words\[[0-9]+u\][^\n]*c2837x_block_encode_(int32|single|double)', ...
                'once'));
        end

        function testGoldenWireAndGeneratedObjects(testCase)
            project = wire_project(testCase.WorkFolder, {'axis_x'});
            candidates = c2837x_block_build_dsp_candidates(project);
            write_candidates(candidates);
            generatedInc = fullfile(project.output.dsp_root, 'inc');
            generatedSrc = fullfile(project.output.dsp_root, 'src');
            hostInclude = fullfile(testCase.RepositoryRoot, 'tests', ...
                'dsp_host', 'include');
            flags = sprintf('-std=c11 -O2 -Wall -Wextra -Werror -fstrict-aliasing -Wstrict-aliasing=2 -mlong-double-64 -I"%s" -I"%s" -I"%s" -I"%s"', ...
                hostInclude, fullfile(testCase.RepositoryRoot, 'dsp', 'inc'), ...
                fullfile(testCase.RepositoryRoot, 'dsp', 'src'), generatedInc);
            probeObject = fullfile(testCase.WorkFolder, 'long_double_probe.o');
            [probeStatus, probeOutput] = system(sprintf( ...
                'echo int x;| gcc -mlong-double-64 -x c -c - -o "%s" 2>&1', ...
                probeObject));
            testCase.assumeEqual(probeStatus, 0, probeOutput);

            harness = fullfile(testCase.RepositoryRoot, 'tests', ...
                'dsp_host', 's3_05_wire_test.c');
            executable = fullfile(testCase.WorkFolder, 's3_05_wire.exe');
            [status, output] = system(sprintf('gcc %s "%s" "%s" -o "%s" 2>&1', ...
                flags, fullfile(generatedSrc, 'axis_x_io.c'), harness, executable));
            testCase.assertEqual(status, 0, output);
            [status, output] = system(sprintf('"%s" 2>&1', executable));
            testCase.verifyEqual(status, 0, output);
            testCase.verifySubstring(output, 's3_05_wire=ok');

            objects = {'c2837x_block_project.c', 'axis_x_config.c', ...
                'axis_x_io.c', 'axis_x_algorithm.c'};
            for index = 1:numel(objects)
                source = fullfile(generatedSrc, objects{index});
                object = fullfile(testCase.WorkFolder, [objects{index} '.o']);
                [status, output] = system(sprintf( ...
                    'gcc %s -c "%s" -o "%s" 2>&1', flags, source, object));
                testCase.verifyEqual(status, 0, output);
            end
        end

        function testGeneratedDualInstanceCoreBinding(testCase)
            project = binding_project(testCase.WorkFolder);
            candidates = c2837x_block_build_dsp_candidates(project);
            write_candidates(candidates);
            generatedInc = fullfile(project.output.dsp_root, 'inc');
            generatedSrc = fullfile(project.output.dsp_root, 'src');
            flags = sprintf(['-std=c11 -O2 -Wall -Wextra -Werror ' ...
                '-fstrict-aliasing -Wstrict-aliasing=2 -mlong-double-64 ' ...
                '-I"%s" -I"%s" -I"%s" -I"%s"'], ...
                fullfile(testCase.RepositoryRoot, 'tests', 'dsp_host', 'include'), ...
                fullfile(testCase.RepositoryRoot, 'dsp', 'inc'), ...
                fullfile(testCase.RepositoryRoot, 'dsp', 'src'), generatedInc);
            sources = { ...
                fullfile(testCase.RepositoryRoot, 'tests', 'dsp_host', ...
                's3_05_generated_binding_test.c'), ...
                fullfile(testCase.RepositoryRoot, 'dsp', 'src', 'c2837x_block.c'), ...
                fullfile(testCase.RepositoryRoot, 'dsp', 'src', ...
                'c2837x_block_protocol.c'), ...
                fullfile(generatedSrc, 'c2837x_block_project.c'), ...
                fullfile(generatedSrc, 'axis_a_config.c'), ...
                fullfile(generatedSrc, 'axis_a_io.c'), ...
                fullfile(generatedSrc, 'axis_a_algorithm.c'), ...
                fullfile(generatedSrc, 'axis_b_config.c'), ...
                fullfile(generatedSrc, 'axis_b_io.c'), ...
                fullfile(generatedSrc, 'axis_b_algorithm.c')};
            quoted = cellfun(@(path) ['"' path '"'], sources, ...
                'UniformOutput', false);
            executable = fullfile(testCase.WorkFolder, 'generated_binding.exe');
            [status, output] = system(sprintf('gcc %s %s -o "%s" 2>&1', ...
                flags, strjoin(quoted, ' '), executable));
            testCase.assertEqual(status, 0, output);
            [status, output] = system(sprintf('"%s" 2>&1', executable));
            testCase.verifyEqual(status, 0, output);
            testCase.verifySubstring(output, 's3_05_generated_binding=ok');
        end

        function testCandidateBuilderRejectsMissingAndDuplicateIoRender(testCase)
            folder = fullfile(testCase.WorkFolder, 'shadow-renderer');
            mkdir(folder);
            addpath(folder, '-begin');
            testCase.addTeardown(@() cleanup_renderer_path(folder));
            project = wire_project(testCase.WorkFolder, {'axis_x'});
            write_shadow_renderer(folder, 0);
            clear c2837x_block_render_dsp_instance_io_files
            rehash;
            testCase.verifyError(@() c2837x_block_build_dsp_candidates(project), ...
                'C2837xBlock:Generation:InstanceRenderMismatch');

            write_shadow_renderer(folder, 2);
            clear c2837x_block_render_dsp_instance_io_files
            rehash;
            testCase.verifyError(@() c2837x_block_build_dsp_candidates(project), ...
                'C2837xBlock:Generation:InstanceRenderMismatch');
        end
    end
end

function project = binding_project(root)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'binding_dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'binding_sfun'));
template = c2837x_block_create_default_instance();
template.iodevice.type = 'test_provider';
template.iodevice.settings = struct('channel_id', 42);
template.inputs = struct('name', 'a_in', 'type', 'uint16', 'dim', 1);
template.outputs = struct('name', 'a_out', 'type', 'uint16', 'dim', 1);
template.display_name = 'Axis A';
template.internal_name = 'axis_a';
second = template;
second.display_name = 'Axis B';
second.internal_name = 'axis_b';
second.inputs.name = 'b_in';
second.outputs.name = 'b_out';
project.instances = [template second];
end

function project = wire_project(root, names)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));
template = c2837x_block_create_default_instance();
template.iodevice.type = 'test_provider';
template.iodevice.settings = struct('channel_id', 42);
template.inputs = variables('i');
template.outputs = variables('o');
template.max_payload_size_bytes = uint32(1024);
instances = repmat(template, 1, numel(names));
for index = 1:numel(names)
    instances(index).display_name = names{index};
    instances(index).internal_name = names{index};
end
project.instances = instances;
end

function values = variables(prefix)
values = struct( ...
    'name', {[prefix '_i16v'], [prefix '_u16v'], [prefix '_i32v'], ...
    [prefix '_u32v'], [prefix '_f32v'], [prefix '_f64v']}, ...
    'type', {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'}, ...
    'dim', {1, 1, 2, 1, 6, 6});
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

function write_shadow_renderer(folder, count)
text = sprintf([ ...
    'function r=c2837x_block_render_dsp_instance_io_files(~)\n' ...
    'p=struct(''instance_index'',1,''internal_name'',''axis_x'',...\n' ...
    '''io_source_bytes'',uint8(10));\n' ...
    'r=repmat(p,1,%u);\nend\n'], count);
path = fullfile(folder, 'c2837x_block_render_dsp_instance_io_files.m');
fileID = fopen(path, 'wb'); assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fwrite(fileID, unicode2native(text, 'UTF-8'), 'uint8');
clear cleanup
end

function cleanup_renderer_path(folder)
rmpath(folder);
clear c2837x_block_render_dsp_instance_io_files
rehash;
end
