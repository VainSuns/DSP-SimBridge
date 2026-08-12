classdef test_sci_iodevice_validation < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    properties (TestParameter)
        invalidSetting = struct( ...
            'baud', struct('field', 'baud', 'value', uint32(4800), ...
                'code', 'SCI_BAUD_INVALID'), ...
            'rxPinType', struct('field', 'rx_pin_type', ...
                'value', 'Open Drain', 'code', 'SCI_RX_PIN_TYPE_INVALID'), ...
            'txPinType', struct('field', 'tx_pin_type', ...
                'value', 'Open-drain', 'code', 'SCI_TX_PIN_TYPE_INVALID'), ...
            'ctrlPinType', struct('field', 'ctrl_pin_type', ...
                'value', 'Open Drain', 'code', 'SCI_CTRL_PIN_TYPE_INVALID'), ...
            'qualification', struct('field', 'rx_qualification', ...
                'value', '3-sample', 'code', ...
                'SCI_RX_QUALIFICATION_INVALID'), ...
            'activeLevel', struct('field', 'ctrl_tx_active_level', ...
                'value', 'Invert', 'code', ...
                'SCI_CTRL_ACTIVE_LEVEL_INVALID'))
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
        function testDefinitionContract(testCase)
            definition = c2837x_block_get_iodevice_definition('sci');

            testCase.verifyEqual(definition.type, 'sci');
            testCase.verifyEqual(definition.max_instance_count, 4);
            testCase.verifyTrue(all(isfield(definition, {'validate_settings', ...
                'collect_resource_claims', 'render_project_support', ...
                'render_instance_config_support', ...
                'render_instance_io_support'})));
        end

        function testValidSettingsAndNormalizedPinGroup(testCase)
            project = project_with_instances(sci_instance( ...
                'sci_a', 'SCI-A', 'SCI-A_TX8_RX9'));

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyEmpty(issues);
        end

        function testScalarStringSettingsMatchCharSemantics(testCase)
            instance = sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9');
            instance.iodevice.settings.module = "SCI-A";
            instance.iodevice.settings.pin_group = "SCI-A_TX8_RX9";
            instance.iodevice.settings.rx_pin_type = "Standard";
            instance.iodevice.settings.rx_qualification = "Sync";
            instance.iodevice.settings.tx_pin_type = "Pull-up";
            instance.iodevice.settings.ctrl_gpio = "None";
            instance.iodevice.settings.ctrl_pin_type = "Standard";
            instance.iodevice.settings.ctrl_tx_active_level = "Low";
            project = project_with_instances(instance);

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyEmpty(issues);
        end

        function testModuleRequired(testCase)
            instance = sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9');
            instance.iodevice.settings.module = '';
            project = project_with_instances(instance);

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyTrue(has_code(issues, 'SCI_MODULE_REQUIRED'));
        end

        function testModuleInvalid(testCase)
            instance = sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9');
            instance.iodevice.settings.module = 'SCI-E';
            project = project_with_instances(instance);

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyTrue(has_code(issues, 'SCI_MODULE_INVALID'));
        end

        function testPinGroupRequired(testCase)
            instance = sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9');
            instance.iodevice.settings.pin_group = '';
            project = project_with_instances(instance);

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyTrue(has_code(issues, 'SCI_PIN_GROUP_REQUIRED'));
        end

        function testPinGroupMustBelongToSelectedModule(testCase)
            project = project_with_instances(sci_instance( ...
                'sci_a', 'SCI-A', 'SCI-B_TX9_RX11'));

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyTrue(has_code(issues, 'SCI_PIN_GROUP_INVALID'));
        end

        function testFrozenSettingValueIsEnforced(testCase, invalidSetting)
            instance = sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9');
            instance.iodevice.settings.(invalidSetting.field) = invalidSetting.value;
            project = project_with_instances(instance);

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyTrue(has_code(issues, invalidSetting.code));
        end

        function testCtrlGpioMustBeCanonicalAndCapable(testCase)
            instance = sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9');
            instance.iodevice.settings.ctrl_gpio = 'GPIO168';
            project = project_with_instances(instance);

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyTrue(has_code(issues, 'SCI_CTRL_GPIO_INVALID'));
        end

        function testDuplicateModule(testCase)
            first = sci_instance('first', 'SCI-A', 'SCI-A_TX8_RX9');
            second = sci_instance('second', 'SCI-A', 'SCI-A_TX29_RX28');
            project = project_with_instances([first second]);

            issues = c2837x_block_validate_project(project, 'instant');

            duplicate = issues(strcmp({issues.code}, 'SCI_MODULE_DUPLICATE'));
            testCase.verifyNumElements(duplicate, 1);
            testCase.verifyEqual(duplicate.instance_index, 2);
            testCase.verifyEqual(duplicate.field_path, ...
                'project.instances(2).iodevice.settings.module');
        end

        function testTwoSciPinGroupsConflictOnSharedGpio(testCase)
            first = sci_instance('first', 'SCI-A', 'SCI-A_TX8_RX9');
            second = sci_instance('second', 'SCI-B', 'SCI-B_TX9_RX11');
            project = project_with_instances([first second]);

            issues = c2837x_block_validate_project(project, 'instant');

            conflict = issues(strcmp({issues.code}, 'SCI_GPIO_CONFLICT'));
            testCase.verifyNumElements(conflict, 1);
            testCase.verifyEqual(conflict.instance_index, 2);
            testCase.verifyEqual(conflict.field_path, ...
                'project.instances(2).iodevice.settings.pin_group');
            testCase.verifyNotEmpty(strfind(conflict.message, 'GPIO9'));
        end

        function testCtrlConflictsWithOwnTx(testCase)
            instance = sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9');
            instance.iodevice.settings.ctrl_gpio = 'GPIO8';
            project = project_with_instances(instance);

            issues = c2837x_block_validate_project(project, 'instant');

            conflict = issues(strcmp({issues.code}, 'SCI_GPIO_CONFLICT'));
            testCase.verifyNumElements(conflict, 1);
            testCase.verifyEqual(conflict.field_path, ...
                'project.instances(1).iodevice.settings.ctrl_gpio');
        end

        function testCtrlConflictsWithAnotherSciPinGroup(testCase)
            first = sci_instance('first', 'SCI-A', 'SCI-A_TX8_RX9');
            first.iodevice.settings.ctrl_gpio = 'GPIO11';
            second = sci_instance('second', 'SCI-B', 'SCI-B_TX10_RX11');
            project = project_with_instances([first second]);

            issues = c2837x_block_validate_project(project, 'instant');

            conflict = issues(strcmp({issues.code}, 'SCI_GPIO_CONFLICT'));
            testCase.verifyNumElements(conflict, 1);
            testCase.verifyEqual(conflict.instance_index, 2);
            testCase.verifyEqual(conflict.field_path, ...
                'project.instances(2).iodevice.settings.pin_group');
        end

        function testMixedProjectConflictsWithActiveW5300Gpio(testCase)
            w5300 = w5300_instance('network');
            sci = sci_instance('sci_a', 'SCI-A', 'SCI-A_TX29_RX28');
            project = project_with_instances([w5300 sci]);

            issues = c2837x_block_validate_project(project, 'instant');

            conflict = issues(strcmp({issues.code}, 'SCI_GPIO_CONFLICT'));
            testCase.verifyNumElements(conflict, 2);
            testCase.verifyTrue(all([conflict.instance_index] == 2));
            testCase.verifyTrue(all(strcmp({conflict.field_path}, ...
                'project.instances(2).iodevice.settings.pin_group')));
        end

        function testMixedProjectAllowsNonreservedSciGpios(testCase)
            w5300 = w5300_instance('network');
            sci = sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9');
            project = project_with_instances([w5300 sci]);

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyFalse(has_code(issues, 'SCI_GPIO_CONFLICT'));
        end

        function testSciOnlyMayUseW5300ReservedGpios(testCase)
            project = project_with_instances(sci_instance( ...
                'sci_a', 'SCI-A', 'SCI-A_TX29_RX28'));

            issues = c2837x_block_validate_project(project, 'instant');

            testCase.verifyFalse(has_code(issues, 'SCI_GPIO_CONFLICT'));
        end

        function testNetworkValidationRemainsConditional(testCase)
            sciProject = invalid_network_project(sci_instance( ...
                'sci_a', 'SCI-A', 'SCI-A_TX8_RX9'));
            w5300Project = invalid_network_project(w5300_instance('network'));
            mixedProject = invalid_network_project([w5300_instance('network'), ...
                sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9')]);

            sciIssues = c2837x_block_validate_project(sciProject, 'instant');
            w5300Issues = c2837x_block_validate_project(w5300Project, 'instant');
            mixedIssues = c2837x_block_validate_project(mixedProject, 'instant');

            testCase.verifyFalse(has_network_issue(sciIssues));
            testCase.verifyTrue(has_network_issue(w5300Issues));
            testCase.verifyTrue(has_network_issue(mixedIssues));
        end

        function testCapabilityFailureIsIsolatedByProjectType(testCase)
            install_unavailable_loader(testCase);
            w5300Project = project_with_instances(w5300_instance('network'));
            sciProject = project_with_instances(sci_instance( ...
                'sci_a', 'SCI-A', 'SCI-A_TX8_RX9'));
            invalidW5300 = w5300_instance('network');
            invalidW5300.iodevice.settings.socket_number = uint16(8);
            invalidW5300.iodevice.settings.tcp_port = uint16(0);
            mixedProject = project_with_instances([invalidW5300, ...
                sci_instance('sci_a', 'SCI-A', 'SCI-A_TX8_RX9')]);

            w5300Issues = c2837x_block_validate_project(w5300Project, 'instant');
            sciIssues = c2837x_block_validate_project(sciProject, 'instant');
            mixedIssues = c2837x_block_validate_project(mixedProject, 'instant');

            testCase.verifyFalse(has_code(w5300Issues, ...
                'SCI_CAPABILITY_UNAVAILABLE'));
            testCase.verifyTrue(has_code(sciIssues, ...
                'SCI_CAPABILITY_UNAVAILABLE'));
            testCase.verifyTrue(has_code(mixedIssues, ...
                'SCI_CAPABILITY_UNAVAILABLE'));
            testCase.verifyTrue(has_code(mixedIssues, 'SOCKET_INVALID'));
            testCase.verifyTrue(has_code(mixedIssues, 'TCP_PORT_INVALID'));
        end

        function testPlatformReservedSetMatchesHalAndIsConditional(testCase)
            w5300Project = project_with_instances(w5300_instance('network'));
            sciProject = project_with_instances(sci_instance( ...
                'sci_a', 'SCI-A', 'SCI-A_TX8_RX9'));
            expected = [28:41 44:52 63:83 85:94 99];

            active = c2837x_block_get_platform_reserved_resources(w5300Project);
            inactive = c2837x_block_get_platform_reserved_resources(sciProject);

            testCase.verifyEqual(cellfun(@str2double, {active.key}), expected);
            testCase.verifyEmpty(inactive);
        end

        function testGeneratorHooksFailAtStageBoundary(testCase)
            definition = c2837x_block_get_iodevice_definition('sci');
            project = project_with_instances(sci_instance( ...
                'sci_a', 'SCI-A', 'SCI-A_TX8_RX9'));

            testCase.verifyError(@() definition.render_project_support(project), ...
                'C2837xBlock:IoDevice:SciGenerationUnavailable');
            testCase.verifyError(@() definition.render_instance_config_support( ...
                project, 1), 'C2837xBlock:IoDevice:SciGenerationUnavailable');
            testCase.verifyError(@() definition.render_instance_io_support( ...
                project, 1), 'C2837xBlock:IoDevice:SciGenerationUnavailable');
        end
    end
end

function instance = sci_instance(name, module, pinGroup)
instance = base_instance(name);
instance.iodevice = c2837x_block_create_iodevice('sci');
instance.iodevice.settings.module = module;
instance.iodevice.settings.baud = uint32(115200);
instance.iodevice.settings.pin_group = pinGroup;
instance.iodevice.settings.rx_pin_type = 'Standard';
instance.iodevice.settings.rx_qualification = 'Sync';
instance.iodevice.settings.tx_pin_type = 'Pull-up';
instance.iodevice.settings.ctrl_gpio = 'None';
instance.iodevice.settings.ctrl_pin_type = 'Standard';
instance.iodevice.settings.ctrl_tx_active_level = 'Low';
end

function instance = w5300_instance(name)
instance = base_instance(name);
instance.iodevice.settings.socket_number = uint16(0);
instance.iodevice.settings.tcp_port = uint16(5000);
end

function instance = base_instance(name)
instance = c2837x_block_create_default_instance();
instance.display_name = name;
instance.internal_name = name;
instance.inputs = struct('name', 'command', 'type', 'single', 'dim', 1);
instance.outputs = struct('name', 'status', 'type', 'single', 'dim', 1);
end

function project = project_with_instances(instances)
project = c2837x_block_create_default_project();
project.instances = instances;
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(tempdir, 'c2837x_block_sci_validation_dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(tempdir, 'c2837x_block_sci_validation_sfun'));
end

function project = invalid_network_project(instances)
project = project_with_instances(instances);
project.common.network.mac = uint8(zeros(1, 6));
project.common.network.ip = '0.0.0.0';
project.common.network.gateway = 'invalid';
project.common.network.subnet = '255.0.255.0';
end

function value = has_code(issues, code)
value = any(strcmp({issues.code}, code));
end

function value = has_network_issue(issues)
codes = {'MAC_INVALID', 'MAC_ALL_ZERO', 'MAC_BROADCAST', 'MAC_MULTICAST', ...
    'IP_INVALID', 'IP_ALL_ZERO', 'IP_BROADCAST', 'GATEWAY_INVALID', ...
    'SUBNET_INVALID', 'SUBNET_NONCONTIGUOUS'};
value = any(ismember({issues.code}, codes));
end

function install_unavailable_loader(testCase)
path = fullfile(testCase.WorkFolder, ...
    'c2837x_block_load_device_capability.m');
text = sprintf([ ...
    'function result = c2837x_block_load_device_capability(varargin)\n' ...
    'result = struct(''available'', false, ''capability'', struct(), ...\n' ...
    '    ''identifier'', ''Test:Capability:Unavailable'', ...\n' ...
    '    ''message'', ''simulated unavailable capability'', ...\n' ...
    '    ''source_path'', '''');\n' ...
    'end\n']);
write_text(path, text);
addpath(testCase.WorkFolder, '-begin');
testCase.addTeardown(@() restore_loader(testCase.WorkFolder));
clear c2837x_block_load_device_capability
rehash
end

function restore_loader(folder)
rmpath(folder);
clear c2837x_block_load_device_capability
rehash
end

function write_text(path, text)
fileID = fopen(path, 'w');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fprintf(fileID, '%s', text);
end
