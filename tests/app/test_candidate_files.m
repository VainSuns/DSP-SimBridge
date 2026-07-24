classdef test_candidate_files < matlab.unittest.TestCase
    properties
        WorkFolder
    end

    methods (TestClassSetup)
        function addCandidatePaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'app', 'fixtures')));
        end
    end

    methods (TestMethodSetup)
        function createWorkFolder(testCase)
            testCase.WorkFolder = c2837x_block_normalize_absolute_path(tempname);
            mkdir(testCase.WorkFolder);
            testCase.addTeardown(@() rmdir(testCase.WorkFolder, 's'));
        end
    end

    methods (Test)
        function testBuilderAcceptsCategoriesAndPreservesOrder(testCase)
            definitions = basic_definitions(testCase.WorkFolder);

            candidates = c2837x_block_build_candidate_files(definitions);

            testCase.verifyEqual({candidates.category}, ...
                {'auto_generated', 'core', 'user'});
            testCase.verifyEqual({candidates.target_path}, {definitions.target_path});
            testCase.verifyEqual({candidates.content_bytes}, {definitions.content_bytes});
            testCase.verifyEqual([candidates.content_size_octets], [1 2 3]);
            testCase.verifyEqual(fieldnames(candidates), {'target_path'; 'category'; ...
                'owner'; 'instance_index'; 'content_bytes'; 'content_size_octets'});
        end

        function testBuilderAcceptsEmptyUint8Row(testCase)
            candidateDefinition = definition(testCase.WorkFolder, 'empty.bin', 'user', ...
                zeros(1, 0, 'uint8'), 0);

            candidate = c2837x_block_build_candidate_files(candidateDefinition);

            testCase.verifyClass(candidate.content_bytes, 'uint8');
            testCase.verifySize(candidate.content_bytes, [1 0]);
            testCase.verifyEqual(candidate.content_size_octets, 0);
        end

        function testBuilderRejectsInvalidCategory(testCase)
            value = definition(testCase.WorkFolder, 'bad.txt', 'guessed', uint8(1), 0);
            testCase.verifyError(@() c2837x_block_build_candidate_files(value), ...
                'C2837xBlock:Candidate:InvalidCategory');
        end

        function testBuilderRejectsInvalidContentShapes(testCase)
            notBytes = definition(testCase.WorkFolder, 'double.bin', 'core', 1, 0);
            column = definition(testCase.WorkFolder, 'column.bin', 'core', uint8([1; 2]), 0);

            testCase.verifyError(@() c2837x_block_build_candidate_files(notBytes), ...
                'C2837xBlock:Candidate:InvalidContent');
            testCase.verifyError(@() c2837x_block_build_candidate_files(column), ...
                'C2837xBlock:Candidate:InvalidContent');
        end

        function testBuilderRejectsRelativeAndNoncanonicalPaths(testCase)
            relative = definition_with_path('relative.txt');
            noncanonical = definition_with_path(fullfile( ...
                testCase.WorkFolder, 'one', '..', 'two.txt'));

            testCase.verifyError(@() c2837x_block_build_candidate_files(relative), ...
                'C2837xBlock:Candidate:InvalidPath');
            testCase.verifyError(@() c2837x_block_build_candidate_files(noncanonical), ...
                'C2837xBlock:Candidate:InvalidPath');
        end

        function testBuilderRejectsOwnerAndInstanceIndex(testCase)
            emptyOwner = definition(testCase.WorkFolder, 'owner.txt', 'user', uint8(1), 0);
            emptyOwner.owner = '';
            fractional = definition(testCase.WorkFolder, 'index.txt', 'user', uint8(1), 1.5);

            testCase.verifyError(@() c2837x_block_build_candidate_files(emptyOwner), ...
                'C2837xBlock:Candidate:InvalidOwner');
            testCase.verifyError(@() c2837x_block_build_candidate_files(fractional), ...
                'C2837xBlock:Candidate:InvalidInstanceIndex');
        end

        function testBuilderRejectsInvalidDefinitions(testCase)
            testCase.verifyError(@() c2837x_block_build_candidate_files(struct('target_path', 'x')), ...
                'C2837xBlock:Candidate:InvalidDefinitions');
        end

        function testBuilderDoesNotMutateDefinitions(testCase)
            definitions = basic_definitions(testCase.WorkFolder);
            before = definitions;

            c2837x_block_build_candidate_files(definitions);

            testCase.verifyEqual(definitions, before);
        end

        function testCandidatePathDuplicateAndCaseConflict(testCase)
            first = definition(testCase.WorkFolder, 'same.txt', 'user', uint8(1), 1);
            duplicate = first;
            upperCase = definition(testCase.WorkFolder, 'SAME.TXT', 'core', uint8(2), 0);
            candidates = c2837x_block_build_candidate_files([first duplicate upperCase]);

            issues = c2837x_block_validate_candidate_files(candidates);

            testCase.verifyEqual({issues.code}, ...
                {'TARGET_DUPLICATE', 'TARGET_CASE_CONFLICT', 'TARGET_CASE_CONFLICT'});
            testCase.verifyEqual({issues.field_path}, ...
                {'candidates(2).target_path', 'candidates(3).target_path', ...
                'candidates(3).target_path'});
            testCase.verifyEqual([issues.instance_index], [1 0 0]);
        end

        function testCandidateCaseConflictUsesPlatformSemantics(testCase)
            testCase.assumeTrue(ispc);
            lower = definition(testCase.WorkFolder, 'case.txt', 'user', uint8(1), 1);
            upper = definition(testCase.WorkFolder, 'CASE.txt', 'user', uint8(1), 1);
            candidates = c2837x_block_build_candidate_files([lower upper]);

            issues = c2837x_block_validate_candidate_files(candidates);

            testCase.verifyEqual({issues.code}, {'TARGET_CASE_CONFLICT'});
        end

        function testCandidateFileParentConflict(testCase)
            parent = definition(testCase.WorkFolder, 'parent', 'core', uint8(1), 0);
            child = definition_with_path(fullfile(parent.target_path, 'child.txt'));
            candidates = c2837x_block_build_candidate_files([parent child]);

            issues = c2837x_block_validate_candidate_files(candidates);

            testCase.verifyEqual({issues.code}, {'TARGET_BELOW_FILE'});
            testCase.verifyEqual(issues.file_path, child.target_path);
        end

        function testCandidateDirectoryOccupationIsLocalized(testCase)
            folder = fullfile(testCase.WorkFolder, 'occupied');
            mkdir(folder);
            candidate = c2837x_block_build_candidate_files( ...
                definition_with_path(folder));

            issues = c2837x_block_validate_candidate_files(candidate);

            testCase.verifyEqual({issues.code}, {'CANDIDATE_TARGET_IS_DIRECTORY'});
            testCase.verifyEqual(issues.file_path, folder);
            testCase.verifyEqual(issues.field_path, 'candidates(1).target_path');
        end

        function testPathIssueOrderIsDeterministic(testCase)
            first = definition(testCase.WorkFolder, 'same.txt', 'user', uint8(1), 1);
            candidates = c2837x_block_build_candidate_files([first first]);

            one = c2837x_block_validate_candidate_files(candidates);
            two = c2837x_block_validate_candidate_files(candidates);

            testCase.verifyEqual(two, one);
        end

        function testFixedFixtureDecisionMatrix(testCase)
            [definitions, expected] = c2837x_block_stage1_candidate_fixture(testCase.WorkFolder);
            candidates = c2837x_block_build_candidate_files(definitions);

            [comparisons, issues] = c2837x_block_compare_candidate_files(candidates);

            testCase.verifyEmpty(issues);
            testCase.verifyEqual({comparisons.target_state}, expected.states);
            testCase.verifyEqual({comparisons.default_action}, expected.actions);
            testCase.verifyEqual({comparisons.selected_action}, expected.actions);
            testCase.verifyEqual([comparisons.action_mandatory], expected.mandatory);
            testCase.verifyEqual({comparisons.category}, {candidates.category});
            testCase.verifyEqual({comparisons.target_path}, {candidates.target_path});
            testCase.verifyEqual({comparisons.owner}, {candidates.owner});
            testCase.verifyEmpty(c2837x_block_validate_candidate_actions(comparisons));
        end

        function testUserDifferentAllowsKeepOrReplace(testCase)
            comparisons = fixture_comparisons(testCase.WorkFolder);
            userIndex = 8;
            comparisons(userIndex).selected_action = 'replace';

            replaceIssues = c2837x_block_validate_candidate_actions(comparisons);
            comparisons(userIndex).selected_action = 'create';
            createIssues = c2837x_block_validate_candidate_actions(comparisons);
            comparisons(userIndex).selected_action = 'skip';
            skipIssues = c2837x_block_validate_candidate_actions(comparisons);

            testCase.verifyEmpty(replaceIssues);
            testCase.verifyEqual({createIssues.code}, {'CANDIDATE_ACTION_INVALID'});
            testCase.verifyEqual({skipIssues.code}, {'CANDIDATE_ACTION_INVALID'});
        end

        function testMandatoryActionErrors(testCase)
            comparisons = fixture_comparisons(testCase.WorkFolder);

            testCase.verifyEqual(invalid_code(comparisons, 3, 'keep'), ...
                'CANDIDATE_REPLACE_REQUIRED');
            testCase.verifyEqual(invalid_code(comparisons, 5, 'keep'), ...
                'CANDIDATE_REPLACE_REQUIRED');
            testCase.verifyEqual(invalid_code(comparisons, 1, 'skip'), ...
                'CANDIDATE_CREATE_REQUIRED');
            testCase.verifyEqual(invalid_code(comparisons, 2, 'replace'), ...
                'CANDIDATE_SKIP_REQUIRED');
        end

        function testBlockedComparisonCannotExecute(testCase)
            comparison = fixture_comparisons(testCase.WorkFolder);
            comparison(1).target_state = 'blocked';
            comparison(1).selected_action = 'blocked';

            issues = c2837x_block_validate_candidate_actions(comparison);

            testCase.verifyEqual({issues.code}, {'CANDIDATE_COMPARISON_BLOCKED'});
            testCase.verifyEqual({issues.field_path}, {'comparisons(1).selected_action'});
        end

        function testExactOctetComparison(testCase)
            path = fullfile(testCase.WorkFolder, 'octets.bin');

            testCase.verifyEqual(compare_after_write(path, uint8([1 2 3]), uint8([1 2 3])), 'same');
            testCase.verifyEqual(compare_after_write(path, uint8([1 2 3]), uint8([1 2 4])), 'different');
            testCase.verifyEqual(compare_after_write(path, uint8([65 10]), uint8([65 13 10])), 'different');
            testCase.verifyEqual(compare_after_write(path, uint8(65), ...
                uint8([239 187 191 65])), 'different');
            testCase.verifyEqual(compare_after_write(path, uint8([65 10]), uint8(65)), 'different');
            testCase.verifyEqual(compare_after_write(path, uint8([0 255 1]), uint8([0 255 1])), 'same');
            testCase.verifyEqual(compare_after_write(path, zeros(1, 0, 'uint8'), ...
                zeros(1, 0, 'uint8')), 'same');
        end

        function testDirectoryTargetBlocksComparison(testCase)
            folder = fullfile(testCase.WorkFolder, 'directory.txt');
            mkdir(folder);
            candidate = c2837x_block_build_candidate_files(definition_with_path(folder));

            [comparison, issues] = c2837x_block_compare_candidate_files(candidate);

            testCase.verifyEqual(comparison.target_state, 'blocked');
            testCase.verifyEqual(comparison.default_action, 'blocked');
            testCase.verifyEqual(comparison.selected_action, 'blocked');
            testCase.verifyEqual({issues.code}, {'CANDIDATE_TARGET_IS_DIRECTORY'});
        end

        function testUnreadableTargetDoesNotAbortOtherCandidates(testCase)
            testCase.assumeFalse(ispc, ...
                'Windows current-account permissions do not reliably create an unreadable file.');
            blockedPath = fullfile(testCase.WorkFolder, 'unreadable.bin');
            otherPath = fullfile(testCase.WorkFolder, 'other.bin');
            write_bytes(blockedPath, uint8(1));
            write_bytes(otherPath, uint8(2));
            make_unreadable(blockedPath, testCase);
            definitions = [definition_with_path(blockedPath), ...
                definition_with_path(otherPath)];
            definitions(2).content_bytes = uint8(2);
            candidates = c2837x_block_build_candidate_files(definitions);

            [comparisons, issues] = c2837x_block_compare_candidate_files(candidates);

            testCase.verifyEqual(comparisons(1).target_state, 'blocked');
            testCase.verifyEqual(comparisons(2).target_state, 'same');
            testCase.verifyEqual({issues.code}, {'CANDIDATE_TARGET_UNREADABLE'});
        end

        function testServicesAreDeterministicAndPwdIndependent(testCase)
            [definitions, ~] = c2837x_block_stage1_candidate_fixture(testCase.WorkFolder);

            first = run_pipeline(definitions);
            unrelated = fullfile(testCase.WorkFolder, 'unrelated.txt');
            write_bytes(unrelated, uint8(9));
            second = run_pipeline_from_folder(definitions, tempdir);

            testCase.verifyEqual(second, first);
        end

        function testCompareDoesNotWriteOrTouchTargets(testCase)
            [definitions, ~] = c2837x_block_stage1_candidate_fixture(testCase.WorkFolder);
            candidates = c2837x_block_build_candidate_files(definitions);
            before = filesystem_snapshot(testCase.WorkFolder);

            comparisons = c2837x_block_compare_candidate_files(candidates);
            after = filesystem_snapshot(testCase.WorkFolder);

            testCase.verifyEqual(after, before);
            testCase.verifyFalse(isfile(definitions(1).target_path));
            testCase.verifyFalse(isfile(definitions(6).target_path));
            testCase.verifyEqual(comparisons(8).selected_action, 'keep');
        end
    end
