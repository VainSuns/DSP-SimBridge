classdef test_configurator_smoke < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
        end
    end

    methods (Test)
        function testHiddenConstruction(testCase)
            originalFolder = pwd;
            originalPath = path;
            try
                app = C2837xBlockConfigurator(struct( ...
                    'visible', 'off', 'preview_provider', []));
            catch cause
                testCase.assumeFail(sprintf('uifigure unavailable: %s', cause.message));
            end
            cleanup = onCleanup(@() delete(app));
            testCase.verifyTrue(isvalid(app));
            testCase.verifyClass(app.ProjectSession, 'c2837x_block_project_session');
            testCase.verifyEqual(pwd, originalFolder);
            testCase.verifyEqual(path, originalPath);
            clear cleanup
        end

        function testInvalidOptionsRejected(testCase)
            testCase.verifyError(@() C2837xBlockConfigurator(struct( ...
                'visible', 'off', 'preview_provider', [], 'extra', true)), ...
                'C2837xBlock:App:InvalidOptions');
        end

        function testInvalidVisibilityRejected(testCase)
            testCase.verifyError(@() C2837xBlockConfigurator(struct( ...
                'visible', 'hidden', 'preview_provider', [])), ...
                'C2837xBlock:App:InvalidOptions');
        end

        function testInvalidProviderRejected(testCase)
            testCase.verifyError(@() C2837xBlockConfigurator(struct( ...
                'visible', 'off', 'preview_provider', 1)), ...
                'C2837xBlock:App:InvalidOptions');
        end
    end
end
