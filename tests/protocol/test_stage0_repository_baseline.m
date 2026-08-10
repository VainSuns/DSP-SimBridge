function tests = test_stage0_repository_baseline
%TEST_STAGE0_REPOSITORY_BASELINE Static repository baseline checks.
tests = functiontests(localfunctions);
end

function testAuthoritativeInputs(testCase)
root = repository_root();
verifyTrue(testCase, isfile(fullfile(root, 'requirements', ...
    'requirements_sci_iodevice_v1.0_frozen.md')));
verifyTrue(testCase, isfile(fullfile(root, 'plan.md')));
verifyTrue(testCase, isfile(fullfile(root, 'requirements', 'archive', ...
    'requirements_multi_iodevice_v1.0_frozen_rev2.md')));
verifyTrue(testCase, isfile(fullfile(root, 'docs', 'archive', ...
    'plan_multi_instance_v1_completed.md')));
verifyTrue(testCase, isfile(fullfile(root, 'docs', 'archive', ...
    'requirements_traceability_multi_instance_v1.md')));
verifyFalse(testCase, isfile(fullfile(root, ...
    'requirements_sci_iodevice_v1.0_frozen.md')));
verifyFalse(testCase, isfile(fullfile(root, ...
    'plan_sci_iodevice_v1.0_approved.md')));
verifyFalse(testCase, isfile(fullfile(root, 'spec_v2_3.md')));
verifyFalse(testCase, isfile(fullfile(root, 'requirements_multi_iodevice (1).md')));
end

function testReadmeDoesNotPromoteLegacySpec(testCase)
root = repository_root();
text = fileread(fullfile(root, 'README.md'));
verifyNotEmpty(testCase, regexp(text, ...
    'requirements/requirements_sci_iodevice_v1\.0_frozen\.md', 'once'));
verifyNotEmpty(testCase, regexp(text, ...
    'requirements/archive/requirements_multi_iodevice_v1\.0_frozen_rev2\.md', 'once'));
verifyNotEmpty(testCase, regexp(text, ...
    'docs/archive/plan_multi_instance_v1_completed\.md', 'once'));
verifyNotEmpty(testCase, regexp(text, ...
    'docs/archive/requirements_traceability_multi_instance_v1\.md', 'once'));
verifyEmpty(testCase, regexp(text, 'spec_v2_3\.md', 'once'));
verifyNotEmpty(testCase, regexp(text, 'V2 多实例项目', 'once'));
verifyNotEmpty(testCase, regexp(text, '历史参考', 'once'));
verifyNotEmpty(testCase, regexp(text, '与当前 V2 多实例 App 不一致', 'once'));
end

function testPlanCoversAllFrNumbers(testCase)
root = repository_root();
text = fileread(fullfile(root, 'plan.md'));
covered = false(1, 95);
ranges = regexp(text, 'FR-(\d{3})\s*[～~-]\s*FR-(\d{3})', 'tokens');
for index = 1:numel(ranges)
    first = str2double(ranges{index}{1});
    last = str2double(ranges{index}{2});
    first = max(first, 1);
    last = min(last, 95);
    if first <= last
        covered(first:last) = true;
    end
end
singles = regexp(text, 'FR-(\d{3})', 'tokens');
for index = 1:numel(singles)
    value = str2double(singles{index}{1});
    if value >= 1 && value <= 95
        covered(value) = true;
    end
end
verifyFalse(testCase, any(~covered));
end

function testStageZeroTasksAndGateExist(testCase)
root = repository_root();
text = fileread(fullfile(root, 'plan.md'));
for task = {'SCI-S0-01','SCI-S0-02'}
    verifyNotEmpty(testCase, regexp(text, task{1}, 'once'));
end
verifyNotEmpty(testCase, regexp(text, 'SCI Stage 0 Gate：SCI-G0', 'once'));
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
