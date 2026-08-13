classdef test_configurator_smoke < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testHiddenConstruction(testCase)
            originalFolder = pwd;
            originalPath = path;
            try
                app = C2837xBlockConfigurator(struct( ...
                    'visible', 'off', 'preview_provider', []));
            catch cause
                testCase.assumeFail(sprintf('uifigure unavailable: %s', cause.message));
            end
            cleanup = onCleanup(@() delete(app));
            testCase.verifyTrue(isvalid(app));
            testCase.verifyClass(app.ProjectSession, 'c2837x_block_project_session');
            testCase.verifyEqual(app.ProjectSession.Project.common.network.mac, ...
                uint8([0 8 220 1 2 3]));
            testCase.verifyEqual(app.ProjectSession.Project.common.network.ip, ...
                '192.168.1.100');
            testCase.verifyEqual(app.ProjectSession.Project.common.network.gateway, ...
                '192.168.1.1');
            testCase.verifyEqual(app.ProjectSession.Project.common.network.subnet, ...
                '255.255.255.0');
            testCase.verifyEqual(pwd, originalFolder);
            testCase.verifyEqual(path, originalPath);
            clear cleanup
        end

        function testDefaultAppUsesProjectProvider(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            try
                app = C2837xBlockConfigurator();
            catch cause
                testCase.assumeFail(sprintf('uifigure unavailable: %s', cause.message));
            end
            cleanup = onCleanup(@() delete(app));
            app.UIFigure.Visible = 'off';
            project = smoke_project(fixture.Folder);
            app.Coordinator.updateProject(project);

            [view, issues] = app.Coordinator.createPreview();

            testCase.verifyEqual(view.status, 'valid');
            testCase.verifyFalse(any(strcmp({issues.severity}, 'Error')));
            testCase.verifyEqual(numel(view.comparisons), 35);
            testCase.verifyTrue(any(startsWith({view.comparisons.target_path}, ...
                project.output.dsp_root)));
            testCase.verifyTrue(any(startsWith({view.comparisons.target_path}, ...
                project.output.sfun_root)));
            clear cleanup
        end

        function testInvalidOptionsRejected(testCase)
            testCase.verifyError(@() C2837xBlockConfigurator(struct( ...
                'visible', 'off', 'preview_provider', [], 'extra', true)), ...
                'C2837xBlock:App:InvalidOptions');
        end

        function testInvalidVisibilityRejected(testCase)
            testCase.verifyError(@() C2837xBlockConfigurator(struct( ...
                'visible', 'hidden', 'preview_provider', [])), ...
                'C2837xBlock:App:InvalidOptions');
        end

        function testInvalidProviderRejected(testCase)
            testCase.verifyError(@() C2837xBlockConfigurator(struct( ...
                'visible', 'off', 'preview_provider', 1)), ...
                'C2837xBlock:App:InvalidOptions');
        end

        function testSaveAndLoadUseCoordinatorRoutes(testCase)
            source = configurator_source();
            testCase.verifyEmpty(regexp(source, ...
                'ProjectSession\.(saveProject|loadProject|canDiscardChanges)', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'Coordinator\.saveProject\(', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'Coordinator\.loadProject\(', 'once'));
            testCase.verifyEqual(numel(regexp(source, ...
                'app\.saveCurrentProject\(\)', 'match')), 3);
        end

        function testDraftRoutesAndSuggestionsAreWired(testCase)
            source = configurator_source();
            testCase.verifyNotEmpty(regexp(source, ...
                'Coordinator\.updateProjectDraft\(', 'once'));
            testCase.verifyEmpty(regexp(source, ...
                'uint16\(app\.DetailFields|uint32\(app\.DetailFields', 'once'));
            testCase.verifyGreaterThanOrEqual(numel(regexp(source, ...
                'c2837x_block_suggest_unique_name\(', 'match')), 3);
            testCase.verifyEmpty(regexp(source, '''new_value''', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'app\.clearPreviewDisplay\(\)', 'once'));
        end

        function testInstanceContextTracksAppOperations(testCase)
            app = create_hidden_app(testCase);
            cleanup = onCleanup(@() delete(app));
            figure = app.UIFigure;
            instanceTable = find_table(figure, {'Display Name', ...
                'Internal Name', 'IoDevice', 'Resource', 'Link', 'Sample Time'});

            push_button(figure, 'Instances', 'Add');
            verify_context(testCase, figure, 'Instance 1', 'instance_1', 1);
            testCase.verifyEqual(instanceTable.Selection, selected_row(1, 6));
            testCase.verifyEqual(find_table(figure, ...
                {'Name', 'Type', 'Dim'}, 'Inputs').Data(1, :), ...
                {'input_value', 'single', 1});

            push_button(figure, 'Instances', 'Copy');
            verify_context(testCase, figure, 'Instance 2', 'instance_2', 2);
            testCase.verifyEqual(instanceTable.Selection, selected_row(2, 6));

            instanceTable.CellSelectionCallback(instanceTable, ...
                struct('Indices', [1 1]));
            verify_context(testCase, figure, 'Instance 1', 'instance_1', 1);

            edit_detail(figure, 'Display Name', 'Axis A');
            edit_detail(figure, 'Internal Name', 'axis_a');
            verify_context(testCase, figure, 'Axis A', 'axis_a', 1);

            issueTable = find_table(figure, {'Severity', 'Code', 'Instance', ...
                'Field', 'File', 'Message'});
            issueTable.Data = {'Error', 'INPUT', 2, ...
                'project.instances(2).inputs(1).name', '', 'message'};
            issueTable.CellSelectionCallback(issueTable, struct('Indices', [1 1]));
            verify_context(testCase, figure, 'Instance 2', 'instance_2', 2);
            testCase.verifyEqual(instanceTable.Selection, selected_row(2, 6));

            issueTable.Data = {'Error', 'PROJECT', 0, 'project', '', 'message'};
            issueTable.CellSelectionCallback(issueTable, struct('Indices', [1 1]));
            verify_context(testCase, figure, 'Instance 2', 'instance_2', 2);

            app.Coordinator.deleteInstance(2);
            refresh_via_common_field(figure);
            verify_context(testCase, figure, 'Axis A', 'axis_a', 1);
            testCase.verifyEqual(instanceTable.Selection, selected_row(1, 6));
            clear cleanup
        end

        function testLoadedProjectRefreshesContext(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            app = create_hidden_app(testCase);
            cleanup = onCleanup(@() delete(app));
            project = load_project(2);
            filePath = fullfile(fixture.Folder, 'two.mat');
            save(filePath, 'project');
            [loaded, issues] = app.Coordinator.loadProject(filePath);
            testCase.verifyTrue(loaded);
            testCase.verifyEmpty(issues);
            refresh_via_common_field(app.UIFigure);
            verify_context(testCase, app.UIFigure, 'Axis 1', 'axis_1', 1);

            project = c2837x_block_create_default_project();
            filePath = fullfile(fixture.Folder, 'zero.mat');
            save(filePath, 'project');
            [loaded, issues] = app.Coordinator.loadProject(filePath);
            testCase.verifyTrue(loaded);
            testCase.verifyEmpty(issues);
            refresh_via_common_field(app.UIFigure);
            verify_none_context(testCase, app.UIFigure);
            table = find_table(app.UIFigure, {'Display Name', 'Internal Name', ...
                'IoDevice', 'Resource', 'Link', 'Sample Time'});
            testCase.verifyEmpty(table.Selection);
            testCase.verifyEmpty(find_table(app.UIFigure, ...
                {'Name', 'Type', 'Dim'}, 'Inputs').Data);
            report = report_text(app.UIFigure);
            testCase.verifyFalse(contains(report, 'Selected Instance:'));
            clear cleanup
        end


        function testSciDynamicConfiguration(testCase)
            app = create_hidden_app(testCase);
            cleanup = onCleanup(@() delete(app));
            figure = app.UIFigure;
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'ProjectSciClockField').Visible, matlab.lang.OnOffSwitchState.off);
            push_button(figure, 'Instances', 'Add');
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'W5300SocketField').Parent.Visible, matlab.lang.OnOffSwitchState.on);
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'SciModuleField').Parent.Visible, matlab.lang.OnOffSwitchState.off);

            invoke_dropdown(figure, 'IoDeviceTypeField', 'sci');
            settings = app.ProjectSession.Project.instances(1).iodevice.settings;
            testCase.verifyEqual(settings, c2837x_block_create_iodevice('sci').settings);
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'W5300SocketField').Parent.Visible, matlab.lang.OnOffSwitchState.off);
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'SciModuleField').Parent.Visible, matlab.lang.OnOffSwitchState.on);
            instanceTable = find_table(figure, {'Display Name', ...
                'Internal Name', 'IoDevice', 'Resource', 'Link', 'Sample Time'});
            testCase.verifyEqual(instanceTable.Data(1, 3:5), ...
                {'SCI', 'Not Selected', '57600 baud'});
            testCase.verifyTrue(contains(findall(figure, 'Tag', ...
                'InputsOutputsInstanceContext').Text, ...
                'Not Selected / 57600 baud'));
            testCase.verifyTrue(contains(report_text(figure), ...
                'Transport: Not Selected / 57600 baud'));
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'ProjectSciClockField').Editable, ...
                matlab.lang.OnOffSwitchState.off);
            testCase.verifyTrue(contains(findall(figure, 'Tag', ...
                'ProjectSciClockField').Value, '14.285714 MHz (SYSCLK / 14)'));

            invoke_dropdown(figure, 'SciModuleField', 'SCI-B');
            capability = c2837x_block_load_device_capability().capability;
            module = capability.sci_modules(2);
            expectedRx = [{'Not Selected'}, ...
                cellstr(compose('GPIO%u', [module.rx_endpoints.gpio]))];
            expectedTx = [{'Not Selected'}, ...
                cellstr(compose('GPIO%u', [module.tx_endpoints.gpio]))];
            rxGpio = findall(figure, 'Tag', 'SciRxGpioField');
            txGpio = findall(figure, 'Tag', 'SciTxGpioField');
            testCase.verifyEqual(rxGpio.Items, expectedRx);
            testCase.verifyEqual(txGpio.Items, expectedTx);
            invoke_dropdown(figure, 'SciRxGpioField', 'GPIO19');
            invoke_dropdown(figure, 'SciTxGpioField', 'GPIO14');
            settings = app.ProjectSession.Project.instances(1).iodevice.settings;
            testCase.verifyEqual(settings.rx_gpio, 'GPIO19');
            testCase.verifyEqual(settings.tx_gpio, 'GPIO14');
            invoke_dropdown(figure, 'SciModuleField', 'SCI-A');
            testCase.verifyEmpty(app.ProjectSession.Project.instances(1). ...
                iodevice.settings.rx_gpio);
            testCase.verifyEmpty(app.ProjectSession.Project.instances(1). ...
                iodevice.settings.tx_gpio);
            testCase.verifyEmpty(rxGpio.Value);
            testCase.verifyEmpty(txGpio.Value);

            ctrl = findall(figure, 'Tag', 'SciCtrlGpioField');
            invoke_dropdown(figure, 'SciCtrlGpioField', ctrl.ItemsData{2});
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'SciCtrlPinTypeField').Enable, matlab.lang.OnOffSwitchState.on);
            invoke_dropdown(figure, 'SciCtrlGpioField', 'None');
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'SciCtrlPinTypeField').Enable, matlab.lang.OnOffSwitchState.off);

            clock = c2837x_block_get_sci_clock_config();
            expected = c2837x_block_calculate_sci_baud(clock.lspclk_hz, 57600);
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'SciActualBaudField').Value, expected.actual_baud, AbsTol=1e-9);
            testCase.verifyEqual(findall(figure, 'Tag', ...
                'SciBaudErrorField').Value, expected.signed_error_baud, AbsTol=1e-9);
            clear cleanup
        end

        function testMixedAddAndSciCopy(testCase)
            app = create_hidden_app(testCase);
            cleanup = onCleanup(@() delete(app));
            figure = app.UIFigure;
            push_button(figure, 'Instances', 'Add');
            invoke_dropdown(figure, 'IoDeviceTypeField', 'sci');
            source = app.ProjectSession.Project;
            source.instances.algorithm.mode = 'external_reference';
            source.instances.algorithm.source_path = ...
                c2837x_block_normalize_absolute_path(fullfile(tempdir, 'source.c'));
            source.instances.iodevice.settings.module = 'SCI-A';
            source.instances.iodevice.settings.rx_gpio = 'GPIO9';
            source.instances.iodevice.settings.tx_gpio = 'GPIO8';
            app.Coordinator.updateProject(source);
            refresh_via_common_field(figure);

            push_button(figure, 'Instances', 'Copy');
            copied = app.ProjectSession.Project.instances(2);
            testCase.verifyEmpty(copied.iodevice.settings.module);
            testCase.verifyEmpty(copied.iodevice.settings.rx_gpio);
            testCase.verifyEmpty(copied.iodevice.settings.tx_gpio);
            testCase.verifyEqual(copied.iodevice.settings.ctrl_gpio, 'None');
            testCase.verifyEqual(copied.algorithm, source.instances.algorithm);

            push_button(figure, 'Instances', 'Add');
            added = app.ProjectSession.Project.instances(3);
            testCase.verifyEqual(added.iodevice.type, 'w5300_tcp');
            testCase.verifyEqual(added.iodevice.settings.socket_number, uint16(0));
            clear cleanup
        end

        function testCapabilityUnavailableIsolation(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            write_unavailable_capability_loader(fixture.Folder);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fixture.Folder, 'IncludeSubfolders', false));
            clear_capability_loader();
            testCase.addTeardown(@clear_capability_loader);
            app = create_hidden_app(testCase);
            cleanup = onCleanup(@() delete(app));

            push_button(app.UIFigure, 'Instances', 'Add');
            invoke_dropdown(app.UIFigure, 'IoDeviceTypeField', 'sci');

            source = app.ProjectSession.Project;
            source.instances.iodevice.settings.module = 'SCI-B';
            source.instances.iodevice.settings.rx_gpio = 'GPIO19';
            source.instances.iodevice.settings.tx_gpio = 'GPIO14';
            source.instances.iodevice.settings.ctrl_gpio = 'GPIO42';
            app.Coordinator.updateProject(source);
            refresh_via_common_field(app.UIFigure);

            testCase.verifyEqual(findall(app.UIFigure, 'Tag', ...
                'SciRxGpioField').Enable, matlab.lang.OnOffSwitchState.off);
            testCase.verifyEqual(findall(app.UIFigure, 'Tag', ...
                'SciTxGpioField').Enable, matlab.lang.OnOffSwitchState.off);
            testCase.verifyEqual(findall(app.UIFigure, 'Tag', ...
                'SciCtrlGpioField').Enable, matlab.lang.OnOffSwitchState.off);
            testCase.verifyEqual(app.ProjectSession.Project.instances(1). ...
                iodevice.settings.rx_gpio, 'GPIO19');
            testCase.verifyEqual(app.ProjectSession.Project.instances(1). ...
                iodevice.settings.tx_gpio, 'GPIO14');
            testCase.verifyEqual(app.ProjectSession.Project.instances(1). ...
                iodevice.settings.ctrl_gpio, 'GPIO42');
            invoke_dropdown(app.UIFigure, 'IoDeviceTypeField', 'w5300_tcp');
            testCase.verifyEqual(app.ProjectSession.Project.instances(1). ...
                iodevice, c2837x_block_create_iodevice('w5300_tcp'));
            clear cleanup
        end
    end
