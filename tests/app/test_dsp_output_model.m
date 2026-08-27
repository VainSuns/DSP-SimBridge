classdef test_dsp_output_model < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
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
        function testCompleteFixedTreeAndMetadata(testCase)
            project = two_instance_project(testCase.WorkFolder);

            model = c2837x_block_build_dsp_output_model(project);

            verify_model(testCase, model, project);
        end

        function testDeterministicAndIgnoresUiState(testCase)
            project = two_instance_project(testCase.WorkFolder);
            first = c2837x_block_build_dsp_output_model(project);
            project.selected_instance = 2;

            second = c2837x_block_build_dsp_output_model(project);

            testCase.verifyEqual(second, first);
            testCase.verifyFalse(isfolder(project.output.dsp_root));
        end

        function testScalarStringNamesMatchCharacterNames(testCase)
            characterProject = two_instance_project(testCase.WorkFolder);
            stringProject = characterProject;
            stringProject.instances(1).internal_name = "current_loop";
            stringProject.instances(2).internal_name = "voltage_loop";

            characterModel = c2837x_block_build_dsp_output_model(characterProject);
            stringModel = c2837x_block_build_dsp_output_model(stringProject);

            testCase.verifyEqual(stringModel, characterModel);
            testCase.verifyTrue(all(cellfun(@is_char_row, ...
                {stringModel.files.relative_path})));
            testCase.verifyTrue(all(cellfun(@is_char_row, ...
                {stringModel.files.owner})));
            testCase.verifyTrue(all(cellfun(@is_char_row, ...
                {stringModel.files.target_path})));
            testCase.verifyTrue(all([stringModel.files(18:19).candidate_available]));
            testCase.verifyEqual(find([stringModel.files.candidate_available]), ...
                1:31);
            testCase.verifyFalse(isfolder(stringProject.output.dsp_root));
        end

        function testProjectPlatformConfigTracksActualIoDevices(testCase)
            w5300 = platform_project(testCase.WorkFolder, 'w5300');
            sci = platform_project(testCase.WorkFolder, 'sci');
            mixed = platform_project(testCase.WorkFolder, 'mixed');

            w5300Model = c2837x_block_build_dsp_output_model(w5300);
            sciModel = c2837x_block_build_dsp_output_model(sci);
            mixedModel = c2837x_block_build_dsp_output_model(mixed);

            testCase.verifyTrue(w5300Model.platform_config.use_w5300);
            testCase.verifyEmpty(w5300Model.platform_config.sci_descriptors);
            testCase.verifyEmpty(w5300Model.platform_config.sci_clock);
            testCase.verifyFalse(sciModel.platform_config.use_w5300);
            testCase.verifyNumElements( ...
                sciModel.platform_config.sci_descriptors, 1);
            testCase.verifyTrue(mixedModel.platform_config.use_w5300);
            testCase.verifyNumElements( ...
                mixedModel.platform_config.sci_descriptors, 1);

            descriptor = sciModel.platform_config.sci_descriptors;
            testCase.verifyEqual(descriptor.module, 'SCI-B');
            testCase.verifyEqual(descriptor.baud, uint32(115200));
            testCase.verifyEqual(descriptor.rx_gpio, 'GPIO19');
            testCase.verifyEqual(descriptor.tx_gpio, 'GPIO14');
            testCase.verifyEqual(descriptor.rx_pin_type, 'Standard');
            testCase.verifyEqual(descriptor.rx_qualification, 'Sync');
            testCase.verifyEqual(descriptor.tx_pin_type, 'Pull-up');
            testCase.verifyEqual(descriptor.ctrl_gpio, 'None');
            testCase.verifyEqual(descriptor.ctrl_pin_type, 'Standard');
            testCase.verifyEqual(descriptor.ctrl_tx_active_level, 'Low');
            testCase.verifyEqual( ...
                sciModel.platform_config.sci_clock.lspclk_divisor, 4);
            testCase.verifyEqual( ...
                sciModel.platform_config.sci_clock.lospcp_encoding, 2);
            platformFields = cellfun(@lower, ...
                fieldnames(sciModel.platform_config), 'UniformOutput', false);
            descriptorFields = cellfun(@lower, fieldnames(descriptor), ...
                'UniformOutput', false);
            testCase.verifyFalse(any(contains(platformFields, ...
                {'com', 'pin_group'})));
            testCase.verifyFalse(any(contains(descriptorFields, ...
                {'com', 'pin_group'})));
        end

        function testProjectRendererUsesCoreV2AndPlatformConfig(testCase)
            project = platform_project(testCase.WorkFolder, 'mixed');
            rendered = c2837x_block_render_dsp_project_files(project);
            header = native2unicode(rendered.header_bytes, 'UTF-8');
            source = native2unicode(rendered.source_bytes, 'UTF-8');

            testCase.verifyNotEmpty(regexp(header, ...
                'C2837X_BLOCK_EXPECTED_CORE_API_VERSION\s+2u', 'once'));
            testCase.verifyNotEmpty(regexp(header, ...
                'C2837X_BLOCK_PLATFORM_HAS_W5300\s+1u', 'once'));
            testCase.verifyNotEmpty(regexp(header, ...
                'C2837X_BLOCK_PLATFORM_HAS_SCI\s+1u', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'C2837X_BLOCK_EXPECTED_CORE_API_VERSION\s+2u', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'C2837xBlock_PlatformConfig', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'c2837x_block_project_sci_descriptors,\s*1u', 'once'));
            testCase.verifyEmpty(regexp(lower([header source]), ...
                '\b(com|pin_group)\b', 'once'));
        end

        function testRejectsPathEscapingInstanceName(testCase)
            project = two_instance_project(testCase.WorkFolder);
            project.instances(1).internal_name = '../escape';

            testCase.verifyError( ...
                @() c2837x_block_build_dsp_output_model(project), ...
                'C2837xBlock:DspOutput:InvalidInstanceName');
        end

        function testRejectsNoncanonicalRoot(testCase)
            project = two_instance_project(testCase.WorkFolder);
            project.output.dsp_root = fullfile(testCase.WorkFolder, 'a', '..', 'dsp');

            testCase.verifyError( ...
                @() c2837x_block_build_dsp_output_model(project), ...
                'C2837xBlock:Project:InvalidPath');
        end
    end
