classdef test_sci_baud_calculation < matlab.unittest.TestCase
    properties (TestParameter)
        supportedBaud = struct( ...
            'baud9600', 9600, ...
            'baud19200', 19200, ...
            'baud38400', 38400, ...
            'baud57600', 57600, ...
            'baud115200', 115200)
        invalidValue = struct( ...
            'zero', 0, ...
            'negative', -1, ...
            'nan', NaN, ...
            'inf', Inf, ...
            'nonScalar', [1 2], ...
            'nonnumeric', 'invalid')
    end

    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testBringUpClockConfig(testCase)
            config = c2837x_block_get_sci_clock_config();

            testCase.verifyEqual(config.sysclk_hz, 200e6, AbsTol=eps(200e6));
            testCase.verifyEqual(config.lspclk_divisor, 14, AbsTol=eps(14));
            testCase.verifyEqual(config.lspclk_hz, ...
                config.sysclk_hz / config.lspclk_divisor, ...
                AbsTol=eps(config.lspclk_hz));
        end

        function testSupportedBaudIsOptimalAndDeterministic( ...
                testCase, supportedBaud)
            config = c2837x_block_get_sci_clock_config();
            expected = reference_result(config.lspclk_hz, supportedBaud);

            testCase.verifyWarningFree(@() ...
                c2837x_block_calculate_sci_baud( ...
                config.lspclk_hz, supportedBaud));
            first = c2837x_block_calculate_sci_baud( ...
                config.lspclk_hz, supportedBaud);
            second = c2837x_block_calculate_sci_baud( ...
                config.lspclk_hz, supportedBaud);

            testCase.verifyEqual(first, second);
            testCase.verifyClass(first.brr, 'uint16');
            testCase.verifyGreaterThanOrEqual(first.brr, uint16(1));
            testCase.verifyLessThanOrEqual(first.brr, intmax('uint16'));
            testCase.verifyEqual(first.brr, expected.brr);
            testCase.verifyEqual(first.actual_baud, expected.actual_baud, ...
                AbsTol=floating_tolerance(expected.actual_baud));
            testCase.verifyEqual(first.signed_error_baud, ...
                first.actual_baud - supportedBaud, ...
                AbsTol=floating_tolerance(first.signed_error_baud));
            testCase.verifyEqual(first.absolute_error_baud, ...
                abs(first.signed_error_baud), ...
                AbsTol=floating_tolerance(first.absolute_error_baud));
            testCase.verifyEqual(first.signed_relative_error_ratio, ...
                first.signed_error_baud / supportedBaud, ...
                AbsTol=floating_tolerance( ...
                first.signed_relative_error_ratio));
        end

        function testExactTieSelectsSmallerBrr(testCase)
            result = c2837x_block_calculate_sci_baud(384, 20);

            testCase.verifyEqual(result.brr, uint16(1));
            testCase.verifyEqual(result.actual_baud, 24, AbsTol=eps(24));
            testCase.verifyEqual(result.absolute_error_baud, 4, ...
                AbsTol=eps(4));
        end

        function testIdealBelowMinimumClampsToMinimum(testCase)
            result = c2837x_block_calculate_sci_baud(1000, 1000);

            testCase.verifyEqual(result.brr, uint16(1));
            testCase.verifyEqual(result.actual_baud, 62.5, AbsTol=eps(62.5));
        end

        function testIdealAboveMaximumClampsToMaximum(testCase)
            result = c2837x_block_calculate_sci_baud(1e6, 1);

            testCase.verifyEqual(result.brr, uint16(65535));
            testCase.verifyEqual(result.actual_baud, 1e6 / (8 * 65536), ...
                AbsTol=eps(1e6 / (8 * 65536)));
        end

        function testInvalidLspclkRejected(testCase, invalidValue)
            testCase.verifyError(@() ...
                c2837x_block_calculate_sci_baud(invalidValue, 9600), ...
                'C2837xBlock:SciBaud:InvalidLspclkHz');
        end

        function testInvalidRequestedBaudRejected(testCase, invalidValue)
            testCase.verifyError(@() ...
                c2837x_block_calculate_sci_baud(200e6 / 14, invalidValue), ...
                'C2837xBlock:SciBaud:InvalidRequestedBaud');
        end
    end
end

function result = reference_result(lspclkHz, requestedBaud)
brr = 1:65535;
actualBaud = lspclkHz ./ (8 * (brr + 1));
[~, selectedIndex] = min(abs(actualBaud - requestedBaud));
result = struct('brr', uint16(brr(selectedIndex)), ...
    'actual_baud', actualBaud(selectedIndex));
end

function tolerance = floating_tolerance(value)
tolerance = max(1e-15, 4 * eps(abs(value)));
end
