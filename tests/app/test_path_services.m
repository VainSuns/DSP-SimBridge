classdef test_path_services < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
        end
    end

    methods (TestMethodSetup)
        function createWorkFolder(testCase)
            testCase.WorkFolder = tempname;
            mkdir(testCase.WorkFolder);
            testCase.WorkFolder = c2837x_block_normalize_absolute_path(testCase.WorkFolder);
            testCase.addTeardown(@() rmdir(testCase.WorkFolder, 's'));
        end
    end

    methods (Test)
        function testCanonicalizesDotsAndTrailingSeparator(testCase)
            raw = fullfile(testCase.WorkFolder, 'one', '..', 'two', '.');
            expected = fullfile(testCase.WorkFolder, 'two');
            testCase.verifyEqual(c2837x_block_normalize_absolute_path(raw), expected);
        end

        function testEmptyAndStringInput(testCase)
            testCase.verifyEqual(c2837x_block_normalize_absolute_path(''), '');
            testCase.verifyEqual(c2837x_block_normalize_absolute_path(string(testCase.WorkFolder)), ...
                testCase.WorkFolder);
        end

        function testRejectsRelativeAndPlaceholders(testCase)
            testCase.verifyError(@() c2837x_block_normalize_absolute_path('relative/file.c'), ...
                'C2837xBlock:Path:RelativeNotAllowed');
            testCase.verifyError(@() c2837x_block_normalize_absolute_path('~/file.c'), ...
                'C2837xBlock:Path:PlaceholderNotAllowed');
            testCase.verifyError(@() c2837x_block_normalize_absolute_path('%TEMP%\file.c'), ...
                'C2837xBlock:Path:PlaceholderNotAllowed');
        end

        function testIndependentOfCurrentFolderAndAllowsMissing(testCase)
            raw = fullfile(testCase.WorkFolder, 'missing', '..', 'future');
            before = pwd;
            first = c2837x_block_normalize_absolute_path(raw);
            cd(tempdir);
            cleanup = onCleanup(@() cd(before));
            second = c2837x_block_normalize_absolute_path(raw);
            testCase.verifyEqual(second, first);
            testCase.verifyFalse(isfolder(first));
        end

        function testWindowsSeparatorsAndRoot(testCase)
            testCase.assumeTrue(ispc);
            mixed = strrep(fullfile(testCase.WorkFolder, 'child'), '\', '/');
            testCase.verifyEqual(c2837x_block_normalize_absolute_path(mixed), ...
                fullfile(testCase.WorkFolder, 'child'));
            root = fileparts(testCase.WorkFolder);
            while ~strcmp(fileparts(root), root)
                root = fileparts(root);
            end
            testCase.verifyEqual(c2837x_block_normalize_absolute_path(root), root);
        end

        function testTargetDuplicateAndKindConflict(testCase)
            path = fullfile(testCase.WorkFolder, 'same');
            targets = [target(path, 'file'), target(path, 'directory')];
            issues = c2837x_block_validate_path_targets(targets);
            testCase.verifyTrue(any(strcmp({issues.code}, 'TARGET_KIND_CONFLICT')));
        end

        function testTargetCaseConflictOnWindows(testCase)
            testCase.assumeTrue(ispc);
            lowerPath = fullfile(testCase.WorkFolder, 'case.c');
            upperPath = fullfile(testCase.WorkFolder, 'CASE.c');
            issues = c2837x_block_validate_path_targets( ...
                [target(lowerPath, 'file'), target(upperPath, 'file')]);
            testCase.verifyTrue(any(strcmp({issues.code}, 'TARGET_CASE_CONFLICT')));
        end

        function testTargetFileParentConflict(testCase)
            parent = fullfile(testCase.WorkFolder, 'file');
            child = fullfile(parent, 'child.c');
            issues = c2837x_block_validate_path_targets( ...
                [target(parent, 'file'), target(child, 'file')]);
            testCase.verifyTrue(any(strcmp({issues.code}, 'TARGET_BELOW_FILE')));
        end

        function testWindowsRootTargetFileParentConflict(testCase)
            testCase.assumeTrue(ispc);
            root = filesystem_root(testCase.WorkFolder);
            targets = [target(root, 'file'), ...
                target(fullfile(root, 'generated', 'file.c'), 'file')];
            issues = c2837x_block_validate_path_targets(targets);
            testCase.verifyTrue(any(strcmp({issues.code}, 'TARGET_BELOW_FILE')));
        end

        function testUnixRootTargetFileParentConflict(testCase)
            testCase.assumeFalse(ispc);
            targets = [target(filesep, 'file'), ...
                target(fullfile(filesep, 'generated', 'file.c'), 'file')];
            issues = c2837x_block_validate_path_targets(targets);
            testCase.verifyTrue(any(strcmp({issues.code}, 'TARGET_BELOW_FILE')));
        end

        function testSimilarTargetDirectoryNamesAreNotRelated(testCase)
            root = filesystem_root(testCase.WorkFolder);
            targets = [target(fullfile(root, 'dsp'), 'file'), ...
                target(fullfile(root, 'dsp2', 'file.c'), 'file')];
            issues = c2837x_block_validate_path_targets(targets);
            testCase.verifyFalse(any(ismember({issues.code}, ...
                {'TARGET_BELOW_FILE', 'TARGET_FILE_IS_PARENT'})));
        end

        function testExistingTypeConflictsAndOrder(testCase)
            filePath = fullfile(testCase.WorkFolder, 'occupied');
            fileID = fopen(filePath, 'w'); fclose(fileID);
            folderPath = fullfile(testCase.WorkFolder, 'folder'); mkdir(folderPath);
            targets = [target(filePath, 'directory'), target(folderPath, 'file')];
            first = c2837x_block_validate_path_targets(targets);
            second = c2837x_block_validate_path_targets(targets);
            testCase.verifyEqual(first, second);
            testCase.verifyEqual({first.code}, ...
                {'TARGET_DIRECTORY_OCCUPIED_BY_FILE', 'TARGET_FILE_OCCUPIED_BY_DIRECTORY'});
        end

        function testSessionRejectsNoncanonicalProjectPath(testCase)
            project = c2837x_block_create_default_project();
            project.output.dsp_root = fullfile(testCase.WorkFolder, 'a', '..', 'b');
            testCase.verifyError(@() c2837x_block_project_session(project), ...
                'C2837xBlock:Project:InvalidPath');
        end

        function testSessionLoadRejectsRelativeV2Path(testCase)
            project = c2837x_block_create_default_project();
            project.output.dsp_root = 'relative';
            filePath = fullfile(testCase.WorkFolder, 'relative.mat');
            save(filePath, 'project');
            session = c2837x_block_project_session();
            testCase.verifyError(@() session.loadProject(filePath), ...
                'C2837xBlock:Project:InvalidPath');
        end
    end
end

function value = target(path, kind)
value = struct('path', c2837x_block_normalize_absolute_path(path), ...
    'kind', kind, 'owner', 'test');
end

function root = filesystem_root(path)
root = path;
while ~strcmp(fileparts(root), root)
    root = fileparts(root);
end
end
