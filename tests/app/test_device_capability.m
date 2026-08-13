classdef test_device_capability < matlab.unittest.TestCase
    properties
        Root
        WorkFolder
        CapabilityPath
    end

    methods (TestClassSetup)
        function addAppFolder(testCase)
            testCase.Root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.CapabilityPath = fullfile(testCase.Root, 'app', ...
                'capabilities', 'TMS320F28377D_PTP.json');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, 'app')));
        end
    end

    methods (TestMethodSetup)
        function makeWorkFolder(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.WorkFolder = fixture.Folder;
        end
    end

    methods (Test)
        function testDefaultCapabilityLoads(testCase)
            result = c2837x_block_load_device_capability();

            testCase.verifyTrue(result.available);
            testCase.verifyEmpty(result.identifier);
            testCase.verifyEmpty(result.message);
            testCase.verifyEqual(result.source_path, ...
                c2837x_block_normalize_absolute_path(testCase.CapabilityPath));
            testCase.verifyEqual(result.capability.schema_version, uint16(1));
            testCase.verifyEqual(result.capability.target, ...
                struct('device', 'TMS320F28377D', 'package', 'PTP'));
        end

        function testUnsupportedSchemaIsRejected(testCase)
            path = fullfile(testCase.WorkFolder, 'unsupported.json');
            text = regexprep(fileread(testCase.CapabilityPath), ...
                '"schema_version"\s*:\s*1', '"schema_version": 99', 'once');
            write_text(path, text);

            result = c2837x_block_load_device_capability(path);

            testCase.verifyFalse(result.available);
            testCase.verifyEqual(result.capability, struct());
            testCase.verifyEqual(result.identifier, ...
                'C2837xBlock:Capability:UnsupportedSchema');
            testCase.verifyNotEmpty(strfind(result.message, '99'));
        end

        function testMissingCapabilityIsUnavailable(testCase)
            path = fullfile(testCase.WorkFolder, 'missing.json');

            result = c2837x_block_load_device_capability(path);

            testCase.verifyFalse(result.available);
            testCase.verifyEqual(result.capability, struct());
            testCase.verifyEqual(result.identifier, ...
                'C2837xBlock:Capability:Unavailable');
            testCase.verifyNotEmpty(strfind(result.message, 'missing.json'));
        end

        function testCorruptJsonIsRejected(testCase)
            path = fullfile(testCase.WorkFolder, 'corrupt.json');
            write_text(path, '{"schema_version": 1, broken');

            result = c2837x_block_load_device_capability(path);

            testCase.verifyFalse(result.available);
            testCase.verifyEqual(result.capability, struct());
            testCase.verifyEqual(result.identifier, ...
                'C2837xBlock:Capability:InvalidJson');
        end

        function testInvalidSchemaIsRejected(testCase)
            path = fullfile(testCase.WorkFolder, 'invalid-schema.json');
            text = regexprep(fileread(testCase.CapabilityPath), ...
                '"package"\s*:\s*"PTP"', '"package": 42', 'once');
            write_text(path, text);

            result = c2837x_block_load_device_capability(path);

            testCase.verifyFalse(result.available);
            testCase.verifyEqual(result.capability, struct());
            testCase.verifyEqual(result.identifier, ...
                'C2837xBlock:Capability:InvalidSchema');
        end

        function testNormalizedStructureIsStable(testCase)
            capability = c2837x_block_load_device_capability().capability;
            module = capability.sci_modules(1);
            endpoint = module.rx_endpoints(1);

            testCase.verifyEqual(fieldnames(capability), ...
                {'schema_version'; 'target'; 'sci_modules'; 'gpios'});
            testCase.verifyEqual(fieldnames(capability.target), ...
                {'device'; 'package'});
            testCase.verifyEqual(fieldnames(module), ...
                {'id'; 'display_name'; 'rx_endpoints'; 'tx_endpoints'});
            testCase.verifyEqual(fieldnames(endpoint), ...
                {'gpio'; 'signal'; 'mux_selection'; ...
                'driverlib_macro'; 'driverlib_value'});
            testCase.verifyEqual(fieldnames(capability.gpios), ...
                {'number'; 'package_pin'});
            testCase.verifyClass(capability.schema_version, 'uint16');
            testCase.verifyClass(endpoint.gpio, 'uint16');
            testCase.verifyClass(endpoint.mux_selection, 'uint8');
            testCase.verifyFalse(isfield(module, 'pin_groups'));
            testCase.verifyFalse(isfield(capability, 'provenance'));
        end

        function testRawCapabilityStoresIndependentEndpoints(testCase)
            text = fileread(testCase.CapabilityPath);

            testCase.verifyEqual(numel(regexp( ...
                text, '"rx_endpoints"\s*:', 'match')), 4);
            testCase.verifyEqual(numel(regexp( ...
                text, '"tx_endpoints"\s*:', 'match')), 4);
            testCase.verifyEmpty(regexp( ...
                text, '"pin_groups"\s*:', 'match'));
        end

        function testCapabilityContainsNoUserOrPlatformConfiguration(testCase)
            text = lower(fileread(testCase.CapabilityPath));
            forbidden = {'baud', 'requested_baud', 'actual_baud', ...
                'pin_type', 'qualification', 'rx_qualification', ...
                'ctrl_polarity', 'selected_sci_module', ...
                'ctrl_gpio', 'com', 'sample_time', ...
                'timeout', 'instances', 'w5300', 'reserved_resources'};

            matches = find_forbidden_keys(text, forbidden);

            testCase.verifyEmpty(matches);
        end

        function testTiEndpointSetsMatchPtpFacts(testCase)
            capability = c2837x_block_load_device_capability().capability;
            [expectedRx, expectedTx] = expected_endpoint_facts();

            actualRx = module_endpoint_facts( ...
                capability.sci_modules, 'rx_endpoints');
            actualTx = module_endpoint_facts( ...
                capability.sci_modules, 'tx_endpoints');

            testCase.verifyEqual({capability.sci_modules.id}, ...
                {'SCI-A', 'SCI-B', 'SCI-C', 'SCI-D'});
            testCase.verifyEqual(actualRx, expectedRx);
            testCase.verifyEqual(actualTx, expectedTx);
        end

        function testIndependentEndpointCountAndPtpFiltering(testCase)
            capability = c2837x_block_load_device_capability().capability;
            expectedGpios = uint16([0:94 99 133]);

            endpointCounts = module_endpoint_counts(capability.sci_modules);
            endpointGpios = all_endpoint_gpios(capability.sci_modules);

            testCase.verifyEqual(endpointCounts, [14 15 12 6]);
            testCase.verifyEqual(sum(endpointCounts), 47);
            testCase.verifyEqual([capability.gpios.number], expectedGpios);
            testCase.verifyTrue(all(ismember(endpointGpios, expectedGpios)));
            testCase.verifyFalse(any(ismember(uint16(135:142), endpointGpios)));
        end

        function testEndpointDescriptorsAreDeterministicAndComplete(testCase)
            capability = c2837x_block_load_device_capability().capability;
            descriptors = endpoint_descriptors(capability.sci_modules);

            testCase.verifyTrue(all([descriptors.sorted]));
            testCase.verifyTrue(all([descriptors.signal_matches]));
            testCase.verifyTrue(all([descriptors.macro_matches]));
            testCase.verifyTrue(all([descriptors.value_matches]));
        end

        function testIndependentNonAdjacentEndpointsExistWithoutPairModel(testCase)
            capability = c2837x_block_load_device_capability().capability;
            module = capability.sci_modules(2);

            testCase.verifyTrue(ismember(uint16(19), ...
                [module.rx_endpoints.gpio]));
            testCase.verifyTrue(ismember(uint16(14), ...
                [module.tx_endpoints.gpio]));
            testCase.verifyFalse(isfield(module, 'pin_groups'));
        end

        function testTiProvenanceIsRepositoryVisible(testCase)
            text = fileread(testCase.CapabilityPath);

            testCase.verifyNotEmpty(strfind(text, ...
                'TMS320F2837xD Dual-Core Real-Time Microcontrollers'));
            testCase.verifyNotEmpty(strfind(text, 'SPRS880P'));
            testCase.verifyNotEmpty(strfind(text, ...
                'Table 5-1 Signal Descriptions'));
            testCase.verifyNotEmpty(strfind(text, ...
                'Table 5-3 GPIO Muxed Pins'));
            testCase.verifyNotEmpty(strfind(text, 'C2000Ware'));
            testCase.verifyNotEmpty(strfind(text, '26.01.00.00'));
            testCase.verifyNotEmpty(strfind(text, ...
                'driverlib/f2837xd/driverlib/pin_map.h'));
        end

        function testW5300PreviewAndGenerateIgnoreUnavailableCapability(testCase)
            install_throwing_loader(testCase, testCase.WorkFolder);
            project = isolation_project(testCase.WorkFolder);

            [candidates, dependencies, providerIssues] = ...
                c2837x_block_build_dsp_candidates(project);
            [snapshot, previewIssues] = c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);
            [result, commitIssues] = c2837x_block_commit_preview_snapshot( ...
                snapshot, project, candidates, dependencies);

            testCase.verifyFalse(has_errors(providerIssues));
            testCase.verifyFalse(has_errors(previewIssues));
            testCase.verifyFalse(has_errors(commitIssues));
            testCase.verifyEqual(result.status, 'completed');
            testCase.verifyTrue(isfolder(project.output.dsp_root));
        end
    end
