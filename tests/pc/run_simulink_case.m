function result = run_simulink_case(instanceFolder, internalName, port, ...
        interfaceHash, transcriptPath, pythonExecutable, keepLoaded, scenario)
%RUN_SIMULINK_CASE Run a two-step Normal-mode generated S-Function case.

if nargin < 7, keepLoaded = false; end
if nargin < 8, scenario = 'success'; end

endpoint = fullfile(fileparts(mfilename('fullpath')), 'sfun_mock_endpoint.py');
readyPath = [transcriptPath '.ready'];
arguments = {endpoint, '--port', sprintf('%u', port), ...
    '--protocol-version', '1', '--interface-hash', ...
    sprintf('0x%08X', interfaceHash), '--input-hex', ...
    ['feff3412dcfeeb32a4f8efcdab8900000080a50000000000f87f' ...
    '000000000000f03f'], '--output-hex', ...
    '0180cdabfeffffff98badcfe0000008001000000a50000000000f87f', ...
    '--scenario', scenario, '--steps', '2', ...
    '--timeout-seconds', '15', '--transcript', transcriptPath, ...
    '--ready-file', readyPath};
process = start_process(pythonExecutable, arguments);
processCleanup = onCleanup(@() stop_process(process));
readyCleanup = onCleanup(@() delete_if_file(readyPath));
deadline = tic;
while ~isfile(readyPath) && toc(deadline) < 5, pause(0.01); end
assert(isfile(readyPath), 'S4-06 mock endpoint did not become ready.');

oldPath = path;
pathCleanup = onCleanup(@() path(oldPath));
addpath(instanceFolder, '-begin');
model = matlab.lang.makeValidName(['s406_' internalName '_' char(java.util.UUID.randomUUID)]);
if ~keepLoaded
    modelCleanup = onCleanup(@() close_model(model));
end
new_system(model);
set_param(model, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
    'FixedStep', '0.0001', 'StopTime', '0.0001', 'SimulationMode', 'normal');
sfun = [model '/Generated S-Function'];
add_block('simulink/User-Defined Functions/S-Function', sfun, ...
    'FunctionName', [internalName '_sfun']);
types = {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'};
values = {'int16([-2 4660])', 'uint16(65244)', 'int32(-123456789)', ...
    'uint32(2309737967)', ...
    'typecast(uint32(hex2dec(''80000000'')),''single'')', ...
    ['typecast(uint8([165 0 0 0 0 0 248 127 ' ...
    '0 0 0 0 0 0 240 63]),''double'')']};
for index = 1:6
    source = [model '/Input ' num2str(index)];
    sink = [model '/Output ' num2str(index)];
    add_block('simulink/Sources/Constant', source, 'Value', values{index}, ...
        'OutDataTypeStr', types{index});
    add_block('simulink/Sinks/To Workspace', sink, ...
        'VariableName', sprintf('s406_output_%u', index), 'SaveFormat', 'Array');
    add_line(model, sprintf('Input %u/1', index), ...
        sprintf('Generated S-Function/%u', index));
    add_line(model, sprintf('Generated S-Function/%u', index), ...
        sprintf('Output %u/1', index));
end

failure = [];
bytes = zeros(1, 0, 'uint8');
if strcmp(scenario, 'success')
    simulation = sim(model, 'ReturnWorkspaceOutputs', 'on');
else
    simulation = sim(model, 'ReturnWorkspaceOutputs', 'on', ...
        'CaptureErrors', 'on');
    assert(~isempty(simulation.ErrorMessage), ...
        'S4-06 error scenario did not fail simulation.');
    failure = MException('C2837xBlock:Test:ExpectedSimulationError', ...
        '%s', simulation.ErrorMessage);
end
for index = 1:6
    portValues = simulation.get(sprintf('s406_output_%u', index));
    assert(~isempty(portValues), 'S4-06 partial outputs were not captured.');
    bytes = [bytes reshape(typecast(portValues(end, :), 'uint8'), 1, [])]; %#ok<AGROW>
end
expected = uint8([1 128 205 171 254 255 255 255 152 186 220 254 ...
    0 0 0 128 1 0 0 0 165 0 0 0 0 0 248 127]);
assert(isequal(bytes, expected), 'S4-06 output bit pattern mismatch.');
assert(process.WaitForExit(5000) && process.ExitCode == 0, ...
    'S4-06 mock endpoint failed.');
transcript = jsondecode(fileread(transcriptPath));
assert(strcmp(transcript.result, 'PASS') && ...
    isequal(reshape(transcript.input_steps, 1, []), [0 1]) && ...
    (transcript.sim_stop_observed == strcmp(scenario, 'success')) && ...
    transcript.extra_reconnect_count == 0, ...
    'S4-06 transcript mismatch.');
result = struct('output_bytes', bytes, 'transcript', transcript, ...
    'model', model, 'failure', failure);
if exist('modelCleanup', 'var'), clear modelCleanup; end
clear pathCleanup readyCleanup processCleanup
end

function process = start_process(executable, arguments)
info = System.Diagnostics.ProcessStartInfo(executable);
quoted = cellfun(@(value) ['"' strrep(value, '"', '\"') '"'], ...
    arguments, 'UniformOutput', false);
info.Arguments = strjoin(quoted, ' ');
info.UseShellExecute = false;
info.CreateNoWindow = true;
process = System.Diagnostics.Process.Start(info);
end

function stop_process(process)
if ~process.HasExited
    process.Kill(true);
    process.WaitForExit();
end
process.Dispose();
end

function close_model(model)
if bdIsLoaded(model), close_system(model, 0); end
end

function delete_if_file(path)
if isfile(path), delete(path); end
end