end

function definitions = basic_definitions(root)
definitions = [definition(root, 'one.bin', 'auto_generated', uint8(1), 0), ...
    definition(root, 'two.bin', 'core', uint8([2 3]), 0), ...
    definition(root, 'three.bin', 'user', uint8([4 5 6]), 1)];
end

function value = definition(root, name, category, bytes, instanceIndex)
value = struct('target_path', fullfile(root, name), 'category', category, ...
    'owner', ['test:' name], 'instance_index', instanceIndex, ...
    'content_bytes', bytes);
end

function value = definition_with_path(path)
value = struct('target_path', path, 'category', 'user', 'owner', 'test:file', ...
    'instance_index', 1, 'content_bytes', uint8(1));
end

function comparisons = fixture_comparisons(root)
[definitions, ~] = c2837x_block_stage1_candidate_fixture(root);
candidates = c2837x_block_build_candidate_files(definitions);
comparisons = c2837x_block_compare_candidate_files(candidates);
end

function code = invalid_code(comparisons, index, action)
comparisons(index).selected_action = action;
issues = c2837x_block_validate_candidate_actions(comparisons);
code = issues.code;
end

function state = compare_after_write(path, candidateBytes, existingBytes)
write_bytes(path, existingBytes);
value = definition_with_path(path);
value.content_bytes = candidateBytes;
candidate = c2837x_block_build_candidate_files(value);
comparison = c2837x_block_compare_candidate_files(candidate);
state = comparison.target_state;
end

