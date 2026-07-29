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

        function testDefaultAppUsesOfficialDspProvider(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            try
                app = C2837xBlockConfigurator();
            catch cause
                testCase.assumeFail(sprintf('uifigure unavailable: %s', cause.message));
            end
            cleanup = onCleanup(@() delete(app));
            app.UIFigure.Visible = 'off';
            project = smoke_project(fixture.Folder);
            app.Coordinator.updateProject(project);

            [view, issues] = app.Coordinator.createPreview();

            testCase.verifyEqual(view.status, 'valid');
            testCase.verifyFalse(any(strcmp({issues.severity}, 'Error')));
            testCase.verifyEqual(numel(view.comparisons), 25);
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

        function testSaveAndLoadUseCoordinatorRoutes(testCase)
            source = configurator_source();
            testCase.verifyEmpty(regexp(source, ...
                'ProjectSession\.(saveProject|loadProject|canDiscardChanges)', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'Coordinator\.saveProject\(', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'Coordinator\.loadProject\(', 'once'));
            testCase.verifyEqual(numel(regexp(source, ...
                'app\.saveCurrentProject\(\)', 'match')), 3);
        end

        function testDraftRoutesAndSuggestionsAreWired(testCase)
            source = configurator_source();
            testCase.verifyNotEmpty(regexp(source, ...
                'Coordinator\.updateProjectDraft\(', 'once'));
            testCase.verifyEmpty(regexp(source, ...
                'uint16\(app\.DetailFields|uint32\(app\.DetailFields', 'once'));
            testCase.verifyGreaterThanOrEqual(numel(regexp(source, ...
                'c2837x_block_suggest_unique_name\(', 'match')), 3);
            testCase.verifyEmpty(regexp(source, '''new_value''', 'once'));
            testCase.verifyNotEmpty(regexp(source, ...
                'app\.clearPreviewDisplay\(\)', 'once'));
        end
    end
end

function source = configurator_source()
path = which('C2837xBlockConfigurator');
source = fileread(path);
end

function project = smoke_project(root)
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
instance.display_name = 'Instance 1';
instance.internal_name = 'instance_1';
instance.inputs = struct('name', 'command', 'type', 'single', 'dim', 1);
instance.outputs = struct('name', 'status', 'type', 'single', 'dim', 1);
project.instances = instance;
end
