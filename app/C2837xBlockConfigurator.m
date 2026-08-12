classdef C2837xBlockConfigurator < handle
%C2837XBLOCKCONFIGURATOR Multi-instance DSP-SimBridge configurator.

    properties (SetAccess = private)
        UIFigure
        ProjectSession
        Coordinator
    end

    properties (Access = private)
        GenerateButton
        StatusLabel
        CommonFields
        ProjectSciClockLabel
        ProjectSciClockField
        InstanceTable
        DetailFields
        DetailTabGroup
        GeneralTab
        IoDeviceTab
        AlgorithmTab
        W5300Grid
        SciGrid
        SourcePathGrid
        InputTable
        OutputTable
        IssueTable
        ReportArea
        CandidateTable
        CandidateArea
        ResultArea
        MainTabGroup
        ProjectTab
        InstancesTab
        InputsOutputsTab
        InputsOutputsTabGroup
        InputsOutputsContextLabel
        InputsTab
        OutputsTab
        IssuesInterfaceTab
        IssuesInterfaceTabGroup
        IssuesContextLabel
        InterfaceContextLabel
        InterfaceTab
        GenerationPreviewTab
        GenerationPreviewInstanceContext
        SelectedInstance = 0
        Updating = false
    end

    methods
        function app = C2837xBlockConfigurator(options)
            if nargin < 1
                options = struct('visible', 'on', 'preview_provider', ...
                    @c2837x_block_build_project_candidates);
            else
                options = validate_options(options);
            end
            app.ProjectSession = c2837x_block_project_session();
            app.Coordinator = c2837x_block_app_coordinator( ...
                app.ProjectSession, options.preview_provider);
            app.createComponents(options.visible);
            app.refreshAll();
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)
        function createComponents(app, visible)
            app.UIFigure = uifigure('Name', 'C2837xBlock Configurator', ...
                'Visible', visible, 'Position', [50 50 1100 720], ...
                'CloseRequestFcn', @(src, ~) app.closeRequested(src));
            root = uigridlayout(app.UIFigure, [3 1]);
            root.RowHeight = {44, '1x', 26};
            root.ColumnWidth = {'1x'};
            root.Padding = [8 8 8 8];
            root.RowSpacing = 8;
            root.ColumnSpacing = 0;

            toolbar = uigridlayout(root, [1 5]);
            toolbar.ColumnWidth = {90, 90, 90, 90, '1x'};
            toolbar.RowHeight = {'1x'};
            toolbar.Padding = [0 0 0 0];
            toolbar.RowSpacing = 0;
            toolbar.ColumnSpacing = 8;
            app.createButton(toolbar, 'Save', @(~, ~) app.saveRequested());
            app.createButton(toolbar, 'Load', @(~, ~) app.loadRequested());
            app.createButton(toolbar, 'Preview', @(~, ~) app.previewRequested());
            app.GenerateButton = app.createButton(toolbar, 'Generate', ...
                @(~, ~) app.generateRequested());
            app.GenerateButton.Enable = 'off';

            app.MainTabGroup = uitabgroup(root);
            app.ProjectTab = uitab(app.MainTabGroup, 'Title', 'Project');
            app.InstancesTab = uitab(app.MainTabGroup, 'Title', 'Instances');
            app.InputsOutputsTab = uitab(app.MainTabGroup, ...
                'Title', 'Inputs / Outputs');
            app.IssuesInterfaceTab = uitab(app.MainTabGroup, ...
                'Title', 'Issues / Interface');
            app.GenerationPreviewTab = uitab(app.MainTabGroup, ...
                'Title', 'Generation Preview');

            app.createProjectTab(app.ProjectTab);
            app.createInstancesTab(app.InstancesTab);
            app.createInputsOutputsTab(app.InputsOutputsTab);
            app.createIssuesTab(app.IssuesInterfaceTab);
            app.createCandidatesTab(app.GenerationPreviewTab);

            app.StatusLabel = uilabel(root, 'Text', 'Ready');
        end

        function createProjectTab(app, tab)
            projectGrid = uigridlayout(tab, [2 1]);
            projectGrid.RowHeight = {310, '1x'};
            projectGrid.ColumnWidth = {'1x'};
            projectGrid.Padding = [8 8 8 8];
            projectGrid.RowSpacing = 8;
            projectGrid.ColumnSpacing = 0;
            commonPanel = uipanel(projectGrid, ...
                'Title', 'Project Common Configuration');
            common = uigridlayout(commonPanel, [6 4]);
            common.ColumnWidth = {160, '1x', 160, '1x'};
            common.RowHeight = {36, 36, 36, 36, 36, 36};
            common.Padding = [10 10 10 10];
            common.RowSpacing = 8;
            common.ColumnSpacing = 10;
            labels = {'DSP Model', 'Protocol Version', 'ABI', 'MAC', ...
                'IP', 'Gateway', 'Subnet', 'DSP Output Root', ...
                'S-Function Output Root'};
            keys = {'dsp_model', 'protocol_version', 'abi', 'mac', 'ip', ...
                'gateway', 'subnet', 'dsp_root', 'sfun_root'};
            app.CommonFields = struct();
            for index = 1:numel(keys)
                uilabel(common, 'Text', labels{index});
                if strcmp(keys{index}, 'abi')
                    field = uidropdown(common, 'Items', {'eabi', 'coffabi'});
                elseif any(strcmp(keys{index}, {'dsp_root', 'sfun_root'}))
                    pathGrid = uigridlayout(common, [1 2]);
                    pathGrid.ColumnWidth = {'1x', 90};
                    pathGrid.RowHeight = {'1x'};
                    pathGrid.Padding = [0 0 0 0];
                    pathGrid.RowSpacing = 0;
                    pathGrid.ColumnSpacing = 8;
                    field = uieditfield(pathGrid, 'text');
                    app.createButton(pathGrid, 'Browse', ...
                        @(~, ~) app.browseOutput(keys{index}));
                else
                    field = uieditfield(common, 'text');
                end
                field.ValueChangedFcn = @(~, ~) app.commonEdited(keys{index});
                app.CommonFields.(keys{index}) = field;
            end
            app.CommonFields.dsp_model.Editable = 'off';
            app.CommonFields.protocol_version.Editable = 'off';
            app.ProjectSciClockLabel = uilabel(common, 'Text', 'SCI LSPCLK', ...
                'Tag', 'ProjectSciClockLabel', 'Visible', 'off');
            app.ProjectSciClockField = uieditfield(common, 'text', ...
                'Editable', 'off', 'Tag', 'ProjectSciClockField', ...
                'Visible', 'off');
        end

        function createInstancesTab(app, tab)
            grid = uigridlayout(tab, [2 1]);
            grid.RowHeight = {'1x', 330};
            grid.ColumnWidth = {'1x'};
            grid.Padding = [8 8 8 8];
            grid.RowSpacing = 8;
            grid.ColumnSpacing = 0;
            listPanel = uipanel(grid, 'Title', 'Instances');
            listGrid = uigridlayout(listPanel, [2 1]);
            listGrid.RowHeight = {'1x', 38};
            listGrid.ColumnWidth = {'1x'};
            listGrid.Padding = [8 8 8 8];
            listGrid.RowSpacing = 8;
            listGrid.ColumnSpacing = 0;
            app.InstanceTable = uitable(listGrid, 'ColumnName', ...
                {'Display Name', 'Internal Name', 'IoDevice', 'Resource', ...
                'Link', 'Sample Time'}, 'ColumnEditable', false(1, 6), ...
                'CellSelectionCallback', @(~, event) app.instanceSelected(event));
            buttons = uigridlayout(listGrid, [1 4]);
            buttons.ColumnWidth = {90, 90, 90, '1x'};
            buttons.RowHeight = {'1x'};
            buttons.Padding = [0 0 0 0];
            buttons.RowSpacing = 0;
            buttons.ColumnSpacing = 8;
            app.createButton(buttons, 'Add', @(~, ~) app.addInstance());
            app.createButton(buttons, 'Copy', @(~, ~) app.copyInstance());
            app.createButton(buttons, 'Delete', @(~, ~) app.deleteInstance());

            detailPanel = uipanel(grid, 'Title', 'Instance Detail');
            app.DetailFields = struct();
            host = uigridlayout(detailPanel, [1 1]);
            host.Padding = [8 8 8 8];
            app.DetailTabGroup = uitabgroup(host, 'Tag', 'InstanceDetailTabGroup');
            app.GeneralTab = uitab(app.DetailTabGroup, 'Title', 'General', ...
                'Tag', 'InstanceGeneralTab');
            app.IoDeviceTab = uitab(app.DetailTabGroup, 'Title', 'IoDevice', ...
                'Tag', 'InstanceIoDeviceTab');
            app.AlgorithmTab = uitab(app.DetailTabGroup, 'Title', 'Algorithm', ...
                'Tag', 'InstanceAlgorithmTab');
            app.createGeneralDetail();
            app.createIoDeviceDetail();
            app.createAlgorithmDetail();
        end

        function createGeneralDetail(app)
            grid = detail_grid(app.GeneralTab, 3);
            app.DetailFields.display_name = labeled_field(grid, 1, 1, ...
                'Display Name', uieditfield(grid, 'text'), 'DisplayNameField');
            app.DetailFields.internal_name = labeled_field(grid, 1, 4, ...
                'Internal Name', uieditfield(grid, 'text'), 'InternalNameField');
            app.DetailFields.iodevice = labeled_field(grid, 2, 1, ...
                'IoDevice', uidropdown(grid, 'Items', {'W5300 TCP', 'SCI'}, ...
                'ItemsData', {'w5300_tcp', 'sci'}), 'IoDeviceTypeField');
            app.DetailFields.sample_time = labeled_field(grid, 2, 4, ...
                'Sample Time', uieditfield(grid, 'numeric'), 'SampleTimeField');
            tooltip = ['Protocol safety limit only. RX/TX buffers ' ...
                'use actual legal message lengths.'];
            label = uilabel(grid, 'Text', 'Max Payload Limit (wire octets)', ...
                'Tag', 'MaxPayloadLimitLabel', 'Tooltip', tooltip);
            label.Layout.Row = 3;
            label.Layout.Column = 1;
            field = uieditfield(grid, 'numeric', 'Tag', 'MaxPayloadLimitField', ...
                'Tooltip', tooltip);
            field.Layout.Row = 3;
            field.Layout.Column = 2;
            app.DetailFields.max_payload = field;
            app.DetailFields.iodevice.ValueChangedFcn = @(~, ~) app.ioDeviceChanged();
            keys = {'display_name', 'internal_name', 'sample_time', 'max_payload'};
            for index = 1:numel(keys)
                key = keys{index};
                app.DetailFields.(key).ValueChangedFcn = @(~, ~) app.detailEdited(key);
            end
        end

        function createIoDeviceDetail(app)
            host = uigridlayout(app.IoDeviceTab, [1 1]);
            host.Padding = [0 0 0 0];
            app.W5300Grid = detail_grid(host, 1);
            app.DetailFields.socket = labeled_field(app.W5300Grid, 1, 1, ...
                'Socket', uidropdown(app.W5300Grid, 'Items', compose('%u', 0:7)), ...
                'W5300SocketField');
            app.DetailFields.port = labeled_field(app.W5300Grid, 1, 4, ...
                'TCP Port', uieditfield(app.W5300Grid, 'numeric'), ...
                'W5300TcpPortField');

            app.SciGrid = detail_grid(host, 6);
            modules = {'', 'SCI-A', 'SCI-B', 'SCI-C', 'SCI-D'};
            app.DetailFields.sci_module = labeled_field(app.SciGrid, 1, 1, ...
                'SCI Module', uidropdown(app.SciGrid, ...
                'Items', {'Not Selected', 'SCI-A', 'SCI-B', 'SCI-C', 'SCI-D'}, ...
                'ItemsData', modules), 'SciModuleField');
            app.DetailFields.sci_baud = labeled_field(app.SciGrid, 1, 4, ...
                'Requested Baud', uidropdown(app.SciGrid, ...
                'Items', compose('%u', [9600 19200 38400 57600 115200]), ...
                'ItemsData', [9600 19200 38400 57600 115200]), 'SciBaudField');
            app.DetailFields.sci_actual_baud = labeled_field(app.SciGrid, 2, 1, ...
                'Actual Baud', uieditfield(app.SciGrid, 'numeric', ...
                'Editable', 'off', 'ValueDisplayFormat', '%.3f'), ...
                'SciActualBaudField');
            app.DetailFields.sci_baud_error = labeled_field(app.SciGrid, 2, 4, ...
                'Baud Error (Actual - Requested)', ...
                uieditfield(app.SciGrid, 'numeric', 'Editable', 'off'), ...
                'SciBaudErrorField');
            app.DetailFields.sci_pin_group = labeled_field(app.SciGrid, 3, 1, ...
                'Pin Group', uidropdown(app.SciGrid, 'Items', {'Not Selected'}, ...
                'ItemsData', {''}), 'SciPinGroupField');
            app.DetailFields.sci_rx_pin_type = labeled_field(app.SciGrid, 3, 4, ...
                'RX Pin Type', uidropdown(app.SciGrid, ...
                'Items', {'Standard', 'Pull-up'}), 'SciRxPinTypeField');
            app.DetailFields.sci_rx_qualification = labeled_field(app.SciGrid, 4, 1, ...
                'RX Qualification', uidropdown(app.SciGrid, ...
                'Items', {'Sync', 'Async'}), 'SciRxQualificationField');
            app.DetailFields.sci_tx_pin_type = labeled_field(app.SciGrid, 4, 4, ...
                'TX Pin Type', uidropdown(app.SciGrid, ...
                'Items', {'Standard', 'Pull-up'}), 'SciTxPinTypeField');
            app.DetailFields.sci_ctrl_gpio = labeled_field(app.SciGrid, 5, 1, ...
                'CTRL GPIO', uidropdown(app.SciGrid, 'Items', {'None'}, ...
                'ItemsData', {'None'}), 'SciCtrlGpioField');
            app.DetailFields.sci_ctrl_pin_type = labeled_field(app.SciGrid, 5, 4, ...
                'CTRL Pin Type', uidropdown(app.SciGrid, ...
                'Items', {'Standard', 'Pull-up'}), 'SciCtrlPinTypeField');
            app.DetailFields.sci_ctrl_active_level = labeled_field(app.SciGrid, 6, 1, ...
                'CTRL TX Active Level', uidropdown(app.SciGrid, ...
                'Items', {'High', 'Low'}), 'SciCtrlActiveLevelField');
            keys = {'socket', 'port', 'sci_module', 'sci_baud', ...
                'sci_pin_group', 'sci_rx_pin_type', 'sci_rx_qualification', ...
                'sci_tx_pin_type', 'sci_ctrl_gpio', 'sci_ctrl_pin_type', ...
                'sci_ctrl_active_level'};
            for index = 1:numel(keys)
                key = keys{index};
                app.DetailFields.(key).ValueChangedFcn = ...
                    @(~, ~) app.detailEdited(key);
            end
        end

        function createAlgorithmDetail(app)
            grid = detail_grid(app.AlgorithmTab, 2);
            app.DetailFields.algorithm_mode = labeled_field(grid, 1, 1, ...
                'Algorithm Mode', uidropdown(grid, 'Items', ...
                {'generated_example', 'external_copy', 'external_reference'}), ...
                'AlgorithmModeField');
            sourceLabel = uilabel(grid, 'Text', 'External Source Path');
            sourceLabel.Layout.Row = 2;
            sourceLabel.Layout.Column = 1;
            app.SourcePathGrid = uigridlayout(grid, [1 2]);
            app.SourcePathGrid.ColumnWidth = {'1x', 90};
            app.SourcePathGrid.Padding = [0 0 0 0];
            app.SourcePathGrid.Layout.Row = 2;
            app.SourcePathGrid.Layout.Column = [2 6];
            app.DetailFields.source_path = uieditfield(app.SourcePathGrid, 'text', ...
                'Tag', 'ExternalSourcePathField');
            app.createButton(app.SourcePathGrid, 'Browse', @(~, ~) app.browseSource());
            app.DetailFields.algorithm_mode.ValueChangedFcn = ...
                @(~, ~) app.detailEdited('algorithm_mode');
            app.DetailFields.source_path.ValueChangedFcn = ...
                @(~, ~) app.detailEdited('source_path');
        end

        function createInputsOutputsTab(app, tab)
            outerGrid = uigridlayout(tab, [2 1]);
            outerGrid.RowHeight = {24, '1x'};
            outerGrid.ColumnWidth = {'1x'};
            outerGrid.Padding = [8 8 8 8];
            outerGrid.RowSpacing = 6;
            outerGrid.ColumnSpacing = 0;
            app.InputsOutputsContextLabel = uilabel(outerGrid, ...
                'Text', 'Current Instance: None', ...
                'Tag', 'InputsOutputsInstanceContext');
            app.InputsOutputsTabGroup = uitabgroup(outerGrid);
            app.InputsTab = uitab(app.InputsOutputsTabGroup, 'Title', 'Inputs');
            app.OutputsTab = uitab(app.InputsOutputsTabGroup, 'Title', 'Outputs');
            app.InputTable = app.createVariablePage(app.InputsTab, 'input');
            app.OutputTable = app.createVariablePage(app.OutputsTab, 'output');
        end

        function table = createVariablePage(app, tab, direction)
            grid = uigridlayout(tab, [2 1]);
            grid.RowHeight = {'1x', 38};
            grid.ColumnWidth = {'1x'};
            grid.Padding = [8 8 8 8];
            grid.RowSpacing = 8;
            grid.ColumnSpacing = 0;
            table = app.variableTable(grid);
            app.variableButtons(grid, direction);
        end

        function table = variableTable(app, parent)
            table = uitable(parent, 'ColumnName', {'Name', 'Type', 'Dim'}, ...
                'ColumnFormat', {'char', {'int16', 'uint16', 'int32', ...
                'uint32', 'single', 'double'}, 'numeric'}, ...
                'ColumnEditable', true(1, 3), ...
                'CellEditCallback', @(~, ~) app.variablesEdited());
        end

        function variableButtons(app, parent, direction)
            buttons = uigridlayout(parent, [1 5]);
            buttons.ColumnWidth = {90, 90, 90, 90, '1x'};
            buttons.RowHeight = {'1x'};
            buttons.Padding = [0 0 0 0];
            buttons.RowSpacing = 0;
            buttons.ColumnSpacing = 8;
            app.createButton(buttons, 'Add', ...
                @(~, ~) app.changeVariable(direction, 'add'));
            app.createButton(buttons, 'Remove', ...
                @(~, ~) app.changeVariable(direction, 'remove'));
            app.createButton(buttons, 'Move Up', ...
                @(~, ~) app.changeVariable(direction, 'up'));
            app.createButton(buttons, 'Move Down', ...
                @(~, ~) app.changeVariable(direction, 'down'));
        end

        function button = createButton(~, parent, text, callback)
            host = uipanel(parent, 'BorderType', 'none');
            button = uibutton(host, 'Text', text, ...
                'Position', [1 1 88 30], 'ButtonPushedFcn', callback);
        end

        function createIssuesTab(app, tab)
            outerGrid = uigridlayout(tab, [1 1]);
            outerGrid.RowHeight = {'1x'};
            outerGrid.ColumnWidth = {'1x'};
            outerGrid.Padding = [8 8 8 8];
            outerGrid.RowSpacing = 0;
            outerGrid.ColumnSpacing = 0;
            app.IssuesInterfaceTabGroup = uitabgroup(outerGrid);
            issuesTab = uitab(app.IssuesInterfaceTabGroup, 'Title', 'Issues');
            app.InterfaceTab = uitab(app.IssuesInterfaceTabGroup, ...
                'Title', 'Interface Hash / Memory');
            issuesGrid = uigridlayout(issuesTab, [2 1]);
            issuesGrid.RowHeight = {24, '1x'};
            issuesGrid.ColumnWidth = {'1x'};
            issuesGrid.Padding = [8 8 8 8];
            issuesGrid.RowSpacing = 6;
            issuesGrid.ColumnSpacing = 0;
            app.IssuesContextLabel = uilabel(issuesGrid, ...
                'Text', 'Current Instance: None | Scope: Entire Project', ...
                'Tag', 'IssuesInstanceContext');
            app.IssueTable = uitable(issuesGrid, 'ColumnName', ...
                {'Severity', 'Code', 'Instance', 'Field', 'File', 'Message'}, ...
                'ColumnEditable', false(1, 6), ...
                'CellSelectionCallback', @(~, event) app.issueSelected(event));
            reportGrid = uigridlayout(app.InterfaceTab, [2 1]);
            reportGrid.RowHeight = {24, '1x'};
            reportGrid.ColumnWidth = {'1x'};
            reportGrid.Padding = [8 8 8 8];
            reportGrid.RowSpacing = 6;
            reportGrid.ColumnSpacing = 0;
            app.InterfaceContextLabel = uilabel(reportGrid, ...
                'Text', 'Current Instance: None', ...
                'Tag', 'InterfaceInstanceContext');
            app.ReportArea = uitextarea(reportGrid, 'Editable', 'off', ...
                'FontName', 'Consolas');
        end

        function createCandidatesTab(app, tab)
            grid = uigridlayout(tab, [3 1]);
            grid.RowHeight = {24, '2x', '1x'};
            grid.ColumnWidth = {'1x'};
            grid.Padding = [8 8 8 8];
            grid.RowSpacing = 8;
            grid.ColumnSpacing = 0;
            app.GenerationPreviewInstanceContext = uilabel(grid, ...
                'Text', 'Current Instance: None', ...
                'Tag', 'GenerationPreviewInstanceContext');
            app.CandidateTable = uitable(grid, 'ColumnName', ...
                {'Target Path', 'Category', 'Owner', 'Instance', 'State', ...
                'Selected Action', 'Mandatory', 'Existing Octets', ...
                'Candidate Octets'}, 'ColumnEditable', ...
                [false false false false false true false false false], ...
                'ColumnFormat', {'char', 'char', 'char', 'numeric', 'char', ...
                {'create', 'skip', 'replace', 'keep'}, 'logical', ...
                'numeric', 'numeric'}, ...
                'CellEditCallback', @(~, event) app.candidateEdited(event), ...
                'CellSelectionCallback', @(~, event) app.candidateSelected(event));
            previewTabs = uitabgroup(grid);
            contentTab = uitab(previewTabs, 'Title', 'Candidate Content');
            resultTab = uitab(previewTabs, 'Title', 'Generation Result');
            contentGrid = uigridlayout(contentTab, [1 1]);
            contentGrid.RowHeight = {'1x'};
            contentGrid.ColumnWidth = {'1x'};
            contentGrid.Padding = [8 8 8 8];
            contentGrid.RowSpacing = 0;
            contentGrid.ColumnSpacing = 0;
            resultGrid = uigridlayout(resultTab, [1 1]);
            resultGrid.RowHeight = {'1x'};
            resultGrid.ColumnWidth = {'1x'};
            resultGrid.Padding = [8 8 8 8];
            resultGrid.RowSpacing = 0;
            resultGrid.ColumnSpacing = 0;
            app.CandidateArea = uitextarea(contentGrid, 'Editable', 'off', ...
                'FontName', 'Consolas');
            app.ResultArea = uitextarea(resultGrid, 'Editable', 'off', ...
                'FontName', 'Consolas');
        end

        function refreshAll(app)
            app.Updating = true;
            cleaner = onCleanup(@() app.finishRefresh());
            project = app.ProjectSession.Project;
            app.CommonFields.dsp_model.Value = project.common.dsp_model;
            app.CommonFields.protocol_version.Value = ...
                sprintf('%u', project.common.protocol_version);
            app.CommonFields.abi.Value = project.common.abi;
            app.CommonFields.mac.Value = format_mac(project.common.network.mac);
            app.CommonFields.ip.Value = project.common.network.ip;
            app.CommonFields.gateway.Value = project.common.network.gateway;
            app.CommonFields.subnet.Value = project.common.network.subnet;
            app.CommonFields.dsp_root.Value = project.output.dsp_root;
            app.CommonFields.sfun_root.Value = project.output.sfun_root;
            app.refreshSciClock();
            app.refreshInstances();
            app.showIssues(app.Coordinator.validateProject('instant'));
            app.refreshReport();
            clear cleaner
        end

        function finishRefresh(app)
            app.Updating = false;
        end

        function refreshInstances(app)
            app.refreshSciClock();
            instances = app.ProjectSession.Project.instances;
            data = cell(numel(instances), 6);
            for index = 1:numel(instances)
                value = instances(index);
                transport = c2837x_block_build_transport_summary(value);
                data(index, :) = {value.display_name, value.internal_name, ...
                    transport.type_label, transport.resource, ...
                    transport.link, value.sample_time_sec};
            end
            app.InstanceTable.Data = data;
            if isempty(instances)
                app.SelectedInstance = 0;
                app.clearDetail();
            else
                app.SelectedInstance = min(max(app.SelectedInstance, 1), numel(instances));
                app.showInstance();
            end
        end

        function showInstance(app)
            value = app.ProjectSession.Project.instances(app.SelectedInstance);
            app.DetailFields.display_name.Value = value.display_name;
            app.DetailFields.internal_name.Value = value.internal_name;
            app.DetailFields.iodevice.Value = value.iodevice.type;
            app.DetailFields.sample_time.Value = value.sample_time_sec;
            app.DetailFields.max_payload.Value = double(value.max_payload_size_bytes);
            app.showIoDevice(value);
            app.DetailFields.algorithm_mode.Value = value.algorithm.mode;
            app.DetailFields.source_path.Value = value.algorithm.source_path;
            app.SourcePathGrid.Visible = ...
                matlab.lang.OnOffSwitchState(~strcmp(value.algorithm.mode, 'generated_example'));
            app.InputTable.Data = variables_to_cell(value.inputs);
            app.OutputTable.Data = variables_to_cell(value.outputs);
            app.refreshInstanceContext();
        end

        function clearDetail(app)
            app.DetailFields.display_name.Value = '';
            app.DetailFields.internal_name.Value = '';
            app.DetailFields.iodevice.Value = 'w5300_tcp';
            app.DetailFields.socket.Value = '0';
            app.DetailFields.port.Value = 0;
            app.DetailFields.sample_time.Value = 0;
            app.DetailFields.max_payload.Value = 0;
            app.DetailFields.algorithm_mode.Value = 'generated_example';
            app.DetailFields.source_path.Value = '';
            app.W5300Grid.Visible = 'off';
            app.SciGrid.Visible = 'off';
            app.SourcePathGrid.Visible = 'off';
            app.InputTable.Data = cell(0, 3);
            app.OutputTable.Data = cell(0, 3);
            app.refreshInstanceContext();
        end

        function text = currentInstanceText(app)
            instances = app.ProjectSession.Project.instances;
            if app.SelectedInstance < 1 || ...
                    app.SelectedInstance > numel(instances)
                text = 'Current Instance: None';
                return;
            end
            instance = instances(app.SelectedInstance);
            transport = c2837x_block_build_transport_summary(instance);
            text = sprintf('Current Instance: %s [%s] | %s', ...
                char(instance.display_name), char(instance.internal_name), ...
                transport.summary);
        end

        function refreshInstanceContext(app)
            text = app.currentInstanceText();
            app.InputsOutputsContextLabel.Text = text;
            app.IssuesContextLabel.Text = sprintf('%s | Scope: Entire Project', text);
            app.InterfaceContextLabel.Text = text;
            app.GenerationPreviewInstanceContext.Text = text;
            if strcmp(text, 'Current Instance: None')
                app.InstanceTable.Selection = [];
            else
                columnCount = numel(app.InstanceTable.ColumnName);
                app.InstanceTable.Selection = [ ...
                    repmat(app.SelectedInstance, columnCount, 1), ...
                    (1:columnCount)'];
            end
        end

        function commonEdited(app, key)
            if app.Updating
                return;
            end
            project = app.ProjectSession.Project;
            try
                switch key
                    case 'abi'
                        project.common.abi = app.CommonFields.abi.Value;
                    case 'mac'
                        project.common.network.mac = parse_mac(app.CommonFields.mac.Value);
                    case {'ip', 'gateway', 'subnet'}
                        project.common.network.(key) = strtrim(app.CommonFields.(key).Value);
                    case {'dsp_root', 'sfun_root'}
                        value = strtrim(app.CommonFields.(key).Value);
                        if ~isempty(value)
                            value = c2837x_block_normalize_absolute_path(value);
                        end
                        project.output.(key) = value;
                    otherwise
                        return;
                end
                [applied, issues] = app.Coordinator.updateProjectDraft(project);
                app.finishDraftEdit(applied, issues);
            catch cause
                app.showOperationError(cause);
            end
        end

        function ioDeviceChanged(app)
            if app.Updating || app.SelectedInstance == 0
                return;
            end
            try
                app.Coordinator.switchIoDevice(app.SelectedInstance, ...
                    app.DetailFields.iodevice.Value);
                app.afterEdit();
            catch cause
                app.Updating = true;
                app.showInstance();
                app.Updating = false;
                app.showOperationError(cause);
            end
        end

        function detailEdited(app, editedKey)
            if app.Updating || app.SelectedInstance == 0
                return;
            end
            source = strtrim(app.DetailFields.source_path.Value);
            mode = app.DetailFields.algorithm_mode.Value;
            if strcmp(mode, 'generated_example')
                source = '';
            elseif ~isempty(source)
                source = c2837x_block_normalize_absolute_path(source);
            end
            project = app.ProjectSession.Project;
            instance = project.instances(app.SelectedInstance);
            instance.display_name = strtrim(app.DetailFields.display_name.Value);
            instance.internal_name = strtrim(app.DetailFields.internal_name.Value);
            if strcmp(instance.iodevice.type, 'w5300_tcp')
                instance.iodevice.settings.socket_number = ...
                    str2double(app.DetailFields.socket.Value);
                instance.iodevice.settings.tcp_port = app.DetailFields.port.Value;
            else
                settings = instance.iodevice.settings;
                settings.module = app.DetailFields.sci_module.Value;
                settings.baud = app.DetailFields.sci_baud.Value;
                if isequal(app.DetailFields.sci_pin_group.Enable, ...
                        matlab.lang.OnOffSwitchState.on)
                    settings.pin_group = app.DetailFields.sci_pin_group.Value;
                end
                settings.rx_pin_type = app.DetailFields.sci_rx_pin_type.Value;
                settings.rx_qualification = ...
                    app.DetailFields.sci_rx_qualification.Value;
                settings.tx_pin_type = app.DetailFields.sci_tx_pin_type.Value;
                if isequal(app.DetailFields.sci_ctrl_gpio.Enable, ...
                        matlab.lang.OnOffSwitchState.on)
                    settings.ctrl_gpio = app.DetailFields.sci_ctrl_gpio.Value;
                end
                settings.ctrl_pin_type = app.DetailFields.sci_ctrl_pin_type.Value;
                settings.ctrl_tx_active_level = ...
                    app.DetailFields.sci_ctrl_active_level.Value;
                if strcmp(editedKey, 'sci_module')
                    settings = clear_invalid_pin_group(settings);
                end
                instance.iodevice.settings = settings;
            end
            instance.sample_time_sec = app.DetailFields.sample_time.Value;
            instance.max_payload_size_bytes = app.DetailFields.max_payload.Value;
            instance.algorithm = struct('mode', mode, 'source_path', source);
            project.instances(app.SelectedInstance) = instance;
            [applied, issues] = app.Coordinator.updateProjectDraft(project);
            app.finishDraftEdit(applied, issues);
        end

        function showIoDevice(app, instance)
            isSci = strcmp(instance.iodevice.type, 'sci');
            app.W5300Grid.Visible = matlab.lang.OnOffSwitchState(~isSci);
            app.SciGrid.Visible = matlab.lang.OnOffSwitchState(isSci);
            if ~isSci
                settings = instance.iodevice.settings;
                app.DetailFields.socket.Value = sprintf('%u', settings.socket_number);
                app.DetailFields.port.Value = double(settings.tcp_port);
                return;
            end
            settings = instance.iodevice.settings;
            app.DetailFields.sci_module.Value = settings.module;
            app.DetailFields.sci_baud.Value = double(settings.baud);
            app.DetailFields.sci_rx_pin_type.Value = settings.rx_pin_type;
            app.DetailFields.sci_rx_qualification.Value = settings.rx_qualification;
            app.DetailFields.sci_tx_pin_type.Value = settings.tx_pin_type;
            app.DetailFields.sci_ctrl_pin_type.Value = settings.ctrl_pin_type;
            app.DetailFields.sci_ctrl_active_level.Value = ...
                settings.ctrl_tx_active_level;
            app.refreshSciCapabilityChoices(settings);
            app.refreshSciBaud(settings.baud);
            app.updateCtrlFields();
        end

        function refreshSciCapabilityChoices(app, settings)
            result = c2837x_block_load_device_capability();
            if ~result.available
                app.DetailFields.sci_pin_group.Items = {'Not Selected'};
                app.DetailFields.sci_pin_group.ItemsData = {''};
                app.DetailFields.sci_pin_group.Value = '';
                app.DetailFields.sci_pin_group.Enable = 'off';
                app.DetailFields.sci_ctrl_gpio.Items = {'None'};
                app.DetailFields.sci_ctrl_gpio.ItemsData = {'None'};
                app.DetailFields.sci_ctrl_gpio.Value = 'None';
                app.DetailFields.sci_ctrl_gpio.Enable = 'off';
                return;
            end
            capability = result.capability;
            groups = empty_pin_groups();
            moduleIndex = find(strcmp({capability.sci_modules.id}, ...
                settings.module), 1);
            if ~isempty(moduleIndex)
                groups = capability.sci_modules(moduleIndex).pin_groups;
            end
            app.DetailFields.sci_pin_group.Items = ...
                [{'Not Selected'}, {groups.display_name}];
            app.DetailFields.sci_pin_group.ItemsData = ...
                [{''}, {groups.id}];
            if any(strcmp(settings.pin_group, {groups.id}))
                app.DetailFields.sci_pin_group.Value = settings.pin_group;
            else
                app.DetailFields.sci_pin_group.Value = '';
            end
            app.DetailFields.sci_pin_group.Enable = 'on';
            gpioItems = compose('GPIO%u', [capability.gpios.number]);
            app.DetailFields.sci_ctrl_gpio.Items = [{'None'}, cellstr(gpioItems)];
            app.DetailFields.sci_ctrl_gpio.ItemsData = ...
                [{'None'}, cellstr(gpioItems)];
            if any(strcmp(settings.ctrl_gpio, app.DetailFields.sci_ctrl_gpio.ItemsData))
                app.DetailFields.sci_ctrl_gpio.Value = settings.ctrl_gpio;
            else
                app.DetailFields.sci_ctrl_gpio.Value = 'None';
            end
            app.DetailFields.sci_ctrl_gpio.Enable = 'on';
        end

        function refreshSciBaud(app, requestedBaud)
            clock = c2837x_block_get_sci_clock_config();
            result = c2837x_block_calculate_sci_baud( ...
                clock.lspclk_hz, requestedBaud);
            app.DetailFields.sci_actual_baud.Value = result.actual_baud;
            app.DetailFields.sci_baud_error.Value = result.signed_error_baud;
        end

        function updateCtrlFields(app)
            enabled = ~strcmp(app.DetailFields.sci_ctrl_gpio.Value, 'None') && ...
                isequal(app.DetailFields.sci_ctrl_gpio.Enable, ...
                matlab.lang.OnOffSwitchState.on);
            state = matlab.lang.OnOffSwitchState(enabled);
            app.DetailFields.sci_ctrl_pin_type.Enable = state;
            app.DetailFields.sci_ctrl_active_level.Enable = state;
        end

        function refreshSciClock(app)
            instances = app.ProjectSession.Project.instances;
            hasSci = ~isempty(instances) && any(arrayfun( ...
                @(value) strcmp(value.iodevice.type, 'sci'), instances));
            state = matlab.lang.OnOffSwitchState(hasSci);
            app.ProjectSciClockLabel.Visible = state;
            app.ProjectSciClockField.Visible = state;
            if hasSci
                clock = c2837x_block_get_sci_clock_config();
                app.ProjectSciClockField.Value = sprintf( ...
                    '%.6f MHz (SYSCLK / %u)', ...
                    clock.lspclk_hz / 1e6, clock.lspclk_divisor);
            else
                app.ProjectSciClockField.Value = 'N/A';
            end
        end

        function browseOutput(app, key)
            folder = uigetdir(app.CommonFields.(key).Value, ...
                'Select Output Root');
            if isequal(folder, 0)
                return;
            end
            app.CommonFields.(key).Value = ...
                c2837x_block_normalize_absolute_path(folder);
            app.commonEdited(key);
        end

        function browseSource(app)
            [file, folder] = uigetfile('*.c', 'Select External C Source');
            if isequal(file, 0)
                return;
            end
            app.DetailFields.source_path.Value = ...
                c2837x_block_normalize_absolute_path(fullfile(folder, file));
            app.detailEdited('source_path');
        end

        function variablesEdited(app)
            if app.Updating || app.SelectedInstance == 0
                return;
            end
            project = app.ProjectSession.Project;
            project.instances(app.SelectedInstance).inputs = ...
                cell_to_variables(app.InputTable.Data);
            project.instances(app.SelectedInstance).outputs = ...
                cell_to_variables(app.OutputTable.Data);
            [applied, issues] = app.Coordinator.updateProjectDraft(project);
            app.finishDraftEdit(applied, issues);
        end

        function finishDraftEdit(app, applied, issues)
            app.GenerateButton.Enable = 'off';
            app.clearPreviewDisplay();
            app.showIssues(issues);
            if applied
                app.refreshInstances();
                app.refreshReport();
            end
        end

        function afterEdit(app)
            app.GenerateButton.Enable = 'off';
            app.clearPreviewDisplay();
            app.refreshInstances();
            app.showIssues(app.Coordinator.validateProject('instant'));
            app.refreshReport();
        end

        function instanceSelected(app, event)
            if isempty(event.Indices)
                return;
            end
            app.SelectedInstance = event.Indices(1);
            app.Updating = true;
            app.showInstance();
            app.Updating = false;
            app.refreshReport();
        end

        function addInstance(app)
            instances = app.ProjectSession.Project.instances;
            w5300 = instances(arrayfun( ...
                @(value) strcmp(value.iodevice.type, 'w5300_tcp'), instances));
            usedSockets = double(arrayfun( ...
                @(value) value.iodevice.settings.socket_number, w5300));
            socket = first_free(0:7, usedSockets);
            if isempty(socket)
                app.showIssues(app_issue('APP_NO_SOCKET_AVAILABLE', ...
                    'No W5300 socket is available.', 'project.instances', 0, ''));
                return;
            end
            usedPorts = double(arrayfun( ...
                @(value) value.iodevice.settings.tcp_port, w5300));
            port = first_free(5000:65535, usedPorts);
            internalName = c2837x_block_suggest_unique_name( ...
                'instance', {instances.internal_name});
            displayName = strrep(internalName, 'instance_', 'Instance ');
            variable = struct('name', 'input_value', 'type', 'single', 'dim', 1);
            output = struct('name', 'output_value', 'type', 'single', 'dim', 1);
            changes = struct('display_name', displayName, ...
                'internal_name', internalName, ...
                'iodevice', struct('settings', struct('socket_number', ...
                uint16(socket), 'tcp_port', uint16(port))), ...
                'inputs', variable, 'outputs', output);
            try
                app.Coordinator.addInstance(changes);
                app.SelectedInstance = numel(app.ProjectSession.Project.instances);
                app.afterEdit();
            catch cause
                app.showOperationError(cause);
            end
        end

        function copyInstance(app)
            if app.SelectedInstance == 0
                return;
            end
            instances = app.ProjectSession.Project.instances;
            internalName = c2837x_block_suggest_unique_name( ...
                'instance', {instances.internal_name});
            displayName = strrep(internalName, 'instance_', 'Instance ');
            try
                selected = instances(app.SelectedInstance);
                if strcmp(selected.iodevice.type, 'sci')
                    app.Coordinator.copyInstance(app.SelectedInstance, ...
                        displayName, internalName);
                else
                    w5300 = instances(arrayfun(@(value) ...
                        strcmp(value.iodevice.type, 'w5300_tcp'), instances));
                    socket = first_free(0:7, double(arrayfun( ...
                        @(value) value.iodevice.settings.socket_number, w5300)));
                    port = first_free(5000:65535, double(arrayfun( ...
                        @(value) value.iodevice.settings.tcp_port, w5300)));
                    if isempty(socket)
                        app.showIssues(app_issue('APP_NO_SOCKET_AVAILABLE', ...
                            'No W5300 socket is available.', ...
                            'project.instances', 0, ''));
                        return;
                    end
                    app.Coordinator.copyInstance(app.SelectedInstance, ...
                        displayName, internalName, ...
                        uint16(socket), uint16(port));
                end
                app.SelectedInstance = numel(app.ProjectSession.Project.instances);
                app.afterEdit();
            catch cause
                app.showOperationError(cause);
            end
        end

        function deleteInstance(app)
            if app.SelectedInstance == 0
                return;
            end
            choice = uiconfirm(app.UIFigure, ...
                'Delete the selected instance? Disk files will not be removed.', ...
                'Delete Instance', 'Options', {'Delete', 'Cancel'}, ...
                'DefaultOption', 'Cancel', 'CancelOption', 'Cancel');
            if ~strcmp(choice, 'Delete')
                return;
            end
            app.Coordinator.deleteInstance(app.SelectedInstance);
            app.SelectedInstance = min(app.SelectedInstance, ...
                numel(app.ProjectSession.Project.instances));
            app.afterEdit();
        end

        function changeVariable(app, direction, action)
            if app.SelectedInstance == 0
                return;
            end
            if strcmp(direction, 'input')
                table = app.InputTable;
            else
                table = app.OutputTable;
            end
            data = table.Data;
            row = [];
            if ~isempty(table.Selection)
                row = table.Selection(1);
            end
            switch action
                case 'add'
                    instance = app.ProjectSession.Project.instances( ...
                        app.SelectedInstance);
                    existingNames = [{instance.inputs.name}, ...
                        {instance.outputs.name}];
                    name = c2837x_block_suggest_unique_name( ...
                        [direction '_value'], existingNames);
                    data(end + 1, :) = {name, 'single', 1};
                case 'remove'
                    if isempty(row) || size(data, 1) <= 1
                        return;
                    end
                    data(row, :) = [];
                case 'up'
                    if isempty(row) || row <= 1
                        return;
                    end
                    data([row - 1 row], :) = data([row row - 1], :);
                case 'down'
                    if isempty(row) || row >= size(data, 1)
                        return;
                    end
                    data([row row + 1], :) = data([row + 1 row], :);
            end
            table.Data = data;
            app.variablesEdited();
        end

        function previewRequested(app)
            [view, issues] = app.Coordinator.createPreview();
            app.showIssues(issues);
            app.showCandidates(view.comparisons);
            app.refreshReport();
            app.GenerateButton.Enable = ...
                matlab.lang.OnOffSwitchState(strcmp(view.status, 'valid'));
            app.StatusLabel.Text = sprintf('Preview: %s', view.status);
            app.showLegacyRisks(view.legacy_file_risks);
        end

        function generateRequested(app)
            [result, issues] = app.Coordinator.commitPreview();
            app.showIssues(issues);
            app.GenerateButton.Enable = 'off';
            app.ResultArea.Value = format_result(result, ...
                app.ProjectSession.Project, app.Coordinator.LegacyFileRisks);
            if isfield(result, 'status')
                app.StatusLabel.Text = sprintf('Generate: %s', result.status);
            end
        end

        function candidateEdited(app, event)
            issues = app.Coordinator.setCandidateAction( ...
                event.Indices(1), event.NewData);
            if ~isempty(issues)
                app.showIssues(issues);
            end
            app.showCandidates(app.Coordinator.PreviewSnapshot.comparison_baseline);
        end

        function candidateSelected(app, event)
            if isempty(event.Indices) || isempty(app.Coordinator.PreviewCandidates)
                return;
            end
            bytes = app.Coordinator.PreviewCandidates(event.Indices(1)).content_bytes;
            try
                text = native2unicode(bytes, 'UTF-8');
                if ~isequal(unicode2native(text, 'UTF-8'), bytes)
                    error('C2837xBlock:App:NonUtf8', 'Non-UTF-8 content.');
                end
                app.CandidateArea.Value = splitlines(string(text));
            catch
                limit = min(numel(bytes), 128);
                app.CandidateArea.Value = {sprintf('Hex (%u/%u octets):', ...
                    limit, numel(bytes)), sprintf('%02X ', bytes(1:limit))};
            end
        end

        function showCandidates(app, comparisons)
            data = cell(numel(comparisons), 9);
            for index = 1:numel(comparisons)
                value = comparisons(index);
                data(index, :) = {value.target_path, value.category, value.owner, ...
                    value.instance_index, value.target_state, value.selected_action, ...
                    value.action_mandatory, value.existing_size_octets, ...
                    value.content_size_octets};
            end
            app.CandidateTable.Data = data;
        end

        function showIssues(app, issues)
            data = cell(numel(issues), 6);
            for index = 1:numel(issues)
                value = issues(index);
                data(index, :) = {value.severity, value.code, ...
                    value.instance_index, value.field_path, value.file_path, ...
                    value.message};
            end
            app.IssueTable.Data = data;
        end

        function issueSelected(app, event)
            if isempty(event.Indices)
                return;
            end
            row = event.Indices(1);
            data = app.IssueTable.Data;
            instanceIndex = data{row, 3};
            if instanceIndex >= 1 && ...
                    instanceIndex <= numel(app.ProjectSession.Project.instances)
                app.SelectedInstance = instanceIndex;
                app.Updating = true;
                app.showInstance();
                app.Updating = false;
                app.refreshReport();
            end
            if ~isempty(data{row, 5})
                app.StatusLabel.Text = data{row, 5};
            end
            app.navigateToIssue(data{row, 2}, data{row, 4}, data{row, 5});
            app.focusIssueField(data{row, 4});
        end

        function navigateToIssue(app, code, fieldPath, filePath)
            issueText = lower(strjoin(string({code, fieldPath, filePath}), ' '));
            if contains(issueText, '.iodevice.settings.')
                app.MainTabGroup.SelectedTab = app.InstancesTab;
                app.DetailTabGroup.SelectedTab = app.IoDeviceTab;
            elseif contains(issueText, '.inputs')
                app.MainTabGroup.SelectedTab = app.InputsOutputsTab;
                app.InputsOutputsTabGroup.SelectedTab = app.InputsTab;
            elseif contains(issueText, '.outputs')
                app.MainTabGroup.SelectedTab = app.InputsOutputsTab;
                app.InputsOutputsTabGroup.SelectedTab = app.OutputsTab;
            elseif any(contains(issueText, ...
                    ["preview", "candidate", "generation", "generated file"]))
                app.MainTabGroup.SelectedTab = app.GenerationPreviewTab;
            elseif any(contains(issueText, ["hash", "memory", "report"]))
                app.MainTabGroup.SelectedTab = app.IssuesInterfaceTab;
                app.IssuesInterfaceTabGroup.SelectedTab = app.InterfaceTab;
            elseif contains(issueText, 'project.common') || ...
                    contains(issueText, 'project.output')
                app.MainTabGroup.SelectedTab = app.ProjectTab;
            elseif contains(issueText, 'project.instances')
                app.MainTabGroup.SelectedTab = app.InstancesTab;
            end
        end

        function focusIssueField(app, fieldPath)
            if contains(fieldPath, '.display_name')
                focus(app.DetailFields.display_name);
            elseif contains(fieldPath, '.internal_name')
                focus(app.DetailFields.internal_name);
            elseif contains(fieldPath, '.socket_number')
                focus(app.DetailFields.socket);
            elseif contains(fieldPath, '.tcp_port')
                focus(app.DetailFields.port);
            elseif contains(fieldPath, '.iodevice.settings.module')
                focus(app.DetailFields.sci_module);
            elseif contains(fieldPath, '.iodevice.settings.baud')
                focus(app.DetailFields.sci_baud);
            elseif contains(fieldPath, '.iodevice.settings.pin_group')
                focus(app.DetailFields.sci_pin_group);
            elseif contains(fieldPath, '.iodevice.settings.rx_pin_type')
                focus(app.DetailFields.sci_rx_pin_type);
            elseif contains(fieldPath, '.iodevice.settings.rx_qualification')
                focus(app.DetailFields.sci_rx_qualification);
            elseif contains(fieldPath, '.iodevice.settings.tx_pin_type')
                focus(app.DetailFields.sci_tx_pin_type);
            elseif contains(fieldPath, '.iodevice.settings.ctrl_gpio')
                focus(app.DetailFields.sci_ctrl_gpio);
            elseif contains(fieldPath, '.iodevice.settings.ctrl_pin_type')
                focus(app.DetailFields.sci_ctrl_pin_type);
            elseif contains(fieldPath, '.iodevice.settings.ctrl_tx_active_level')
                focus(app.DetailFields.sci_ctrl_active_level);
            elseif contains(fieldPath, '.sample_time_sec')
                focus(app.DetailFields.sample_time);
            elseif contains(fieldPath, '.max_payload_size_bytes')
                focus(app.DetailFields.max_payload);
            elseif contains(fieldPath, '.algorithm.mode')
                focus(app.DetailFields.algorithm_mode);
            elseif contains(fieldPath, '.algorithm.source_path')
                focus(app.DetailFields.source_path);
            elseif contains(fieldPath, '.inputs')
                focus(app.InputTable);
            elseif contains(fieldPath, '.outputs')
                focus(app.OutputTable);
            elseif contains(fieldPath, 'project.common.network.mac')
                focus(app.CommonFields.mac);
            elseif contains(fieldPath, 'project.common.network.ip')
                focus(app.CommonFields.ip);
            elseif contains(fieldPath, 'project.common.network.gateway')
                focus(app.CommonFields.gateway);
            elseif contains(fieldPath, 'project.common.network.subnet')
                focus(app.CommonFields.subnet);
            elseif contains(fieldPath, 'project.output.dsp_root')
                focus(app.CommonFields.dsp_root);
            elseif contains(fieldPath, 'project.output.sfun_root')
                focus(app.CommonFields.sfun_root);
            end
        end

        function refreshReport(app)
            [report, issues] = c2837x_block_build_project_report( ...
                app.ProjectSession.Project);
            if ~isempty(issues)
                app.ReportArea.Value = {issues.message};
                return;
            end
            lines = {sprintf('Project Total Protocol Buffer Words: %u', ...
                report.total_protocol_buffer_words)};
            if app.SelectedInstance >= 1 && ...
                    app.SelectedInstance <= numel(report.instances)
                value = report.instances(app.SelectedInstance);
                instance = app.ProjectSession.Project.instances(app.SelectedInstance);
                transport = c2837x_block_build_transport_summary(instance);
                lines = [lines, {sprintf('Selected Instance: %s [%s]', ...
                    char(instance.display_name), char(instance.internal_name)), ...
                    sprintf('Transport: %s', transport.summary), ...
                    sprintf('Max Payload Limit: %u wire octets', ...
                    instance.max_payload_size_bytes), ...
                    sprintf('Interface Hash: 0x%08X', value.interface_hash), ...
                    sprintf('Input Data Octets: %u', value.input_data_octets), ...
                    sprintf('Output Data Octets: %u', value.output_data_octets), ...
                    sprintf('Input Payload Octets: %u', value.input_payload_octets), ...
                    sprintf('Output Payload Octets: %u', value.output_payload_octets), ...
                    sprintf('Instance Protocol Buffer Words: %u', ...
                    value.protocol_buffer_words), ...
                    sprintf('RX Frame Words: %u', value.rx_frame_words), ...
                    sprintf('TX Frame Words: %u', value.tx_frame_words), ...
                    sprintf('Canonical UTF-8 Octets: %u', value.canonical_utf8_octets), ...
                    'Canonical Hash Text:', value.canonical_text}];
            end
            app.ReportArea.Value = lines;
        end

        function saveRequested(app)
            app.saveCurrentProject();
        end

        function saved = saveCurrentProject(app)
            path = app.ProjectSession.FilePath;
            if isempty(path)
                [file, folder] = uiputfile('*.mat', 'Save Project', ...
                    app.ProjectSession.DefaultFileName);
                if isequal(file, 0)
                    saved = false;
                    return;
                end
                path = fullfile(folder, file);
            end
            [saved, issues, requiresConfirmation] = ...
                app.Coordinator.saveProject(path, false);
            app.showIssues(issues);
            if requiresConfirmation
                choice = uiconfirm(app.UIFigure, ...
                    'The project has validation issues.', 'Save Project', ...
                    'Options', {'Save Current Configuration', 'Cancel'}, ...
                    'DefaultOption', 'Cancel', 'CancelOption', 'Cancel');
                if ~strcmp(choice, 'Save Current Configuration')
                    saved = false;
                    return;
                end
                [saved, issues] = app.Coordinator.saveProject(path, true);
                app.showIssues(issues);
            end
            if saved
                app.StatusLabel.Text = sprintf('Saved: %s', path);
            end
        end

        function loadRequested(app)
            [file, folder] = uigetfile('*.mat', 'Load Project');
            if isequal(file, 0)
                return;
            end
            choice = app.discardDecision();
            if strcmp(choice, 'Cancel')
                return;
            end
            if strcmp(choice, 'Save') && ~app.saveCurrentProject()
                return;
            end
            [loaded, issues] = app.Coordinator.loadProject(fullfile(folder, file));
            app.showIssues(issues);
            if loaded
                if isempty(app.ProjectSession.Project.instances)
                    app.SelectedInstance = 0;
                else
                    app.SelectedInstance = 1;
                end
                app.refreshAll();
                app.clearPreviewDisplay();
                app.GenerateButton.Enable = 'off';
            end
        end

        function closeRequested(app, source)
            if ~app.ProjectSession.Dirty
                delete(source);
                return;
            end
            choice = app.discardDecision();
            if strcmp(choice, 'Cancel')
                return;
            end
            if strcmp(choice, 'Save') && ~app.saveCurrentProject()
                return;
            end
            delete(source);
        end

        function choice = discardDecision(app)
            choice = 'Don''t Save';
            if ~app.ProjectSession.Dirty
                return;
            end
            choice = uiconfirm(app.UIFigure, 'The project has unsaved changes.', ...
                'Unsaved Project', 'Options', {'Save', 'Don''t Save', 'Cancel'}, ...
                'DefaultOption', 'Cancel', 'CancelOption', 'Cancel');
        end

        function clearPreviewDisplay(app)
            app.CandidateTable.Data = cell(0, 9);
            app.CandidateArea.Value = {''};
            app.ResultArea.Value = {''};
        end

        function showLegacyRisks(app, risks)
            if isempty(risks)
                return;
            end
            lines = arrayfun(@(risk) sprintf('LegacyFileRisk: %s %s - %s', ...
                risk.action, risk.internal_name, risk.reason), risks, ...
                'UniformOutput', false);
            app.ResultArea.Value = lines;
        end

        function showOperationError(app, cause)
            app.StatusLabel.Text = cause.identifier;
        end
    end
end

function grid = detail_grid(parent, rows)
rowHeight = 34;
rowSpacing = 6;
grid = uigridlayout(parent, [rows + 1, 6]);
if isa(parent, 'matlab.ui.container.GridLayout')
    grid.Layout.Row = 1;
    grid.Layout.Column = 1;
end
grid.ColumnWidth = {190, 280, 24, 220, 280, '1x'};
grid.RowHeight = [repmat({rowHeight}, 1, rows), {'1x'}];
grid.Padding = [8 8 8 8];
grid.RowSpacing = rowSpacing;
grid.ColumnSpacing = 0;
end

function field = labeled_field(grid, row, labelColumn, labelText, field, tag)
label = uilabel(grid, 'Text', labelText);
label.Layout.Row = row;
label.Layout.Column = labelColumn;
field.Layout.Row = row;
field.Layout.Column = labelColumn + 1;
field.Tag = tag;
end

function settings = clear_invalid_pin_group(settings)
result = c2837x_block_load_device_capability();
if ~result.available
    return;
end
modules = result.capability.sci_modules;
moduleIndex = find(strcmp({modules.id}, settings.module), 1);
validIds = {};
if ~isempty(moduleIndex)
    validIds = {modules(moduleIndex).pin_groups.id};
end
if ~any(strcmp(settings.pin_group, validIds))
    settings.pin_group = '';
end
end

function groups = empty_pin_groups()
groups = struct('id', {}, 'display_name', {}, 'rx', {}, 'tx', {});
end

function options = validate_options(options)
expected = {'visible'; 'preview_provider'};
if ~isstruct(options) || ~isscalar(options) || ...
        ~isequal(sort(fieldnames(options)), sort(expected)) || ...
        ~((ischar(options.visible) && isrow(options.visible)) || ...
        (isstring(options.visible) && isscalar(options.visible))) || ...
        ~any(strcmp(char(options.visible), {'on', 'off'})) || ...
        ~(isempty(options.preview_provider) || ...
        (isa(options.preview_provider, 'function_handle') && ...
        isscalar(options.preview_provider)))
    error('C2837xBlock:App:InvalidOptions', ...
        'Options must contain only visible and preview_provider.');
end
options.visible = char(options.visible);
end

function values = cell_to_variables(data)
prototype = struct('name', '', 'type', '', 'dim', 1);
values = repmat(prototype, 1, size(data, 1));
for index = 1:size(data, 1)
    values(index) = struct('name', strtrim(char(string(data{index, 1}))), ...
        'type', char(string(data{index, 2})), 'dim', data{index, 3});
end
end

function data = variables_to_cell(values)
data = cell(numel(values), 3);
for index = 1:numel(values)
    data(index, :) = {values(index).name, values(index).type, values(index).dim};
end
end

function value = first_free(candidates, used)
value = candidates(find(~ismember(candidates, used), 1));
end

function value = parse_mac(text)
parts = regexp(strtrim(text), '[:-]', 'split');
if numel(parts) ~= 6 || any(cellfun(@(part) numel(part) ~= 2, parts))
    value = zeros(1, 0, 'uint8');
    return;
end
try
    value = uint8(hex2dec(char(parts))');
catch
    value = zeros(1, 0, 'uint8');
end
end

function text = format_mac(value)
if numel(value) ~= 6
    text = '';
else
    text = strjoin(compose('%02X', value), ':');
end
end

function issue = app_issue(code, message, fieldPath, instanceIndex, filePath)
issue = struct('severity', 'Error', 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', instanceIndex, ...
    'file_path', filePath);
end

function lines = format_result(result, project, risks)
lines = c2837x_block_format_generation_result(result, project, risks);
end