end

function verify_model(testCase, model, project)
corePaths = fixed_core_paths();
projectPaths = {'inc/c2837x_block_project.h', ...
    'src/c2837x_block_project.c'};
instanceSuffixes = {'inc/%s_config.h', 'inc/%s_user_config.h', ...
    'inc/%s_algorithm.h', 'src/%s_config.c', 'src/%s_io.c', ...
    'src/%s_algorithm.c'};
instancePaths = cell(1, 12);
for instanceIndex = 1:2
    for suffixIndex = 1:6
        instancePaths{(instanceIndex - 1) * 6 + suffixIndex} = sprintf( ...
            instanceSuffixes{suffixIndex}, ...
            project.instances(instanceIndex).internal_name);
    end
end
expectedPaths = [corePaths projectPaths instancePaths];

testCase.verifyEqual(model.schema_version, uint16(1));
testCase.verifyEqual(model.dsp_root, project.output.dsp_root);
testCase.verifyEqual(model.inc_root, fullfile(project.output.dsp_root, 'inc'));
testCase.verifyEqual(model.src_root, fullfile(project.output.dsp_root, 'src'));
testCase.verifyEqual({model.files.relative_path}, expectedPaths);
testCase.verifyEqual({model.files(1:17).category}, repmat({'core'}, 1, 17));
testCase.verifyEqual({model.files(18:19).category}, ...
    repmat({'auto_generated'}, 1, 2));
testCase.verifyEqual({model.files(20:25).category}, ...
    {'auto_generated', 'user', 'auto_generated', ...
    'auto_generated', 'auto_generated', 'user'});
testCase.verifyEqual({model.files(26:31).category}, ...
    {model.files(20:25).category});
testCase.verifyEqual({model.files(1:17).file_scope}, repmat({'core'}, 1, 17));
testCase.verifyEqual({model.files(18:19).file_scope}, repmat({'project'}, 1, 2));
testCase.verifyEqual({model.files(20:31).file_scope}, repmat({'instance'}, 1, 12));
testCase.verifyEqual([model.files.instance_index], [zeros(1, 19) ones(1, 6) 2 * ones(1, 6)]);
testCase.verifyEqual([model.files.candidate_available], ...
    true(1, 31));
testCase.verifyEqual(numel(unique({model.files.owner})), 31);
testCase.verifyEqual(numel(unique(lower_cell({model.files.target_path}))), 31);
testCase.verifyTrue(all(cellfun(@(path) path_below(project.output.dsp_root, path), ...
    {model.files.target_path})));
testCase.verifyFalse(any(contains({model.files.relative_path}, 'main.c')));
testCase.verifyFalse(any(contains(lower_cell({model.files.relative_path}), ...
    {'ccs', 'linker'}), 'all'));
