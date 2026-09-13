function tests = test_stage0_repository_baseline
%TEST_STAGE0_REPOSITORY_BASELINE Static repository baseline checks.
tests = functiontests(localfunctions);
end

function testAuthoritativeInputs(testCase)
root = repository_root();
verifyTrue(testCase, isfile(fullfile(root, 'requirements', ...
    'requirements_w5300_udp_iodevice_v1.0_frozen.md')));
verifyTrue(testCase, isfile(fullfile(root, 'plan.md')));
verifyTrue(testCase, isfile(fullfile(root, 'requirements', 'archive', ...
    'requirements_sci_iodevice_v1.0_frozen.md')));
verifyTrue(testCase, isfile(fullfile(root, 'docs', 'archive', ...
    'plan_sci_iodevice_v1.0_completed.md')));
verifyFalse(testCase, isfile(fullfile(root, 'docs', 'archive', ...
    'requirements_traceability_sci_iodevice_v1.0_completed.md')));
verifyTrue(testCase, isfile(fullfile(root, 'requirements', 'archive', ...
    'requirements_multi_iodevice_v1.0_frozen_rev2.md')));
verifyTrue(testCase, isfile(fullfile(root, 'docs', 'archive', ...
    'plan_multi_instance_v1_completed.md')));
verifyFalse(testCase, isfile(fullfile(root, 'docs', 'archive', ...
    'requirements_traceability_multi_instance_v1.md')));
verifyFalse(testCase, isfile(fullfile(root, ...
    'requirements_w5300_udp_iodevice_v1.0_frozen.md')));
verifyFalse(testCase, isfile(fullfile(root, ...
    'plan_w5300_udp_iodevice_v1.0_approved.md')));
verifyFalse(testCase, isfile(fullfile(root, ...
    'requirements_sci_iodevice_v1.0_frozen.md')));
verifyFalse(testCase, isfile(fullfile(root, 'docs', ...
    'requirements_traceability.md')));
verifyFalse(testCase, isfile(fullfile(root, 'spec_v2_3.md')));
verifyFalse(testCase, isfile(fullfile(root, 'requirements_multi_iodevice (1).md')));
end

function testReadmeCurrentAuthority(testCase)
root = repository_root();
text = fileread(fullfile(root, 'README.md'));
verifyNotEmpty(testCase, regexp(text, ...
    'requirements/requirements_w5300_udp_iodevice_v1\.0_frozen\.md', 'once'));
verifyNotEmpty(testCase, regexp(text, 'Current UDP implementation plan', 'once'));
verifyNotEmpty(testCase, regexp(text, 'W5300/TCP', 'once'));
verifyNotEmpty(testCase, regexp(text, 'W5300/UDP', 'once'));
verifyNotEmpty(testCase, regexp(text, 'SCI', 'once'));
verifyEmpty(testCase, regexp(text, ...
    'requirements/requirements_sci_iodevice_v1\.0_frozen\.md', 'once'));
verifyEmpty(testCase, regexp(text, 'docs/requirements_traceability\.md', 'once'));
verifyEmpty(testCase, regexp(text, ...
    'requirements_traceability_multi_instance_v1\.md', 'once'));
verifyEmpty(testCase, regexp(text, ...
    'requirements_traceability_sci_iodevice_v1\.0_completed\.md', 'once'));
verifyEmpty(testCase, regexp(text, 'spec_v2_3\.md', 'once'));
end

function testPlanCoversAllFrNumbers(testCase)
root = repository_root();
text = fileread(fullfile(root, 'plan.md'));
covered = false(1, 82);
ranges = regexp(text, 'FR-(\d{3})\s*[～~-]\s*FR-(\d{3})', 'tokens');
for index = 1:numel(ranges)
    first = str2double(ranges{index}{1});
    last = str2double(ranges{index}{2});
    first = max(first, 1);
    last = min(last, 82);
    if first <= last
        covered(first:last) = true;
    end
end
singles = regexp(text, 'FR-(\d{3})', 'tokens');
for index = 1:numel(singles)
    value = str2double(singles{index}{1});
    if value >= 1 && value <= 82
        covered(value) = true;
    end
end
verifyFalse(testCase, any(~covered));
end

function testStageZeroTasksAndGateExist(testCase)
root = repository_root();
text = fileread(fullfile(root, 'plan.md'));
for task = {'UDP-S0-01','UDP-S0-02'}
    verifyNotEmpty(testCase, regexp(text, task{1}, 'once'));
end
verifyNotEmpty(testCase, regexp(text, 'UDP Stage 0 Gate：UDP-G0', 'once'));
end

function testCurrentUdpAuthorityIdentity(testCase)
root = repository_root();
requirements = fileread(fullfile(root, 'requirements', ...
    'requirements_w5300_udp_iodevice_v1.0_frozen.md'));
plan = fileread(fullfile(root, 'plan.md'));
verifyNotEmpty(testCase, regexp(requirements, ...
    'Status\s*=\s*Frozen V1\.0', 'once'));
verifyNotEmpty(testCase, regexp(requirements, ...
    'FR range\s*=\s*FR-001 \.\.\. FR-082', 'once'));
verifyNotEmpty(testCase, regexp(plan, 'Approved for Implementation', 'once'));
verifyNotEmpty(testCase, regexp(plan, 'UDP-S0-02', 'once'));
verifyNotEmpty(testCase, regexp(plan, 'UDP-G0', 'once'));
end

function root = repository_root()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