function result = run_pipeline(definitions)
result.candidates = c2837x_block_build_candidate_files(definitions);
result.path_issues = c2837x_block_validate_candidate_files(result.candidates);
[result.comparisons, result.comparison_issues] = ...
    c2837x_block_compare_candidate_files(result.candidates);
result.action_issues = c2837x_block_validate_candidate_actions(result.comparisons);
end

function result = run_pipeline_from_folder(definitions, folder)
before = pwd;
cleanup = onCleanup(@() cd(before));
cd(folder);
result = run_pipeline(definitions);
clear cleanup
end

function snapshot = filesystem_snapshot(root)
entries = dir(fullfile(root, '**', '*'));
entries = entries(~[entries.isdir]);
[~, order] = sort({entries.name});
entries = entries(order);
snapshot = struct('name', {entries.name}, 'folder', {entries.folder}, ...
    'bytes', {entries.bytes}, 'datenum', {entries.datenum}, ...
    'content', cell(1, numel(entries)));
for index = 1:numel(entries)
    snapshot(index).content = read_bytes(fullfile(entries(index).folder, entries(index).name));
end
end

function make_unreadable(path, testCase)
[success, attributes] = fileattrib(path, '-r', 'a');
testCase.assumeTrue(success, 'Unable to remove read permission on this platform.');
testCase.addTeardown(@() fileattrib(path, '+r', 'a'));
fileID = fopen(path, 'rb');
testCase.assumeLessThan(fileID, 0, ...
    'Current account can still read a permission-restricted file.');
testCase.verifyNotEmpty(attributes);
end

function write_bytes(path, bytes)
fileID = fopen(path, 'wb');
assert(fileID >= 0, 'Test target could not be opened.');
cleanup = onCleanup(@() fclose(fileID));
fwrite(fileID, bytes, 'uint8');
clear cleanup
end

function bytes = read_bytes(path)
fileID = fopen(path, 'rb');
assert(fileID >= 0, 'Test target could not be read.');
cleanup = onCleanup(@() fclose(fileID));
bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
clear cleanup
end