testCase.verifyEmpty(intersect({model.files.relative_path}, excluded_paths()));
testCase.verifyTrue(all(cellfun(@isfile, {model.files(1:17).source_path})));
testCase.verifyTrue(all(cellfun(@isempty, {model.files(18:31).source_path})));
testCase.verifyEqual({model.files(18:31).responsibility}, ...
    expected_noncore_responsibilities());
testCase.verifyTrue(all(contains({model.files([24 30]).responsibility}, ...
    {'serialization', 'IoDevice channel binding'}), 'all'));
testCase.verifyFalse(any(contains({model.files([24 30]).responsibility}, ...
    'adapter')));
testCase.verifyTrue(all(contains({model.files([20 23 26 29]).responsibility}, ...
    {'sizes', 'Interface Hash', 'adapter', 'static bind'}), 'all'));
end

function project = two_instance_project(root)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
first = c2837x_block_create_default_instance();
first.display_name = 'Current Loop';
first.internal_name = 'current_loop';
second = first;
second.display_name = 'Voltage Loop';
second.internal_name = 'voltage_loop';
second.iodevice.settings.socket_number = uint16(1);
second.iodevice.settings.tcp_port = uint16(5001);
project.instances = [first second];
end

function project = platform_project(root, mode)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, [mode '_dsp']));

w5300 = c2837x_block_create_default_instance();
w5300.display_name = 'Network';
w5300.internal_name = 'network';

sci = c2837x_block_create_default_instance();
sci.display_name = 'Serial';
sci.internal_name = 'serial';
sci.iodevice = c2837x_block_create_iodevice('sci');
sci.iodevice.settings.module = 'SCI-B';
sci.iodevice.settings.baud = uint32(115200);
sci.iodevice.settings.rx_gpio = 'GPIO19';
sci.iodevice.settings.tx_gpio = 'GPIO14';
sci.iodevice.settings.rx_pin_type = 'Standard';
sci.iodevice.settings.rx_qualification = 'Sync';
sci.iodevice.settings.tx_pin_type = 'Pull-up';
sci.iodevice.settings.ctrl_gpio = 'None';
sci.iodevice.settings.ctrl_pin_type = 'Standard';
sci.iodevice.settings.ctrl_tx_active_level = 'Low';

switch mode
    case 'w5300'
        project.instances = w5300;
    case 'sci'
        project.instances = sci;
    case 'mixed'
        project.instances = [w5300 sci];
    otherwise
        error('test_dsp_output_model:InvalidMode', 'Unknown platform mode.');
end
end

function paths = fixed_core_paths()
paths = {'inc/c2837x_block.h', 'inc/c2837x_block_protocol.h', ...
    'inc/c2837x_block_iodevice.h', 'inc/c2837x_w5300_regs.h', ...
    'inc/c2837x_w5300_hal.h', 'inc/c2837x_w5300_socket.h', ...
    'inc/c2837x_w5300_channel.h', 'src/c2837x_block.c', ...
    'src/c2837x_block_protocol.c', 'src/c2837x_block_internal.h', ...
    'src/c2837x_block_config_internal.h', 'src/c2837x_block_platform.h', ...
    'src/c2837x_block_platform.c', 'src/c2837x_block_timer2.c', ...
    'src/c2837x_w5300_hal.c', 'src/c2837x_w5300_socket.c', ...
    'src/c2837x_w5300_channel.c'};
end

function paths = excluded_paths()
paths = {'inc/c2837x_block_algorithm.h', 'inc/c2837x_block_config.h', ...
    'src/c2837x_block_config.c', 'src/c2837x_block_global_variable.c', ...
    'src/my_algorithm.c'};
end

function values = expected_noncore_responsibilities()
projectValues = { ...
    ['Project instance exports and project-level public ' ...
    'configuration declarations.'], ...
    ['Project instance definitions, static bindings, and ' ...
    'project-level public configuration.']};
instanceValues = { ...
    ['Instance sizes, Interface Hash, adapter declarations, and static ' ...
    'binding declarations.'], ...
    'User-editable DSP timeout configuration.', ...
    ['Authoritative typed algorithm structures and callback ' ...
    'declarations.'], ...
    ['Instance sizes, Interface Hash, adapter definitions, and static ' ...
    'bindings.'], ...
    'Instance serialization and IoDevice channel binding.', ...
    'User algorithm implementation.'};
values = [projectValues instanceValues instanceValues];
end

function tf = is_char_row(value)
tf = ischar(value) && isrow(value);
end

function values = lower_cell(values)
values = cellfun(@lower, values, 'UniformOutput', false);
end

function tf = path_below(root, path)
prefix = [root filesep];
if ispc
    tf = startsWith(path, prefix, 'IgnoreCase', true);
else
    tf = startsWith(path, prefix);
end
end