end

function matches = find_forbidden_keys(text, forbidden)
matches = {};
for index = 1:numel(forbidden)
    pattern = ['"' regexptranslate('escape', forbidden{index}) '"\s*:'];
    if ~isempty(regexp(text, pattern, 'once'))
        matches{end + 1} = forbidden{index}; %#ok<AGROW>
    end
end
end

function [rxFacts, txFacts] = expected_endpoint_facts()
rxFacts = { ...
    [9 6; 28 1; 35 1; 43 15; 49 6; 64 6; 85 5], ...
    [11 2; 15 2; 19 2; 23 3; 55 6; 71 6; 87 5], ...
    [13 6; 39 5; 57 6; 62 1; 73 6; 90 6], ...
    [46 6; 77 6; 94 6]};
txFacts = { ...
    [8 6; 29 1; 36 1; 42 15; 48 6; 65 6; 84 5], ...
    [9 2; 10 6; 14 2; 18 2; 22 3; 54 6; 70 6; 86 5], ...
    [12 6; 38 5; 56 6; 63 1; 72 6; 89 6], ...
    [47 6; 76 6; 93 6]};
end

function facts = module_endpoint_facts(modules, field)
facts = cell(1, numel(modules));
for moduleIndex = 1:numel(modules)
    endpoints = modules(moduleIndex).(field);
    facts{moduleIndex} = zeros(numel(endpoints), 2);
    for endpointIndex = 1:numel(endpoints)
        facts{moduleIndex}(endpointIndex, :) = double([ ...
            endpoints(endpointIndex).gpio ...
            endpoints(endpointIndex).mux_selection]);
    end
