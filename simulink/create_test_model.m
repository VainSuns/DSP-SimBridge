% CREATE_TEST_MODEL  Create a Simulink test model for C2837xBlock Phase 1 verification.
%
% The model has:
%   - 3 constant inputs (a, b, c) of type int16
%   - 1 C2837xBlock S-Function block
%   - 1 display output
%   - Fixed-step discrete solver, sample time 100 us
%
% Usage:
%   create_test_model
%   % Then run the simulation (ensure DSP is listening)

function create_test_model()

    model_name = 'c2837x_block_test';

    % Close if already open
    if bdIsLoaded(model_name)
        close_system(model_name, 0);
    end

    % Create new model
    new_system(model_name);
    open_system(model_name);

    % Configure solver: fixed-step, discrete, 100 us
    set_param(model_name, 'SolverType', 'Fixed-step');
    set_param(model_name, 'Solver', 'FixedStepDiscrete');
    set_param(model_name, 'FixedStep', '0.0001');
    set_param(model_name, 'StopTime', '0.1');  % 100 ms = 1000 steps

    % Add constant blocks for inputs
    add_block('simulink/Sources/Constant', [model_name '/a']);
    set_param([model_name '/a'], 'Value', 'int16(100)');
    set_param([model_name '/a'], 'OutDataTypeStr', 'int16');
    set_param([model_name '/a'], 'Position', [100 50 150 80]);

    add_block('simulink/Sources/Constant', [model_name '/b']);
    set_param([model_name '/b'], 'Value', 'int16(200)');
    set_param([model_name '/b'], 'OutDataTypeStr', 'int16');
    set_param([model_name '/b'], 'Position', [100 120 150 150]);

    add_block('simulink/Sources/Constant', [model_name '/c']);
    set_param([model_name '/c'], 'Value', 'int16(300)');
    set_param([model_name '/c'], 'OutDataTypeStr', 'int16');
    set_param([model_name '/c'], 'Position', [100 190 150 220]);

    % Add S-Function block
    add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function', [model_name '/DSP']);
    set_param([model_name '/DSP'], 'FunctionName', 'c2837x_block_sfun_matlab');
    set_param([model_name '/DSP'], 'Position', [250 80 350 180]);

    % Add display block
    add_block('simulink/Sinks/Display', [model_name '/sum_display']);
    set_param([model_name '/sum_display'], 'Position', [450 120 520 150]);

    % Add lines
    add_line(model_name, 'a/1', 'DSP/1');
    add_line(model_name, 'b/1', 'DSP/2');
    add_line(model_name, 'c/1', 'DSP/3');
    add_line(model_name, 'DSP/1', 'sum_display/1');

    % Save model
    save_system(model_name);

    fprintf('Test model "%s" created successfully.\n', model_name);
    fprintf('Expected: a=100, b=200, c=300 -> sum=600\n');
    fprintf('Run the simulation to test DSP communication.\n');

end
