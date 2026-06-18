function c2837x_block_sfun_matlab(block)
% C2837X_BLOCK_SFUN_MATLAB  Level-2 MATLAB S-Function for C2837xBlock DSP communication.
%
% Phase 1: 3x int16 input (a, b, c), 1x int16 output (sum).
% Communicates with DSP via TCP/IP using the V2.3 protocol.
%
% Usage:
%   1. Open the test Simulink model.
%   2. Ensure DSP is running and listening on the configured IP:port.
%   3. Run the simulation.

setup(block);

end

%% ============================================================
function setup(block)
% Register number of ports
block.NumInputPorts  = 3;
block.NumOutputPorts = 1;

% Set port properties
for i = 1:3
    block.InputPort(i).Dimensions  = 1;
    block.InputPort(i).DatatypeID  = 4; % int16
    block.InputPort(i).Complexity  = 'Real';
    block.InputPort(i).DirectFeedThrough = true;
    block.InputPort(i).SamplingMode = 'Sample';
end

block.OutputPort(1).Dimensions = 1;
block.OutputPort(1).DatatypeID = 4; % int16
block.OutputPort(1).Complexity = 'Real';
block.OutputPort(1).SamplingMode = 'Sample';

% Register sample time
block.SampleTimes = [0.0001 0]; % 100 us, fixed-step

% Register methods
block.RegBlockMethod('Start', @Start);
block.RegBlockMethod('Outputs', @Outputs);
block.RegBlockMethod('Terminate', @Terminate);

end

%% ============================================================
function Start(block)
%START  Connect to DSP and perform SIM_START handshake.

    % Network configuration
    dsp_ip   = '192.168.1.100';
    tcp_port = 5000;
    timeout_s = 5.0;

    % Protocol constants
    protocol_version = uint16(1);
    config_hash = uint32(hex2dec('12345678'));

    % Open TCP connection
    try
        sock = tcpclient(dsp_ip, tcp_port, 'ConnectTimeout', timeout_s, ...
                         'Timeout', timeout_s);
    catch e
        error('C2837xBlock: Failed to connect to DSP at %s:%d - %s', ...
              dsp_ip, tcp_port, e.message);
    end

    % Build SIM_START frame
    % type = 0x0001, length = 6
    % payload: protocol_version (uint16) + config_hash (uint32)
    payload = zeros(1, 6, 'uint8');
    payload(1) = uint8(bitand(protocol_version, 255));
    payload(2) = uint8(bitshift(protocol_version, -8));
    payload(3) = uint8(bitand(config_hash, 255));
    payload(4) = uint8(bitand(bitshift(config_hash, -8), 255));
    payload(5) = uint8(bitand(bitshift(config_hash, -16), 255));
    payload(6) = uint8(bitand(bitshift(config_hash, -24), 255));

    frame = zeros(1, 10, 'uint8');
    frame(1) = 1; frame(2) = 0;  % type = 0x0001
    frame(3) = 6; frame(4) = 0;  % length = 6
    frame(5:10) = payload;

    write(sock, frame);

    % Wait for RESPONSE
    resp = read(sock, 6);
    if length(resp) < 6
        error('C2837xBlock: Incomplete RESPONSE from DSP');
    end

    resp_type   = uint16(resp(1)) + uint16(resp(2)) * 256;
    resp_length = uint16(resp(3)) + uint16(resp(4)) * 256;

    if resp_type ~= 5
        error('C2837xBlock: Expected RESPONSE (0x0005), got 0x%04X', resp_type);
    end
    if resp_length ~= 2
        error('C2837xBlock: RESPONSE length should be 2, got %d', resp_length);
    end

    error_code = uint16(resp(5)) + uint16(resp(6)) * 256;
    if error_code ~= 0
        error('C2837xBlock: SIM_START rejected by DSP, error_code=%d', error_code);
    end

    % Store socket in persistent variable (UserData not available in Level-2)
    assignin('base', 'c2837x_block_socket', sock);
    assignin('base', 'c2837x_block_step_index', uint32(0));

    fprintf('C2837xBlock: Connected to DSP, SIM_START successful.\n');

end