end
end

function counts = module_endpoint_counts(modules)
counts = zeros(1, numel(modules));
for moduleIndex = 1:numel(modules)
    counts(moduleIndex) = numel(modules(moduleIndex).rx_endpoints) + ...
        numel(modules(moduleIndex).tx_endpoints);
end
end

function gpios = all_endpoint_gpios(modules)
gpios = uint16([]);
for moduleIndex = 1:numel(modules)
    gpios = [gpios [modules(moduleIndex).rx_endpoints.gpio] ...
        [modules(moduleIndex).tx_endpoints.gpio]]; %#ok<AGROW>
end
end

function descriptors = endpoint_descriptors(modules)
prototype = struct('sorted', false, 'signal_matches', false, ...
    'macro_matches', false, 'value_matches', false);
descriptors = repmat(prototype, 1, 0);
for moduleIndex = 1:numel(modules)
    for direction = {'rx_endpoints', 'tx_endpoints'}
        endpoints = modules(moduleIndex).(direction{1});
        letter = modules(moduleIndex).id(end);
        directionLetter = upper(direction{1}(1));
        signal = sprintf('SCI%sXD%s', directionLetter, letter);
        for endpointIndex = 1:numel(endpoints)
            endpoint = endpoints(endpointIndex);
            descriptor = prototype;
            descriptor.sorted = issorted([endpoints.gpio]);
            descriptor.signal_matches = strcmp(endpoint.signal, signal);
            descriptor.macro_matches = strcmp(endpoint.driverlib_macro, ...
                sprintf('GPIO_%u_%s', endpoint.gpio, signal));
            descriptor.value_matches = hex2dec( ...
                endpoint.driverlib_value(3:10)) == expected_driverlib_value( ...
                endpoint.gpio, endpoint.mux_selection);
            descriptors(end + 1) = descriptor; %#ok<AGROW>
        end
    end
end
end

function value = expected_driverlib_value(gpio, muxSelection)
bank = floor(double(gpio) / 32);
half = floor(mod(double(gpio), 32) / 16);
muxOffset = hex2dec('0006') + bank * hex2dec('0040') + half * 2;
shift = mod(double(gpio), 16) * 2;
value = muxOffset * 2^16 + shift * 2^8 + double(muxSelection);
end

function install_throwing_loader(testCase, folder)
path = fullfile(folder, 'c2837x_block_load_device_capability.m');
write_text(path, sprintf([ ...
    'function result = c2837x_block_load_device_capability(varargin)\n' ...
    'error(''Test:CapabilityMustBeOnDemand'', ' ...
    '''W5300-only path requested SCI capability.'');\n' ...
    'result = []; %%#ok<UNRCH>\n' ...
    'end\n']));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
clear c2837x_block_load_device_capability
testCase.addTeardown(@restore_loader);
rehash;
end

function restore_loader()
clear c2837x_block_load_device_capability
rehash;
end

function project = isolation_project(root)
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
instance.display_name = 'W5300 Only';
instance.internal_name = 'w5300_only';
instance.inputs = struct('name', 'command', 'type', 'int16', 'dim', 1);
instance.outputs = struct('name', 'status', 'type', 'uint16', 'dim', 1);
project.instances = instance;
end

function valid = has_errors(issues)
valid = ~isempty(issues) && any(strcmp({issues.severity}, 'Error'));
end

function write_text(path, text)
fileID = fopen(path, 'w');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fprintf(fileID, '%s', text);
clear cleanup
end