end

function app = create_hidden_app(testCase)
try
    app = C2837xBlockConfigurator(struct( ...
        'visible', 'off', 'preview_provider', []));
catch cause
    testCase.assumeFail(sprintf('uifigure unavailable: %s', cause.message));
end
end

function push_button(figure, tabTitle, text)
tab = find_tab(figure, tabTitle);
buttons = findall(tab, 'Type', 'uibutton');
button = buttons(strcmp({buttons.Text}, text));
button.ButtonPushedFcn(button, []);
drawnow;
end

function invoke_dropdown(figure, tag, value)
field = findall(figure, 'Tag', tag);
field.Value = value;
field.ValueChangedFcn(field, []);
drawnow;
end

function write_unavailable_capability_loader(folder)
lines = [ ...
    "function result = c2837x_block_load_device_capability(varargin)"; ...
    "result = struct('available', false, 'capability', struct(), ..."; ...
    "    'identifier', 'C2837xBlock:Capability:Unavailable', ..."; ...
    "    'message', 'unavailable test fixture', 'source_path', '');"; ...
    "end"];
writelines(lines, fullfile(folder, 'c2837x_block_load_device_capability.m'));
end

function clear_capability_loader()
clear('c2837x_block_load_device_capability');
end

function edit_detail(figure, labelText, value)
label = findall(figure, 'Type', 'uilabel', 'Text', labelText);
grid = label.Parent;
fields = grid.Children(arrayfun(@(item) ...
    isa(item, 'matlab.ui.control.EditField') && ...
    isequal(item.Layout.Row, label.Layout.Row) && ...
    isequal(item.Layout.Column, label.Layout.Column + 1), grid.Children));
