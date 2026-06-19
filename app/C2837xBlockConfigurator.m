classdef C2837xBlockConfigurator < handle
%C2837XBLOCKCONFIGURATOR  MATLAB App for C2837xBlock configuration and code generation.
%
%   Usage:
%     app = C2837xBlockConfigurator;
%
%   Generates DSP-side and PC-side configuration files from a GUI.

    properties (Access = private)
        UIFigure           matlab.ui.Figure
        MainGrid           matlab.ui.container.GridLayout

        % Left panel
        InputLabel          matlab.ui.control.Label
        InputTable          matlab.ui.control.Table
        AddInputBtn         matlab.ui.control.Button
        RemoveInputBtn      matlab.ui.control.Button
        RemoveAllInputBtn   matlab.ui.control.Button
        OutputLabel         matlab.ui.control.Label
        OutputTable         matlab.ui.control.Table
        AddOutputBtn        matlab.ui.control.Button
        RemoveOutputBtn     matlab.ui.control.Button
        RemoveAllOutputBtn  matlab.ui.control.Button
        ReportLabel         matlab.ui.control.Label
        ReportArea          matlab.ui.control.TextArea

        % Right panel - Network
        NetPanel            matlab.ui.container.Panel
        IpField             matlab.ui.control.EditField
        GatewayField        matlab.ui.control.EditField
        SubnetField         matlab.ui.control.EditField
        PortField           matlab.ui.control.NumericEditField
        SocketField         matlab.ui.control.DropDown
        MacField            matlab.ui.control.EditField

        % Right panel - Settings
        SettingsPanel       matlab.ui.container.Panel
        SampleTimeField     matlab.ui.control.NumericEditField
        AbiDropDown         matlab.ui.control.DropDown
        DoubleDropDown      matlab.ui.control.DropDown
        MaxPayloadField     matlab.ui.control.NumericEditField
        SocketTxField       matlab.ui.control.NumericEditField
        SocketRxField       matlab.ui.control.NumericEditField

        % Right panel - Paths
        PathPanel           matlab.ui.container.Panel
        DspPathField        matlab.ui.control.EditField
        DspPathBtn          matlab.ui.control.Button
        PcPathField         matlab.ui.control.EditField
        PcPathBtn           matlab.ui.control.Button

        % Actions
        GenerateBtn         matlab.ui.control.Button
        SaveBtn             matlab.ui.control.Button
        LoadBtn             matlab.ui.control.Button
        PreviewBtn          matlab.ui.control.Button

        % Output
        HashArea            matlab.ui.control.TextArea
        StatusLabel         matlab.ui.control.Label
    end

    methods (Access = public)
        function app = C2837xBlockConfigurator()
            createComponents(app);
            loadDefaultConfig(app);
            updateReport(app);
        end

        function delete(app)
            if isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)

        %% ---- Close callback ----
        function closeApp(~, src)
            delete(src);
        end

        %% ---- Collect config from UI ----
        function config = collectConfig(app)
            config.protocol_version = uint16(1);
            config.abi = app.AbiDropDown.Value;
            config.dsp_ip = strtrim(app.IpField.Value);
            config.gateway = strtrim(app.GatewayField.Value);
            config.subnet = strtrim(app.SubnetField.Value);
            config.tcp_port = round(app.PortField.Value);
            config.socket_num = str2double(app.SocketField.Value);
            config.sample_time_sec = app.SampleTimeField.Value;
            config.max_payload_size_bytes = round(app.MaxPayloadField.Value);
            config.socket0_tx_kb = round(app.SocketTxField.Value);
            config.socket0_rx_kb = round(app.SocketRxField.Value);
            config.double_mode = app.DoubleDropDown.Value;

            % MAC
            mac_str = strrep(strtrim(app.MacField.Value), ':', '');
            mac_bytes = uint8(hex2dec(reshape(mac_str, 2, [])'));
            config.mac = mac_bytes(:)';

            % Inputs
            in_data = app.InputTable.Data;
            config.inputs = struct('name', {}, 'type', {}, 'dim', {});
            for i = 1:size(in_data, 1)
                config.inputs(i).name = strtrim(in_data{i, 1});
                config.inputs(i).type = strtrim(in_data{i, 2});
                config.inputs(i).dim  = round(in_data{i, 3});
            end

            % Outputs
            out_data = app.OutputTable.Data;
            config.outputs = struct('name', {}, 'type', {}, 'dim', {});
            for i = 1:size(out_data, 1)
                config.outputs(i).name = strtrim(out_data{i, 1});
                config.outputs(i).type = strtrim(out_data{i, 2});
                config.outputs(i).dim  = round(out_data{i, 3});
            end

            config.dsp_output_path = strtrim(app.DspPathField.Value);
            config.pc_output_path  = strtrim(app.PcPathField.Value);
        end

        %% ---- Validate config (shared by generate and preview) ----
        function errMsg = validateConfig(~, config)
            errMsg = '';

            % Double type requires double_mode = eabi64
            if strcmp(config.double_mode, 'disabled')
                has_double = any(strcmp({config.inputs.type}, 'double')) || ...
                             any(strcmp({config.outputs.type}, 'double'));
                if has_double
                    errMsg = 'Variable type "double" requires Double Mode = eabi64.';
                    return;
                end
            end

            % Numeric range checks
            if config.tcp_port < 1 || config.tcp_port > 65535 || isnan(config.tcp_port)
                errMsg = 'TCP Port must be 1..65535.';
                return;
            end
            if config.sample_time_sec <= 0 || isnan(config.sample_time_sec)
                errMsg = 'Sample Time must be positive.';
                return;
            end
            if config.max_payload_size_bytes < 1 || config.max_payload_size_bytes > 65535 || isnan(config.max_payload_size_bytes)
                errMsg = 'Max Payload must be 1..65535.';
                return;
            end
            if mod(config.max_payload_size_bytes, 2) ~= 0
                errMsg = 'Max Payload must be even.';
                return;
            end

            % Variable dim checks
            for i = 1:numel(config.inputs)
                d = config.inputs(i).dim;
                if d < 1 || isnan(d) || d ~= floor(d)
                    errMsg = sprintf('Input "%s" dim must be a positive integer.', config.inputs(i).name);
                    return;
                end
            end
            for i = 1:numel(config.outputs)
                d = config.outputs(i).dim;
                if d < 1 || isnan(d) || d ~= floor(d)
                    errMsg = sprintf('Output "%s" dim must be a positive integer.', config.outputs(i).name);
                    return;
                end
            end

            % IP address validation
            [ok, msg] = validate_ip(config.dsp_ip, 'DSP IP');
            if ~ok, errMsg = msg; return; end
            [ok, msg] = validate_ip(config.gateway, 'Gateway');
            if ~ok, errMsg = msg; return; end
            [ok, msg] = validate_ip(config.subnet, 'Subnet');
            if ~ok, errMsg = msg; return; end

            % Payload size validation
            in_data_bytes = 0;
            for i = 1:numel(config.inputs)
                in_data_bytes = in_data_bytes + type_wire_bytes(config.inputs(i).type) * config.inputs(i).dim;
            end
            out_data_bytes = 0;
            for i = 1:numel(config.outputs)
                out_data_bytes = out_data_bytes + type_wire_bytes(config.outputs(i).type) * config.outputs(i).dim;
            end
            in_payload = 4 + in_data_bytes;
            out_payload = 4 + out_data_bytes;

            if in_payload > config.max_payload_size_bytes
                errMsg = sprintf('Input payload (%d bytes) exceeds max payload (%d).', ...
                          in_payload, config.max_payload_size_bytes);
                return;
            end
            if out_payload > config.max_payload_size_bytes
                errMsg = sprintf('Output payload (%d bytes) exceeds max payload (%d).', ...
                          out_payload, config.max_payload_size_bytes);
                return;
            end
            if mod(in_payload, 2) ~= 0
                errMsg = 'Input payload size must be even.';
                return;
            end
            if mod(out_payload, 2) ~= 0
                errMsg = 'Output payload size must be even.';
                return;
            end

            % Output path validation
            errMsg = validate_output_path(config.dsp_output_path, 'DSP Output');
            if ~isempty(errMsg), return; end
            errMsg = validate_output_path(config.pc_output_path, 'PC Output');
            if ~isempty(errMsg), return; end
        end

        %% ---- Load default Phase 1 config ----
        function loadDefaultConfig(app)
            app.IpField.Value       = '192.168.1.100';
            app.GatewayField.Value  = '192.168.1.1';
            app.SubnetField.Value   = '255.255.255.0';
            app.PortField.Value     = 5000;
            app.SocketField.Value   = '0';
            app.MacField.Value      = '00:08:DC:01:02:03';
            app.SampleTimeField.Value = 1e-4;
            app.AbiDropDown.Value   = 'eabi';
            app.DoubleDropDown.Value = 'disabled';
            app.MaxPayloadField.Value = 1024;
            app.SocketTxField.Value = 64;
            app.SocketRxField.Value = 64;
            app.DspPathField.Value  = '';
            app.PcPathField.Value   = '';

            app.InputTable.Data = {
                'a', 'int16', 1;
                'b', 'int16', 1;
                'c', 'int16', 1;
            };
            app.OutputTable.Data = {
                'sum', 'int16', 1;
            };
        end

        %% ---- Update offset report ----
        function updateReport(app)
            config = collectConfig(app);
            L = {};

            % Validate names first
            all_names = {};
            for i = 1:numel(config.inputs)
                all_names{end+1} = config.inputs(i).name; %#ok<AGROW>
            end
            for i = 1:numel(config.outputs)
                all_names{end+1} = config.outputs(i).name; %#ok<AGROW>
            end

            has_error = false;
            checked = {};
            for i = 1:numel(all_names)
                [valid, msg] = c2837x_block_validate_name(all_names{i}, checked);
                if ~valid
                    L{end+1} = sprintf('ERROR: %s', msg); %#ok<AGROW>
                    has_error = true;
                end
                checked{end+1} = all_names{i}; %#ok<AGROW>
            end

            % Build name lists and compute max width
            in_names = cell(1, 1 + numel(config.inputs));
            in_names{1} = 'step_index';
            for i = 1:numel(config.inputs)
                v = config.inputs(i);
                if v.dim == 1
                    in_names{i+1} = sprintf('input.%s', v.name);
                else
                    in_names{i+1} = sprintf('input.%s[%d]', v.name, v.dim);
                end
            end
            max_in = max(cellfun(@length, in_names));

            out_names = cell(1, 1 + numel(config.outputs));
            out_names{1} = 'step_index';
            for i = 1:numel(config.outputs)
                v = config.outputs(i);
                if v.dim == 1
                    out_names{i+1} = sprintf('output.%s', v.name);
                else
                    out_names{i+1} = sprintf('output.%s[%d]', v.name, v.dim);
                end
            end
            max_out = max(cellfun(@length, out_names));

            % INPUT_DATA payload (compact: name | byte range | word range)
            L{end+1} = 'INPUT_DATA payload:';
            L{end+1} = sprintf('  %-*s  %-10s  %s', max_in, 'Name', 'Bytes', 'Words');
            L{end+1} = sprintf('  %s', repmat('-', 1, max_in + 16));
            off_b = 0;
            off_w = 0;
            for idx = 1:numel(in_names)
                nm = in_names{idx};
                if idx == 1
                    sz = 4; ws = 2;
                else
                    v = config.inputs(idx - 1);
                    sz = type_wire_bytes(v.type) * v.dim;
                    ws = sz / 2;
                end
                if sz == 2
                    byte_str = sprintf('%d', off_b);
                else
                    byte_str = sprintf('%d..%d', off_b, off_b + sz - 1);
                end
                if ws == 1
                    word_str = sprintf('%d', off_w);
                else
                    word_str = sprintf('%d..%d', off_w, off_w + ws - 1);
                end
                L{end+1} = sprintf('  %-*s  %-10s  %s', max_in, nm, byte_str, word_str);
                off_b = off_b + sz;
                off_w = off_w + ws;
            end
            in_data_bytes = off_b - 4;
            L{end+1} = sprintf('  %s', repmat('-', 1, max_in + 16));
            L{end+1} = sprintf('  %-*s  %-10d  %d', max_in, 'Total', off_b, off_w);
            L{end+1} = '';

            % OUTPUT_DATA payload
            L{end+1} = 'OUTPUT_DATA payload:';
            L{end+1} = sprintf('  %-*s  %-10s  %s', max_out, 'Name', 'Bytes', 'Words');
            L{end+1} = sprintf('  %s', repmat('-', 1, max_out + 16));
            off_b = 0;
            off_w = 0;
            for idx = 1:numel(out_names)
                nm = out_names{idx};
                if idx == 1
                    sz = 4; ws = 2;
                else
                    v = config.outputs(idx - 1);
                    sz = type_wire_bytes(v.type) * v.dim;
                    ws = sz / 2;
                end
                if sz == 2
                    byte_str = sprintf('%d', off_b);
                else
                    byte_str = sprintf('%d..%d', off_b, off_b + sz - 1);
                end
                if ws == 1
                    word_str = sprintf('%d', off_w);
                else
                    word_str = sprintf('%d..%d', off_w, off_w + ws - 1);
                end
                L{end+1} = sprintf('  %-*s  %-10s  %s', max_out, nm, byte_str, word_str);
                off_b = off_b + sz;
                off_w = off_w + ws;
            end
            out_data_bytes = off_b - 4;
            L{end+1} = sprintf('  %s', repmat('-', 1, max_out + 16));
            L{end+1} = sprintf('  %-*s  %-10d  %d', max_out, 'Total', off_b, off_w);
            L{end+1} = '';

            % Size checks
            max_payload = config.max_payload_size_bytes;
            in_payload = 4 + in_data_bytes;
            out_payload = 4 + out_data_bytes;
            if in_payload > max_payload
                L{end+1} = sprintf('WARNING: input_payload_size_bytes (%d) > max_payload (%d)', ...
                                   in_payload, max_payload);
                has_error = true;
            end
            if out_payload > max_payload
                L{end+1} = sprintf('WARNING: output_payload_size_bytes (%d) > max_payload (%d)', ...
                                   out_payload, max_payload);
                has_error = true;
            end
            if mod(in_payload, 2) ~= 0
                L{end+1} = 'WARNING: input_payload_size_bytes is odd';
                has_error = true;
            end
            if mod(out_payload, 2) ~= 0
                L{end+1} = 'WARNING: output_payload_size_bytes is odd';
                has_error = true;
            end
            if mod(max_payload, 2) ~= 0
                L{end+1} = 'WARNING: max_payload_size_bytes is odd';
                has_error = true;
            end
            if max_payload > 65535
                L{end+1} = 'WARNING: max_payload_size_bytes > 65535';
                has_error = true;
            end

            app.ReportArea.Value = L;

            if has_error
                app.StatusLabel.Text = 'Status: Validation errors found';
                app.StatusLabel.FontColor = [1 0 0];
            else
                app.StatusLabel.Text = 'Status: Ready';
                app.StatusLabel.FontColor = [0 0.5 0];
            end
        end

        %% ---- Generate button callback ----
        function generateButtonPushed(app, ~, ~)
            config = collectConfig(app);

            % Validate
            all_names = {};
            for i = 1:numel(config.inputs)
                all_names{end+1} = config.inputs(i).name; %#ok<AGROW>
            end
            for i = 1:numel(config.outputs)
                all_names{end+1} = config.outputs(i).name; %#ok<AGROW>
            end
            checked = {};
            for i = 1:numel(all_names)
                [valid, msg] = c2837x_block_validate_name(all_names{i}, checked);
                if ~valid
                    uialert(app.UIFigure, msg, 'Validation Error');
                    return;
                end
                checked{end+1} = all_names{i}; %#ok<AGROW>
            end

            % Validate configuration
            errMsg = validateConfig(app, config);
            if ~isempty(errMsg)
                uialert(app.UIFigure, errMsg, 'Config Error');
                return;
            end

            % Double check: eabi64 requires eabi ABI
            if strcmp(config.double_mode, 'eabi64') && ~strcmp(config.abi, 'eabi')
                uialert(app.UIFigure, 'Double eabi64 requires EABI.', 'Config Error');
                return;
            end

            try
                generate_dsp = ~isempty(strtrim(config.dsp_output_path));
                generate_pc  = ~isempty(strtrim(config.pc_output_path));

                if generate_dsp
                    dsp_path = resolve_output_path(config.dsp_output_path);
                end
                if generate_pc
                    pc_path = resolve_output_path(config.pc_output_path);
                end

                % Check if files already exist
                existing = {};
                if generate_dsp
                    dsp_inc_files = {'c2837x_block_algorithm.h', 'c2837x_block_config.h', ...
                                     'c2837x_block.h', 'c2837x_block_protocol.h', ...
                                     'c2837x_w5300_regs.h', 'c2837x_w5300_hal.h', ...
                                     'c2837x_w5300_socket.h'};
                    dsp_src_files = {'c2837x_block_config.c', 'c2837x_block_global_variable.c', ...
                                     'c2837x_block.c', 'c2837x_block_protocol.c', ...
                                     'c2837x_w5300_hal.c', 'c2837x_w5300_socket.c'};
                    for i = 1:numel(dsp_inc_files)
                        p = fullfile(dsp_path, 'inc', dsp_inc_files{i});
                        if isfile(p), existing{end+1} = p; end %#ok<AGROW>
                    end
                    for i = 1:numel(dsp_src_files)
                        p = fullfile(dsp_path, 'src', dsp_src_files{i});
                        if isfile(p), existing{end+1} = p; end %#ok<AGROW>
                    end
                end
                if generate_pc
                    pc_files = {'c2837x_block_pc_config.h', 'c2837x_block_sfun_io.c', ...
                                'c2837x_block_sfun.c', 'c2837x_block_sfun.h', ...
                                'c2837x_block_pc_socket.c', 'c2837x_block_pc_socket.h', ...
                                'c2837x_block_protocol.c', 'c2837x_block_protocol.h', ...
                                'build_c2837x_block_sfun.m'};
                    for i = 1:numel(pc_files)
                        p = fullfile(pc_path, pc_files{i});
                        if isfile(p), existing{end+1} = p; end %#ok<AGROW>
                    end
                end

                if ~isempty(existing)
                    % Separate DSP and PC files
                    dsp_existing = {};
                    pc_existing = {};
                    for i = 1:numel(existing)
                        [~, name, ext] = fileparts(existing{i});
                        fname = [name ext];
                        if generate_dsp && contains(existing{i}, dsp_path)
                            dsp_existing{end+1} = fname; %#ok<AGROW>
                        else
                            pc_existing{end+1} = fname; %#ok<AGROW>
                        end
                    end

                    % Build message with file names
                    msg = 'Files already exist:\n';
                    if ~isempty(dsp_existing)
                        msg = sprintf('%s\nDSP (%s):', msg, dsp_path);
                        for i = 1:numel(dsp_existing)
                            msg = sprintf('%s\n  - %s', msg, dsp_existing{i});
                        end
                    end
                    if ~isempty(pc_existing)
                        msg = sprintf('%s\n\nPC (%s):', msg, pc_path);
                        for i = 1:numel(pc_existing)
                            msg = sprintf('%s\n  - %s', msg, pc_existing{i});
                        end
                    end
                    msg = sprintf('%s\n\nReplace all?', msg);

                    choice = uiconfirm(app.UIFigure, msg, 'Confirm Replace', ...
                        'Options', {'Replace', 'Cancel'}, 'DefaultOption', 'Cancel');
                    if strcmp(choice, 'Cancel')
                        app.StatusLabel.Text = 'Status: Cancelled';
                        return;
                    end
                end

                app.StatusLabel.Text = 'Status: Generating...';
                app.StatusLabel.FontColor = [0 0 0];
                pause(0.01);  % Allow UI to update (avoid drawnow deadlock in App Designer)

                % Generate files
                status_parts = {};
                if generate_dsp
                    c2837x_block_generate_dsp_files(config, dsp_path);
                    status_parts{end+1} = 'DSP OK';
                else
                    status_parts{end+1} = 'DSP skipped';
                end
                if generate_pc
                    c2837x_block_generate_pc_files(config, pc_path);
                    status_parts{end+1} = 'PC OK';
                else
                    status_parts{end+1} = 'PC skipped';
                end

                [hash_str, hash_val] = c2837x_block_build_hash_string(config);
                app.HashArea.Value = strsplit(hash_str, '\n');
                app.StatusLabel.Text = sprintf('Status: %s. config_hash = 0x%08X', ...
                                               strjoin(status_parts, ', '), hash_val);
                app.StatusLabel.FontColor = [0 0.5 0];
            catch e
                uialert(app.UIFigure, e.message, 'Generation Error');
                app.StatusLabel.Text = 'Status: Error';
                app.StatusLabel.FontColor = [1 0 0];
            end
        end

        %% ---- Save button callback ----
        function saveButtonPushed(app, ~, ~)
            [file, path] = uiputfile('*.mat', 'Save Configuration', 'c2837x_block_config.mat');
            if isequal(file, 0), return; end
            filepath = fullfile(path, file);
            if isfile(filepath)
                choice = uiconfirm(app.UIFigure, ...
                    sprintf('File already exists:\n%s\n\nReplace?', filepath), ...
                    'Confirm Replace', ...
                    'Options', {'Replace', 'Cancel'}, 'DefaultOption', 'Cancel');
                if strcmp(choice, 'Cancel')
                    return;
                end
            end
            config = collectConfig(app); %#ok<NASGU>
            save(filepath, 'config');
            app.StatusLabel.Text = sprintf('Status: Saved to %s', file);
            app.StatusLabel.FontColor = [0 0.5 0];
        end

        %% ---- Load button callback ----
        function loadButtonPushed(app, ~, ~)
            [file, path] = uigetfile('*.mat', 'Load Configuration');
            if isequal(file, 0), return; end
            data = load(fullfile(path, file));
            if ~isfield(data, 'config')
                uialert(app.UIFigure, 'No config variable in file.', 'Load Error');
                return;
            end
            config = data.config;
            applyConfig(app, config);
            updateReport(app);
            app.StatusLabel.Text = sprintf('Status: Loaded from %s', file);
            app.StatusLabel.FontColor = [0 0.5 0];
        end

        %% ---- Preview hash button callback ----
        function previewButtonPushed(app, ~, ~)
            config = collectConfig(app);

            % Validate before computing hash
            errMsg = validateConfig(app, config);
            if ~isempty(errMsg)
                uialert(app.UIFigure, errMsg, 'Validation Error');
                return;
            end

            [hash_str, hash_val] = c2837x_block_build_hash_string(config);
            app.HashArea.Value = strsplit(hash_str, '\n');
            app.StatusLabel.Text = sprintf('Status: config_hash = 0x%08X', hash_val);
            app.StatusLabel.FontColor = [0 0.5 0];
        end

        %% ---- Apply loaded config to UI ----
        function applyConfig(app, config)
            if isfield(config, 'dsp_ip'),       app.IpField.Value = config.dsp_ip; end
            if isfield(config, 'gateway'),       app.GatewayField.Value = config.gateway; end
            if isfield(config, 'subnet'),        app.SubnetField.Value = config.subnet; end
            if isfield(config, 'tcp_port'),      app.PortField.Value = config.tcp_port; end
            if isfield(config, 'socket_num'),    app.SocketField.Value = num2str(config.socket_num); end
            if isfield(config, 'sample_time_sec'), app.SampleTimeField.Value = config.sample_time_sec; end
            if isfield(config, 'abi'),           app.AbiDropDown.Value = config.abi; end
            if isfield(config, 'double_mode'),   app.DoubleDropDown.Value = config.double_mode; end
            if isfield(config, 'max_payload_size_bytes'), app.MaxPayloadField.Value = config.max_payload_size_bytes; end
            if isfield(config, 'socket0_tx_kb'), app.SocketTxField.Value = config.socket0_tx_kb; end
            if isfield(config, 'socket0_rx_kb'), app.SocketRxField.Value = config.socket0_rx_kb; end
            if isfield(config, 'dsp_output_path'), app.DspPathField.Value = config.dsp_output_path; end
            if isfield(config, 'pc_output_path'),  app.PcPathField.Value = config.pc_output_path; end

            if isfield(config, 'mac')
                app.MacField.Value = sprintf('%02X:%02X:%02X:%02X:%02X:%02X', ...
                    config.mac(1), config.mac(2), config.mac(3), ...
                    config.mac(4), config.mac(5), config.mac(6));
            end

            if isfield(config, 'inputs')
                n = numel(config.inputs);
                data = cell(n, 3);
                for i = 1:n
                    data{i,1} = config.inputs(i).name;
                    data{i,2} = config.inputs(i).type;
                    data{i,3} = config.inputs(i).dim;
                end
                app.InputTable.Data = data;
            end

            if isfield(config, 'outputs')
                n = numel(config.outputs);
                data = cell(n, 3);
                for i = 1:n
                    data{i,1} = config.outputs(i).name;
                    data{i,2} = config.outputs(i).type;
                    data{i,3} = config.outputs(i).dim;
                end
                app.OutputTable.Data = data;
            end
        end

        %% ---- Add/Remove input ----
        function addInputPushed(app, ~, ~)
            data = app.InputTable.Data;
            data{end+1, 1} = 'new_var';
            data{end,   2} = 'int16';
            data{end,   3} = 1;
            app.InputTable.Data = data;
            updateReport(app);
        end

        function removeInputPushed(app, ~, ~)
            sel = app.InputTable.Selection;
            if isempty(sel), return; end
            data = app.InputTable.Data;
            if size(data, 1) <= 1, return; end
            data(sel(1), :) = [];
            app.InputTable.Data = data;
            updateReport(app);
        end

        function removeAllInputPushed(app, ~, ~)
            app.InputTable.Data = cell(0, 3);
            updateReport(app);
        end

        %% ---- Add/Remove output ----
        function addOutputPushed(app, ~, ~)
            data = app.OutputTable.Data;
            data{end+1, 1} = 'new_var';
            data{end,   2} = 'int16';
            data{end,   3} = 1;
            app.OutputTable.Data = data;
            updateReport(app);
        end

        function removeOutputPushed(app, ~, ~)
            sel = app.OutputTable.Selection;
            if isempty(sel), return; end
            data = app.OutputTable.Data;
            if size(data, 1) <= 1, return; end
            data(sel(1), :) = [];
            app.OutputTable.Data = data;
            updateReport(app);
        end

        function removeAllOutputPushed(app, ~, ~)
            app.OutputTable.Data = cell(0, 3);
            updateReport(app);
        end

        %% ---- Browse paths ----
        function browseDspPath(app, ~, ~)
            d = uigetdir(app.DspPathField.Value, 'Select DSP Output Directory');
            if isequal(d, 0), return; end
            app.DspPathField.Value = d;
        end

        function browsePcPath(app, ~, ~)
            d = uigetdir(app.PcPathField.Value, 'Select PC Output Directory');
            if isequal(d, 0), return; end
            app.PcPathField.Value = d;
        end

        %% ---- Table edit callback ----
        function tableEdited(app, ~, ~)
            updateReport(app);
        end

        %% ---- Build UI ----
        function createComponents(app)
            app.UIFigure = uifigure('Name', 'C2837xBlock Configurator', ...
                'Position', [100 100 980 720], ...
                'CloseRequestFcn', @(src,~) closeApp(app, src));

            main = uigridlayout(app.UIFigure, [2 2]);
            main.ColumnWidth = {'2x', '3x'};
            main.RowHeight = {'1x', 22};
            main.Padding = [6 6 6 6];
            main.ColumnSpacing = 6;
            main.RowSpacing = 6;
            app.MainGrid = main;

            % ============ LEFT PANEL ============
            left = uigridlayout(main, [8 3]);
            left.Layout.Row = 1;
            left.Layout.Column = 1;
            left.RowHeight = {20, '1x', 20, 20, '1x', 20, 20, '1x'};
            left.ColumnWidth = {'1x', '1x', '1x'};

            % Input label
            app.InputLabel = uilabel(left, 'Text', 'Input Variables', 'FontWeight', 'bold');
            app.InputLabel.Layout.Row = 1;
            app.InputLabel.Layout.Column = [1 3];

            % Input table
            app.InputTable = uitable(left, ...
                'ColumnName', {'Name', 'Type', 'Dim'}, ...
                'ColumnFormat', {'char', {'int16','uint16','int32','uint32','single','double'}, 'numeric'}, ...
                'ColumnEditable', [true true true], ...
                'Data', {'a','int16',1; 'b','int16',1; 'c','int16',1});
            app.InputTable.Layout.Row = 2;
            app.InputTable.Layout.Column = [1 3];
            app.InputTable.CellEditCallback = @(~,~) tableEdited(app);

            % Add/Remove/RemoveAll input buttons
            app.AddInputBtn = uibutton(left, 'Text', 'Add', ...
                'ButtonPushedFcn', @(s,e) addInputPushed(app,s,e));
            app.AddInputBtn.Layout.Row = 3;
            app.AddInputBtn.Layout.Column = 1;

            app.RemoveInputBtn = uibutton(left, 'Text', 'Remove', ...
                'ButtonPushedFcn', @(s,e) removeInputPushed(app,s,e));
            app.RemoveInputBtn.Layout.Row = 3;
            app.RemoveInputBtn.Layout.Column = 2;

            app.RemoveAllInputBtn = uibutton(left, 'Text', 'Remove All', ...
                'ButtonPushedFcn', @(s,e) removeAllInputPushed(app,s,e));
            app.RemoveAllInputBtn.Layout.Row = 3;
            app.RemoveAllInputBtn.Layout.Column = 3;

            % Output label
            app.OutputLabel = uilabel(left, 'Text', 'Output Variables', 'FontWeight', 'bold');
            app.OutputLabel.Layout.Row = 4;
            app.OutputLabel.Layout.Column = [1 3];

            % Output table
            app.OutputTable = uitable(left, ...
                'ColumnName', {'Name', 'Type', 'Dim'}, ...
                'ColumnFormat', {'char', {'int16','uint16','int32','uint32','single','double'}, 'numeric'}, ...
                'ColumnEditable', [true true true], ...
                'Data', {'sum','int16',1});
            app.OutputTable.Layout.Row = 5;
            app.OutputTable.Layout.Column = [1 3];
            app.OutputTable.CellEditCallback = @(~,~) tableEdited(app);

            % Add/Remove/RemoveAll output buttons
            app.AddOutputBtn = uibutton(left, 'Text', 'Add', ...
                'ButtonPushedFcn', @(s,e) addOutputPushed(app,s,e));
            app.AddOutputBtn.Layout.Row = 6;
            app.AddOutputBtn.Layout.Column = 1;

            app.RemoveOutputBtn = uibutton(left, 'Text', 'Remove', ...
                'ButtonPushedFcn', @(s,e) removeOutputPushed(app,s,e));
            app.RemoveOutputBtn.Layout.Row = 6;
            app.RemoveOutputBtn.Layout.Column = 2;

            app.RemoveAllOutputBtn = uibutton(left, 'Text', 'Remove All', ...
                'ButtonPushedFcn', @(s,e) removeAllOutputPushed(app,s,e));
            app.RemoveAllOutputBtn.Layout.Row = 6;
            app.RemoveAllOutputBtn.Layout.Column = 3;

            % Report label
            app.ReportLabel = uilabel(left, 'Text', 'Offset Report', 'FontWeight', 'bold');
            app.ReportLabel.Layout.Row = 7;
            app.ReportLabel.Layout.Column = [1 3];

            % Report area
            app.ReportArea = uitextarea(left, 'Editable', 'off', 'FontName', 'Consolas');
            app.ReportArea.Layout.Row = 8;
            app.ReportArea.Layout.Column = [1 3];

            % ============ RIGHT PANEL ============
            right = uigridlayout(main, [5 1]);
            right.Layout.Row = 1;
            right.Layout.Column = 2;
            right.RowHeight = {40, 190, 190, 90, '1x'};
            right.RowSpacing = 4;

            % Action buttons
            btn_grid = uigridlayout(right, [1 4]);
            btn_grid.RowHeight = {'1x'};
            btn_grid.ColumnWidth = {'1x','1x','1x','1x'};
            btn_grid.Layout.Row = 1;
            btn_grid.RowSpacing = 1;
            % btn_grid.

            app.GenerateBtn = uibutton(btn_grid, 'Text', 'Generate', ...
                'BackgroundColor', [0.3 0.7 0.3], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(s,e) generateButtonPushed(app,s,e));
            app.SaveBtn = uibutton(btn_grid, 'Text', 'Save Config', ...
                'ButtonPushedFcn', @(s,e) saveButtonPushed(app,s,e));
            app.LoadBtn = uibutton(btn_grid, 'Text', 'Load Config', ...
                'ButtonPushedFcn', @(s,e) loadButtonPushed(app,s,e));
            app.PreviewBtn = uibutton(btn_grid, 'Text', 'Preview Hash', ...
                'ButtonPushedFcn', @(s,e) previewButtonPushed(app,s,e));

            % Network panel
            app.NetPanel = uipanel(right, 'Title', 'Network Configuration');
            app.NetPanel.Layout.Row = 2;
            net_grid = uigridlayout(app.NetPanel, [6 2], "ColumnSpacing", 1);
            net_grid.RowHeight = repmat({24}, 1, 6);
            net_grid.ColumnWidth = {'1x', '2x'};
            net_grid.Padding = [4 4 4 4];
            net_grid.RowSpacing = 4;

            uilabel(net_grid, 'Text', 'IP Address:', 'HorizontalAlignment', 'left');
            app.IpField = uieditfield(net_grid, 'text');
            uilabel(net_grid, 'Text', 'Gateway:', 'HorizontalAlignment', 'left');
            app.GatewayField = uieditfield(net_grid, 'text');
            uilabel(net_grid, 'Text', 'Subnet Mask:', 'HorizontalAlignment', 'left');
            app.SubnetField = uieditfield(net_grid, 'text');
            uilabel(net_grid, 'Text', 'TCP Port:', 'HorizontalAlignment', 'left');
            app.PortField = uieditfield(net_grid, 'numeric');
            app.PortField.HorizontalAlignment = 'left';
            uilabel(net_grid, 'Text', 'Socket #:', 'HorizontalAlignment', 'left');
            app.SocketField = uidropdown(net_grid, 'Items', ...
                {'0', '1', '2', '3', '4', '5', '6', '7'});
            uilabel(net_grid, 'Text', 'MAC Address:', 'HorizontalAlignment', 'left');
            app.MacField = uieditfield(net_grid, 'text');
            app.MacField.Editable = 'off';

            % Settings panel
            app.SettingsPanel = uipanel(right, 'Title', 'Settings');
            app.SettingsPanel.Layout.Row = 3;
            set_grid = uigridlayout(app.SettingsPanel, [6 2], "ColumnSpacing", 1);
            set_grid.RowHeight = repmat({24}, 1, 6);
            set_grid.ColumnWidth = {'1x', '2x'};
            set_grid.Padding = [4 4 4 4];
            set_grid.RowSpacing = 4;

            uilabel(set_grid, 'Text', 'Sample Time (s):');
            app.SampleTimeField = uieditfield(set_grid, 'numeric', 'HorizontalAlignment', 'left');
            uilabel(set_grid, 'Text', 'Target ABI:');
            app.AbiDropDown = uidropdown(set_grid, 'Items', {'eabi', 'coff'});
            uilabel(set_grid, 'Text', 'Double Mode:');
            app.DoubleDropDown = uidropdown(set_grid, 'Items', {'disabled', 'eabi64'});
            uilabel(set_grid, 'Text', 'Max Payload (B):');
            app.MaxPayloadField = uieditfield(set_grid, 'numeric', 'HorizontalAlignment', 'left');
            uilabel(set_grid, 'Text', 'Socket TX (KB):');
            app.SocketTxField = uieditfield(set_grid, 'numeric', 'HorizontalAlignment', 'left');
            app.SocketTxField.Editable = "off";
            uilabel(set_grid, 'Text', 'Socket RX (KB):');
            app.SocketRxField = uieditfield(set_grid, 'numeric', 'HorizontalAlignment', 'left');
            app.SocketRxField.Editable = "off";

            % Paths panel
            app.PathPanel = uipanel(right, 'Title', 'Output Paths');
            app.PathPanel.Layout.Row = 4;
            path_grid = uigridlayout(app.PathPanel, [2 3]);
            path_grid.RowHeight = repmat({26}, 1, 2);
            path_grid.ColumnWidth = {60, '1x', 80};
            path_grid.Padding = [4 4 4 4];

            % Row 1: DSP
            uilabel(path_grid, 'Text', 'DSP:', 'HorizontalAlignment', 'right');
            app.DspPathField = uieditfield(path_grid, 'text');
            app.DspPathBtn = uibutton(path_grid, 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(s,e) browseDspPath(app,s,e));

            % Row 2: Simulink
            uilabel(path_grid, 'Text', 'Simulink:', 'HorizontalAlignment', 'right');
            app.PcPathField = uieditfield(path_grid, 'text');
            app.PcPathBtn = uibutton(path_grid, 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(s,e) browsePcPath(app,s,e));

            % Hash preview (no label)
            app.HashArea = uitextarea(right, 'Editable', 'off', 'FontName', 'Consolas');
            app.HashArea.Layout.Row = 5;

            % ============ STATUS BAR (bottom, spans both columns) ============
            app.StatusLabel = uilabel(main, 'Text', 'Status: Ready', ...
                'FontColor', [0 0.5 0]);
            app.StatusLabel.Layout.Row = 2;
            app.StatusLabel.Layout.Column = [1 2];
        end
    end
end

%% ---- Local helpers ----
function [ok, msg] = validate_ip(ip_str, field_name)
    ok = true;
    msg = '';
    parts = strsplit(ip_str, '.');
    if numel(parts) ~= 4
        ok = false;
        msg = sprintf('%s: expected 4 octets, got %d.', field_name, numel(parts));
        return;
    end
    nums = str2double(parts);
    if any(isnan(nums))
        ok = false;
        msg = sprintf('%s: each octet must be a number.', field_name);
        return;
    end
    if any(nums < 0 | nums > 255 | nums ~= floor(nums))
        ok = false;
        msg = sprintf('%s: each octet must be 0..255.', field_name);
        return;
    end
end

function p = resolve_output_path(raw)
    if is_absolute_path(raw)
        p = raw;
    else
        p = fullfile(pwd, raw);
    end
end

function tf = is_absolute_path(p)
    tf = (length(p) >= 2 && p(2) == ':') || ...
         (length(p) >= 1 && (p(1) == '/' || p(1) == '\'));
end

function b = type_wire_bytes(t)
    switch t
        case {'int16','uint16'}, b = 2;
        case {'int32','uint32','single'}, b = 4;
        case 'double', b = 8;
    end
end

function errMsg = validate_output_path(raw_path, field_name)
%VALIDATE_OUTPUT_PATH  Validate output path is not inside project folder.
%   Returns empty string if path is empty (skip) or valid.
    errMsg = '';

    % Empty path means skip this side
    if isempty(strtrim(raw_path))
        return;
    end

    % Resolve to absolute path
    if is_absolute_path(raw_path)
        abs_path = raw_path;
    else
        abs_path = fullfile(pwd, raw_path);
    end

    % Normalize path (remove trailing separators, resolve . and ..)
    abs_path = GetFullPath(abs_path);

    % Get project root (where this App file is located)
    app_dir = fileparts(mfilename('fullpath'));
    project_root = fileparts(app_dir);  % Parent of app/ folder
    project_root = GetFullPath(project_root);

    % Check if output path is inside project folder
    % Must check with trailing separator to avoid prefix matching
    % e.g., C2837xBlock_Test should NOT match C2837xBlock
    root_with_sep = [project_root filesep];
    is_inside = strcmpi(abs_path, project_root) || ...
                startsWith(abs_path, root_with_sep, 'IgnoreCase', ispc);
    if is_inside
        errMsg = sprintf('%s path cannot be inside the project folder.\nProject: %s\nOutput:  %s', ...
                  field_name, project_root, abs_path);
        return;
    end
end

function p = GetFullPath(p)
%GETFULLPATH  Get absolute path, resolving . and ..
    try
        javaFile = java.io.File(p);
        p = char(javaFile.getCanonicalPath());
    catch
        % Fallback if Java not available
        if is_absolute_path(p)
            % Simple normalization
            p = strrep(p, '/', filesep);
            p = strrep(p, '\', filesep);
        end
    end
end
