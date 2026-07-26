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
        SelectedInstance = 0
        Updating = false
    end

    methods
        function app = C2837xBlockConfigurator(options)
            if nargin < 1
                options = struct('visible', 'on', 'preview_provider', []);
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
                'Visible', visible, 'Position', [50 50 1400 850], ...
                'CloseRequestFcn', @(src, ~) app.closeRequested(src));
            root = uigridlayout(app.UIFigure, [4 1]);
            root.RowHeight = {36, 190, '1x', 24};
            root.Padding = [8 8 8 8];

            toolbar = uigridlayout(root, [1 5]);
            toolbar.ColumnWidth = {90, 90, 90, 90, '1x'};
            uibutton(toolbar, 'Text', 'Save', ...
                'ButtonPushedFcn', @(~, ~) app.saveRequested());
            uibutton(toolbar, 'Text', 'Load', ...
                'ButtonPushedFcn', @(~, ~) app.loadRequested());
            uibutton(toolbar, 'Text', 'Preview', ...
                'ButtonPushedFcn', @(~, ~) app.previewRequested());
            app.GenerateButton = uibutton(toolbar, 'Text', 'Generate', ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.generateRequested());

            commonPanel = uipanel(root, 'Title', 'Project Common Configuration');
            common = uigridlayout(commonPanel, [5 4]);
            common.ColumnWidth = {130, '1x', 150, '1x'};
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
                    pathGrid.ColumnWidth = {'1x', 70};
                    pathGrid.Padding = [0 0 0 0];
                    field = uieditfield(pathGrid, 'text');
                    uibutton(pathGrid, 'Text', 'Browse', ...
                        'ButtonPushedFcn', @(~, ~) app.browseOutput(keys{index}));
                else
                    field = uieditfield(common, 'text');
                end
                field.ValueChangedFcn = @(~, ~) app.commonEdited(keys{index});
                app.CommonFields.(keys{index}) = field;
            end
            app.CommonFields.dsp_model.Editable = 'off';
            app.CommonFields.protocol_version.Editable = 'off';

            tabs = uitabgroup(root);
            app.createInstancesTab(uitab(tabs, 'Title', 'Instances'));
            app.createIssuesTab(uitab(tabs, 'Title', 'Issues / Hash'));
            app.createCandidatesTab(uitab(tabs, 'Title', 'Candidate Preview'));

            app.StatusLabel = uilabel(root, 'Text', 'Ready');
        end

        function createInstancesTab(app, tab)
            grid = uigridlayout(tab, [1 3]);
            grid.ColumnWidth = {'2x', '2x', '3x'};
            listPanel = uipanel(grid, 'Title', 'Instances');
            listGrid = uigridlayout(listPanel, [2 1]);
            listGrid.RowHeight = {'1x', 30};
            app.InstanceTable = uitable(listGrid, 'ColumnName', ...
                {'Display Name', 'Internal Name', 'IoDevice', 'Socket', ...
                'TCP Port', 'Sample Time'}, 'ColumnEditable', false(1, 6), ...
                'CellSelectionCallback', @(~, event) app.instanceSelected(event));
            buttons = uigridlayout(listGrid, [1 3]);
            uibutton(buttons, 'Text', 'Add', ...
                'ButtonPushedFcn', @(~, ~) app.addInstance());
            uibutton(buttons, 'Text', 'Copy', ...
                'ButtonPushedFcn', @(~, ~) app.copyInstance());
            uibutton(buttons, 'Text', 'Delete', ...
                'ButtonPushedFcn', @(~, ~) app.deleteInstance());

            detailPanel = uipanel(grid, 'Title', 'Instance Detail');
            detail = uigridlayout(detailPanel, [9 2]);
            detail.ColumnWidth = {140, '1x'};
            detailKeys = {'display_name', 'internal_name', 'iodevice', ...
                'socket', 'port', 'sample_time', 'max_payload', ...
                'algorithm_mode', 'source_path'};
            detailLabels = {'Display Name', 'Internal Name', 'IoDevice', ...
                'Socket', 'TCP Port', 'Sample Time', 'Max Payload', ...
                'Algorithm Mode', 'External Source Path'};
            app.DetailFields = struct();
            for index = 1:numel(detailKeys)
                uilabel(detail, 'Text', detailLabels{index});
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
                    pathGrid.ColumnWidth = {'1x', 70};
                    pathGrid.Padding = [0 0 0 0];
                    app.SourcePathGrid = pathGrid;
                    field = uieditfield(pathGrid, 'text');
                    uibutton(pathGrid, 'Text', 'Browse', ...
                        'ButtonPushedFcn', @(~, ~) app.browseSource());
                else
                    field = uieditfield(detail, 'text');
                end
                field.ValueChangedFcn = @(~, ~) app.detailEdited();
                app.DetailFields.(key) = field;
            end
            app.DetailFields.iodevice.Editable = 'off';

            ioPanel = uipanel(grid, 'Title', 'Inputs / Outputs');
            io = uigridlayout(ioPanel, [6 1]);
            io.RowHeight = {22, '1x', 30, 22, '1x', 30};
            uilabel(io, 'Text', 'Inputs', 'FontWeight', 'bold');
            app.InputTable = app.variableTable(io);
            app.variableButtons(io, 'input');
            uilabel(io, 'Text', 'Outputs', 'FontWeight', 'bold');
            app.OutputTable = app.variableTable(io);
            app.variableButtons(io, 'output');
        end

        function table = variableTable(app, parent)
            table = uitable(parent, 'ColumnName', {'Name', 'Type', 'Dim'}, ...
                'ColumnFormat', {'char', {'int16', 'uint16', 'int32', ...
                'uint32', 'single', 'double'}, 'numeric'}, ...
                'ColumnEditable', true(1, 3), ...
                'CellEditCallback', @(~, ~) app.variablesEdited());
        end

        function variableButtons(app, parent, direction)
            buttons = uigridlayout(parent, [1 4]);
            uibutton(buttons, 'Text', 'Add', 'ButtonPushedFcn', ...
                @(~, ~) app.changeVariable(direction, 'add'));
            uibutton(buttons, 'Text', 'Remove', 'ButtonPushedFcn', ...
                @(~, ~) app.changeVariable(direction, 'remove'));
            uibutton(buttons, 'Text', 'Move Up', 'ButtonPushedFcn', ...
                @(~, ~) app.changeVariable(direction, 'up'));
            uibutton(buttons, 'Text', 'Move Down', 'ButtonPushedFcn', ...
                @(~, ~) app.changeVariable(direction, 'down'));
        end

        function createIssuesTab(app, tab)
            grid = uigridlayout(tab, [1 2]);
            grid.ColumnWidth = {'3x', '2x'};
            app.IssueTable = uitable(grid, 'ColumnName', ...
                {'Severity', 'Code', 'Instance', 'Field', 'File', 'Message'}, ...
                'ColumnEditable', false(1, 6), ...
                'CellSelectionCallback', @(~, event) app.issueSelected(event));
            app.ReportArea = uitextarea(grid, 'Editable', 'off', ...
                'FontName', 'Consolas');
        end

        function createCandidatesTab(app, tab)
            grid = uigridlayout(tab, [3 1]);
            grid.RowHeight = {'2x', '1x', '1x'};
            app.CandidateTable = uitable(grid, 'ColumnName', ...
                {'Target Path', 'Category', 'Owner', 'Instance', 'State', ...
                'Selected Action', 'Mandatory', 'Existing Octets', ...
                'Candidate Octets'}, 'ColumnEditable', ...
                [false false false false false true false false false], ...
                'CellEditCallback', @(~, event) app.candidateEdited(event), ...
                'CellSelectionCallback', @(~, event) app.candidateSelected(event));
            app.CandidateArea = uitextarea(grid, 'Editable', 'off', ...
                'FontName', 'Consolas');
            app.ResultArea = uitextarea(grid, 'Editable', 'off', ...
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
                app.Coordinator.LegacyFileRisks);
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
            end
            if ~isempty(data{row, 5})
                app.StatusLabel.Text = data{row, 5};
            end
            app.focusIssueField(data{row, 4});
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
                lines = [lines, {sprintf('Interface Hash: 0x%08X', value.interface_hash), ...
                    sprintf('Input Data Octets: %u', value.input_data_octets), ...
                    sprintf('Output Data Octets: %u', value.output_data_octets), ...
                    sprintf('Input Payload Octets: %u', value.input_payload_octets), ...
                    sprintf('Output Payload Octets: %u', value.output_payload_octets), ...
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

function lines = format_result(result, risks)
if isempty(fieldnames(result))
    lines = {'Generate blocked: valid Preview required.'};
    return;
end
lines = cell(1, 10 + numel(risks));
lines(1:10) = {sprintf('Created: %u', result.created_count), ...
    sprintf('Replaced: %u', result.replaced_count), ...
    sprintf('Skipped: %u', result.skipped_count), ...
    sprintf('Kept: %u', result.kept_count), ...
    sprintf('Failed: %u', result.failed_count), ...
    sprintf('Not Attempted: %u', result.not_attempted_count), ...
    sprintf('Created Directories: %u', numel(result.created_directories)), ...
    sprintf('Temporary Files Remaining: %u', ...
    numel(result.temporary_files_remaining)), ...
    sprintf('DSP Root: %s', result.dsp_root), ...
    sprintf('S-Function Root: %s', result.sfun_root)};
for index = 1:numel(risks)
    lines{10 + index} = sprintf('LegacyFileRisk: %s %s - %s', ...
        risks(index).action, risks(index).internal_name, risks(index).reason);
end
end