field = fields(1);
field.Value = value;
field.ValueChangedFcn(field, []);
drawnow;
end

function refresh_via_common_field(figure)
dropdowns = findall(find_tab(figure, 'Project'), 'Type', 'uidropdown');
field = dropdowns(arrayfun(@(value) ...
    isequal(value.Items, {'eabi', 'coffabi'}), dropdowns));
field.ValueChangedFcn(field, []);
drawnow;
end

function verify_context(testCase, figure, displayName, internalName, row)
text = sprintf('Current Instance: %s [%s] | Socket %u / TCP %u', ...
    displayName, internalName, row - 1, 4999 + row);
testCase.verifyEqual(findall(figure, 'Tag', ...
    'InputsOutputsInstanceContext').Text, text);
testCase.verifyEqual(findall(figure, 'Tag', ...
    'IssuesInstanceContext').Text, [text ' | Scope: Entire Project']);
testCase.verifyEqual(findall(figure, 'Tag', ...
    'InterfaceInstanceContext').Text, text);
testCase.verifyEqual(findall(figure, 'Tag', ...
    'GenerationPreviewInstanceContext').Text, text);
report = report_text(figure);
testCase.verifyTrue(contains(report, ...
    sprintf('Selected Instance: %s [%s]', displayName, internalName)));