%% ============================================================
function Outputs(block)
%OUTPUTS  Send INPUT_DATA and receive OUTPUT_DATA for one simulation step.

    sock = evalin('base', 'c2837x_block_socket');
    step_index = evalin('base', 'c2837x_block_step_index');

    % Read inputs
    a = typecast(block.InputPort(1).Data, 'int16');
    b = typecast(block.InputPort(2).Data, 'int16');
    c = typecast(block.InputPort(3).Data, 'int16');

    % Pack INPUT_DATA payload: step_index (4 bytes) + a (2) + b (2) + c (2)
    payload = zeros(1, 10, 'uint8');

    % step_index (uint32 LE)
    payload(1) = uint8(bitand(step_index, 255));
    payload(2) = uint8(bitand(bitshift(step_index, -8), 255));
    payload(3) = uint8(bitand(bitshift(step_index, -16), 255));
    payload(4) = uint8(bitand(bitshift(step_index, -24), 255));

    % a (int16 LE)
    a_u = typecast(int16(a), 'uint16');
    payload(5) = uint8(bitand(a_u, 255));
    payload(6) = uint8(bitshift(a_u, -8));

    % b (int16 LE)
    b_u = typecast(int16(b), 'uint16');
    payload(7) = uint8(bitand(b_u, 255));
    payload(8) = uint8(bitshift(b_u, -8));

    % c (int16 LE)
    c_u = typecast(int16(c), 'uint16');
    payload(9)  = uint8(bitand(c_u, 255));
    payload(10) = uint8(bitshift(c_u, -8));

    % Build frame: type=0x0002, length=10
    frame = zeros(1, 14, 'uint8');
    frame(1) = 2;  frame(2) = 0;   % type = 0x0002
    frame(3) = 10; frame(4) = 0;   % length = 10
    frame(5:14) = payload;

    write(sock, frame);

    % Wait for OUTPUT_DATA or RESPONSE
    resp_header = read(sock, 4);
    if length(resp_header) < 4
        error('C2837xBlock: Timeout waiting for DSP response at step %d', step_index);
    end

    resp_type   = uint16(resp_header(1)) + uint16(resp_header(2)) * 256;
    resp_length = uint16(resp_header(3)) + uint16(resp_header(4)) * 256;

    if resp_type == 3  % OUTPUT_DATA
        if resp_length ~= 6
            error('C2837xBlock: OUTPUT_DATA length should be 6, got %d', resp_length);
        end

        resp_payload = read(sock, 6);
        if length(resp_payload) < 6
            error('C2837xBlock: Incomplete OUTPUT_DATA payload');
        end

        % Parse returned step_index
        returned_step = uint32(resp_payload(1)) + ...
                        uint32(resp_payload(2)) * 256 + ...
                        uint32(resp_payload(3)) * 65536 + ...
                        uint32(resp_payload(4)) * 16777216;

        if returned_step ~= step_index
            error('C2837xBlock: step_index mismatch, sent %d, got %d', ...
                  step_index, returned_step);
        end

        % Parse sum (int16 LE)
        sum_u = uint16(resp_payload(5)) + bitshift(uint16(resp_payload(6)), 8);
        sum_val = typecast(sum_u, 'int16');

        block.OutputPort(1).Data = sum_val;

    elseif resp_type == 5  % RESPONSE (error)
        if resp_length ~= 2
            error('C2837xBlock: RESPONSE length should be 2, got %d', resp_length);
        end

        resp_payload = read(sock, 2);
        if length(resp_payload) < 2
            error('C2837xBlock: Incomplete RESPONSE payload');
        end

        error_code = uint16(resp_payload(1)) + uint16(resp_payload(2)) * 256;

        if error_code == 0
            error('C2837xBlock: Unexpected RESPONSE(0) during step %d', step_index);
        end

        error('C2837xBlock: DSP error RESPONSE(%d) at step %d', error_code, step_index);

    else
        % Read remaining bytes to flush
        if resp_length > 0
            read(sock, resp_length);
        end
        error('C2837xBlock: Unexpected frame type 0x%04X at step %d', resp_type, step_index);
    end

    % Update step_index
    if step_index == intmax('uint32')
        error('C2837xBlock: step_index overflow at UINT32_MAX');
    end
    assignin('base', 'c2837x_block_step_index', step_index + 1);

end

%% ============================================================
function Terminate(block)
%TERMINATE  Send SIM_STOP and close connection.

    try
        sock = evalin('base', 'c2837x_block_socket');

        % Build SIM_STOP frame: type=0x0004, length=0
        frame = [4 0 0 0]; % type=0x0004, length=0
        write(sock, frame);

        % Brief pause to allow DSP to process
        pause(0.1);

        clear sock;
        fprintf('C2837xBlock: Disconnected from DSP.\n');
    catch
        % Socket may already be closed
    end

    evalin('base', 'clear c2837x_block_socket c2837x_block_step_index;');

end
