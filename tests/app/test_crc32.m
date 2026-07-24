classdef test_crc32 < matlab.unittest.TestCase
    properties (TestParameter)
        invalidInput = struct('double', 1, 'cell', {{'text'}}, ...
            'uint8Matrix', uint8(ones(2)), 'charMatrix', ['ab'; 'cd'], ...
            'stringArray', ["a" "b"])
    end

    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testStandardVector(testCase)
            actual = c2837x_block_crc32('123456789');

            testCase.verifyClass(actual, 'uint32');
            testCase.verifyEqual(actual, uint32(hex2dec('CBF43926')));
        end

        function testEmptyOctets(testCase)
            actual = c2837x_block_crc32(zeros(1, 0, 'uint8'));

            testCase.verifyEqual(actual, uint32(0));
        end

        function testRowAndColumnOctetsMatch(testCase)
            row = uint8([1 2 3 4 255]);

            testCase.verifyEqual(c2837x_block_crc32(row), ...
                c2837x_block_crc32(row.'));
        end

        function testCharAndUtf8OctetsMatch(testCase)
            text = '123456789';

            testCase.verifyEqual(c2837x_block_crc32(text), ...
                c2837x_block_crc32(unicode2native(text, 'UTF-8')));
        end

        function testNonAsciiUsesExplicitUtf8(testCase)
            text = native2unicode(uint8([228 184 173 230 150 135]), 'UTF-8');
            utf8 = uint8([228 184 173 230 150 135]);

            testCase.verifyEqual(c2837x_block_crc32(text), ...
                c2837x_block_crc32(utf8));
            testCase.verifyEqual(c2837x_block_crc32(string(text)), ...
                c2837x_block_crc32(utf8));
        end

        function testInvalidInputsRejected(testCase, invalidInput)
            testCase.verifyError(@() c2837x_block_crc32(invalidInput), ...
                'C2837xBlock:CRC32:InvalidInput');
        end
    end
end
