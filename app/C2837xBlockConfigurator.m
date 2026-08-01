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
        InstanceTable
        DetailFields
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
            projectGrid.RowHeight = {260, '1x'};
            projectGrid.ColumnWidth = {'1x'};
            projectGrid.Padding = [8 8 8 8];
            projectGrid.RowSpacing = 8;
            projectGrid.ColumnSpacing = 0;
            commonPanel = uipanel(projectGrid, ...
                'Title', 'Project Common Configuration');
            common = uigridlayout(commonPanel, [5 4]);
            common.ColumnWidth = {160, '1x', 160, '1x'};
            common.RowHeight = {36, 36, 36, 36, 36};
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
        end

        function createInstancesTab(app, tab)
            grid = uigridlayout(tab, [2 1]);
            grid.RowHeight = {'1x', 250};
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
                {'Display Name', 'Internal Name', 'IoDevice', 'Socket', ...
                'TCP Port', 'Sample Time'}, 'ColumnEditable', false(1, 6), ...
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
            detail = uigridlayout(detailPanel, [5 4]);
            detail.ColumnWidth = {205, '1x', 140, '1x'};
            detail.RowHeight = {'1x', '1x', '1x', '1x', '1x'};
            detail.Padding = [8 8 8 8];
            detail.RowSpacing = 8;
            detail.ColumnSpacing = 8;
            detailKeys = {'display_name', 'internal_name', 'iodevice', ...
                'socket', 'port', 'sample_time', 'max_payload', ...
                'algorithm_mode', 'source_path'};
            detailLabels = {'Display Name', 'Internal Name', 'IoDevice', ...
                'Socket', 'TCP Port', 'Sample Time', ...
                'Max Payload Limit (wire octets)', ...
                'Algorithm Mode', 'External Source Path'};
            app.DetailFields = struct();
            for index = 1:numel(detailKeys)
                row = ceil(index / 2);
                labelColumn = 1 + 2 * mod(index - 1, 2);
                label = uilabel(detail, 'Text', detailLabels{index});
                label.Layout.Row = row;
                label.Layout.Column = labelColumn;
                key = detailKeys{index};
                if strcmp(key, 'socket')
                    field = uidropdown(detail, 'Items', compose('%u', 0:7));
                elseif strcmp(key, 'algorithm_mode')
                    field = uidropdown(detail, 'Items', ...
                        {'generated_example', 'external_copy', 'external_reference'});
                elseif any(strcmp(key, {'port', 'sample_time', 'max_payload'}))
                    field = uieditfield(detail, 'numeric');
                elseif strcmp(key, 'source_path')
                    pathGrid = uigridlayout(detail, [1 2]);
                    pathGrid.ColumnWidth = {'1x', 90};
                    pathGrid.RowHeight = {'1x'};
                    pathGrid.Padding = [0 0 0 0];
                    pathGrid.RowSpacing = 0;
                    pathGrid.ColumnSpacing = 8;
                    app.SourcePathGrid = pathGrid;
                    field = uieditfield(pathGrid, 'text');
                    app.createButton(pathGrid, 'Browse', ...
                        @(~, ~) app.browseSource());
                else
                    field = uieditfield(detail, 'text');
                end
                if strcmp(key, 'source_path')
                    pathGrid.Layout.Row = row;
                    pathGrid.Layout.Column = [2 4];
                else
                    field.Layout.Row = row;
                    field.Layout.Column = labelColumn + 1;
                end
                field.ValueChangedFcn = @(~, ~) app.detailEdited();
                app.DetailFields.(key) = field;
                if strcmp(key, 'max_payload')
                    tooltip = ['Protocol safety limit only. RX/TX buffers ' ...
                        'use actual legal message lengths.'];
                    label.Tag = 'MaxPayloadLimitLabel';
                    label.Tooltip = tooltip;
                    field.Tag = 'MaxPayloadLimitField';
                    field.Tooltip = tooltip;
                end
            end
            app.DetailFields.iodevice.Editable = 'off';
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
            grid = uigridlayout(tab, [2 1]);
            grid.RowHeight = {'2x', '1x'};
            grid.ColumnWidth = {'1x'};
            grid.Padding = [8 8 8 8];
            grid.RowSpacing = 8;
            grid.ColumnSpacing = 0;
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
            app.refreshInstances();
            app.showIssues(app.Coordinator.validateProject('instant'));
            app.refreshReport();
            clear cleaner
        end

        function finishRefresh(app)
            app.Updating = false;
        end

        function refreshInstances(app)
            instances = app.ProjectSession.Project.instances;
            data = cell(numel(instances), 6);
            for index = 1:numel(instances)
                value = instances(index);
                data(index, :) = {value.display_name, value.internal_name, ...
                    value.iodevice.type, double(value.iodevice.settings.socket_number), ...
                    double(value.iodevice.settings.tcp_port), value.sample_time_sec};
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
            app.DetailFields.socket.Value = sprintf('%u', value.iodevice.settings.socket_number);
            app.DetailFields.port.Value = double(value.iodevice.settings.tcp_port);
            app.DetailFields.sample_time.Value = value.sample_time_sec;
            app.DetailFields.max_payload.Value = double(value.max_payload_size_bytes);
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
            app.DetailFields.iodevice.Value = '';
            app.DetailFields.socket.Value = '0';
            app.DetailFields.port.Value = 0;
            app.DetailFields.sample_time.Value = 0;
            app.DetailFields.max_payload.Value = 0;
            app.DetailFields.algorithm_mode.Value = 'generated_example';
            app.DetailFields.source_path.Value = '';
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
            text = sprintf('Current Instance: %s [%s]', ...
                char(instance.display_name), char(instance.internal_name));
        end

        function refreshInstanceContext(app)
            text = app.currentInstanceText();
            app.InputsOutputsContextLabel.Text = text;
            app.IssuesContextLabel.Text = sprintf('%s | Scope: Entire Project', text);
            app.InterfaceContextLabel.Text = text;
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

        function detailEdited(app)
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
            instance.iodevice.settings.socket_number = ...
                str2double(app.DetailFields.socket.Value);
            instance.iodevice.settings.tcp_port = app.DetailFields.port.Value;
            instance.sample_time_sec = app.DetailFields.sample_time.Value;
            instance.max_payload_size_bytes = app.DetailFields.max_payload.Value;
            instance.algorithm = struct('mode', mode, 'source_path', source);
            project.instances(app.SelectedInstance) = instance;
            [applied, issues] = app.Coordinator.updateProjectDraft(project);
            app.finishDraftEdit(applied, issues);
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
            app.detailEdited();
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
            usedSockets = double(arrayfun(@(x) x.iodevice.settings.socket_number, ...
                app.ProjectSession.Project.instances));
            socket = first_free(0:7, usedSockets);
            if isempty(socket)
                app.showIssues(app_issue('APP_NO_SOCKET_AVAILABLE', ...
                    'No W5300 socket is available.', 'project.instances', 0, ''));
                return;
            end
            usedPorts = double(arrayfun(@(x) x.iodevice.settings.tcp_port, ...
                app.ProjectSession.Project.instances));
            port = first_free(5000:65535, usedPorts);
            instances = app.ProjectSession.Project.instances;
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
            socket = first_free(0:7, double(arrayfun( ...
                @(x) x.iodevice.settings.socket_number, instances)));
            port = first_free(5000:65535, double(arrayfun( ...
                @(x) x.iodevice.settings.tcp_port, instances)));
            if isempty(socket)
                app.showIssues(app_issue('APP_NO_SOCKET_AVAILABLE', ...
                    'No W5300 socket is available.', 'project.instances', 0, ''));
                return;
            end
            internalName = c2837x_block_suggest_unique_name( ...
                'instance', {instances.internal_name});
            displayName = strrep(internalName, 'instance_', 'Instance ');
            try
                app.Coordinator.copyInstance(app.SelectedInstance, ...
                    displayName, internalName, ...
                    uint16(socket), uint16(port));
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
            if contains(issueText, '.inputs')
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
                lines = [lines, {sprintf('Selected Instance: %s [%s]', ...
                    char(instance.display_name), char(instance.internal_name)), ...
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
