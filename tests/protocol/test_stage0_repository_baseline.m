function tests = test_stage0_repository_baseline
%TEST_STAGE0_REPOSITORY_BASELINE Static repository baseline checks.
tests = functiontests(localfunctions);
end

function testAuthoritativeInputs(testCase)
root = repository_root();
verifyTrue(testCase, isfile(fullfile(root, 'requirements', ...
    'requirements_multi_iodevice_v1.0_frozen_rev2.md')));
verifyTrue(testCase, isfile(fullfile(root, 'plan.md')));
verifyFalse(testCase, isfile(fullfile(root, 'spec_v2_3.md')));
verifyFalse(testCase, isfile(fullfile(root, 'requirements_multi_iodevice (1).md')));
end

function testReadmeDoesNotPromoteLegacySpec(testCase)
root = repository_root();
text = fileread(fullfile(root, 'README.md'));
verifyNotEmpty(testCase, regexp(text, ...
    'requirements/requirements_multi_iodevice_v1\.0_frozen_rev2\.md', 'once'));
verifyEmpty(testCase, regexp(text, 'spec_v2_3\.md', 'once'));
verifyNotEmpty(testCase, regexp(text, '旧单实例', 'once'));
end

function testPlanCoversAllFrNumbers(testCase)
root = repository_root();
text = fileread(fullfile(root, 'plan.md'));
covered = false(1, 267);
ranges = regexp(text, 'FR-(\d{3})\s*[～~-]\s*FR-(\d{3})', 'tokens');
for index = 1:numel(ranges)
    first = str2double(ranges{index}{1});
    last = str2double(ranges{index}{2});
    covered(first:last) = true;
end
singles = regexp(text, 'FR-(\d{3})', 'tokens');
for index = 1:numel(singles)
    value = str2double(singles{index}{1});
    if value >= 1 && value <= 267
        covered(value) = true;
    end
end
verifyFalse(testCase, any(~covered));
end

function testStageZeroTasksAndGateExist(testCase)
root = repository_root();
text = fileread(fullfile(root, 'plan.md'));
for task = {'S0-01','S0-02','S0-03','S0-04','S0-05'}
    verifyNotEmpty(testCase, regexp(text, task{1}, 'once'));
end
verifyNotEmpty(testCase, regexp(text, '阶段0门禁 G0', 'once'));
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