testCase.verifyTrue(contains(report, ...
    sprintf('Transport: Socket %u / TCP %u', row - 1, 4999 + row)));
table = find_table(figure, {'Display Name', 'Internal Name', 'IoDevice', ...
    'Resource', 'Link', 'Sample Time'});
testCase.verifyEqual(unique(table.Selection(:, 1)), row);
end

function verify_none_context(testCase, figure)
testCase.verifyEqual(findall(figure, 'Tag', ...
    'InputsOutputsInstanceContext').Text, 'Current Instance: None');
testCase.verifyEqual(findall(figure, 'Tag', ...
    'IssuesInstanceContext').Text, ...
    'Current Instance: None | Scope: Entire Project');
testCase.verifyEqual(findall(figure, 'Tag', ...
    'InterfaceInstanceContext').Text, 'Current Instance: None');
testCase.verifyEqual(findall(figure, 'Tag', ...
    'GenerationPreviewInstanceContext').Text, 'Current Instance: None');
end

function value = selected_row(row, columns)
value = [repmat(row, columns, 1), (1:columns)'];
end

function text = report_text(figure)
area = findall(find_tab(figure, 'Interface Hash / Memory'), ...
    'Type', 'uitextarea');
text = strjoin(string(area.Value), newline);
end

function tab = find_tab(parent, title)
tabs = findall(parent, 'Type', 'uitab');
tab = tabs(strcmp({tabs.Title}, title));
end

function table = find_table(figure, columns, tabTitle)
if nargin < 3
    parent = figure;
else
    parent = find_tab(figure, tabTitle);
end
tables = findall(parent, 'Type', 'uitable');
matches = arrayfun(@(value) isequal(string(value.ColumnName(:)), ...
    string(columns(:))), tables);
table = tables(matches);
end

function project = load_project(count)
project = c2837x_block_create_default_project();
instances = repmat(c2837x_block_create_default_instance(), 1, count);
for index = 1:count
    instances(index).display_name = sprintf('Axis %u', index);
    instances(index).internal_name = sprintf('axis_%u', index);
    instances(index).iodevice.settings.socket_number = uint16(index - 1);
    instances(index).iodevice.settings.tcp_port = uint16(4999 + index);
    instances(index).inputs = struct('name', sprintf('input_%u', index), ...
        'type', 'single', 'dim', 1);
    instances(index).outputs = struct('name', sprintf('output_%u', index), ...
        'type', 'single', 'dim', 1);
end
project.instances = instances;
end

function source = configurator_source()
path = which('C2837xBlockConfigurator');
source = fileread(path);
end

function project = smoke_project(root)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.1.10';
project.common.network.gateway = '0.0.0.0';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, 'sfun'));
instance = c2837x_block_create_default_instance();
instance.display_name = 'Instance 1';
instance.internal_name = 'instance_1';
instance.inputs = struct('name', 'command', 'type', 'single', 'dim', 1);
instance.outputs = struct('name', 'status', 'type', 'single', 'dim', 1);
project.instances = instance;
end
