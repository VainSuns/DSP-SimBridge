classdef test_app_name_suggestions < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testEmptyCollection(testCase)
            testCase.verifyEqual(c2837x_block_suggest_unique_name( ...
                'instance', {}), 'instance_1');
        end

        function testNextNumber(testCase)
            testCase.verifyEqual(c2837x_block_suggest_unique_name( ...
                'instance', {'instance_1'}), 'instance_2');
        end

        function testFillsGap(testCase)
            testCase.verifyEqual(c2837x_block_suggest_unique_name( ...
                'instance', {'instance_1', 'instance_3'}), 'instance_2');
        end

        function testCaseInsensitive(testCase)
            testCase.verifyEqual(c2837x_block_suggest_unique_name( ...
                'instance', {'Instance_1'}), 'instance_2');
        end

        function testDeterministicLongSequence(testCase)
            names = compose('instance_%u', 1:1000);
            testCase.verifyEqual(c2837x_block_suggest_unique_name( ...
                'instance', names), 'instance_1001');
        end

        function testInvalidPrefix(testCase)
            invalid = {'', '_instance', '1instance', 'bad-name'};
            for index = 1:numel(invalid)
                testCase.verifyError(@() c2837x_block_suggest_unique_name( ...
                    invalid{index}, {}), ...
                    'C2837xBlock:App:InvalidNameSuggestionInput');
            end
        end

        function testInvalidExistingNames(testCase)
            testCase.verifyError(@() c2837x_block_suggest_unique_name( ...
                'instance', {1}), ...
                'C2837xBlock:App:InvalidNameSuggestionInput');
        end

        function testDeletedMiddleInstance(testCase)
            testCase.verifyEqual(c2837x_block_suggest_unique_name( ...
                'instance', {'instance_1', 'instance_3'}), 'instance_2');
        end

        function testConsecutiveInputAdds(testCase)
            names = {'input_value_1', 'output_value_1'};
            first = c2837x_block_suggest_unique_name('input_value', names);
            second = c2837x_block_suggest_unique_name( ...
                'input_value', [names {first}]);
            testCase.verifyEqual({first, second}, ...
                {'input_value_2', 'input_value_3'});
        end

        function testInputOutputSharedScope(testCase)
            names = {'Input_Value_1', 'output_value_1'};
            testCase.verifyEqual(c2837x_block_suggest_unique_name( ...
                'input_value', names), 'input_value_2');
            testCase.verifyEqual(c2837x_block_suggest_unique_name( ...
                'output_value', names), 'output_value_2');
        end
    end
end
