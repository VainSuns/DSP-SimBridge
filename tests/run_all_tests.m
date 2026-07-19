function result = run_all_tests(category)
%RUN_ALL_TESTS Run DSP-SimBridge tests by category.
%   RESULT = RUN_ALL_TESTS() runs every implemented category.
%   RESULT = RUN_ALL_TESTS(CATEGORY) runs protocol, app, dsp_host, or pc.
% Empty categories are reported as NOT_IMPLEMENTED and are never counted as
% passing tests.

if nargin < 1 || isempty(category)
    requested = {'protocol','app','dsp_host','pc'};
else
    category = char(string(category));
    valid = {'protocol','app','dsp_host','pc'};
    assert(any(strcmp(category, valid)), 'DSP-SimBridge:Tests:UnknownCategory', ...
        'Unknown test category: %s', category);
    requested = {category};
end

root = fileparts(mfilename('fullpath'));
records = repmat(empty_record(), 1, numel(requested));
for index = 1:numel(requested)
    name = requested{index};
    folder = fullfile(root, name);
    files = dir(fullfile(folder, 'test_*.m'));
    records(index).category = name;
    if isempty(files)
        records(index).status = 'NOT_IMPLEMENTED';
        records(index).unverified = {'No test_*.m files exist in this category.'};
        continue;
    end

    suite = testsuite(folder, 'IncludeSubfolders', true);
    outcomes = run(suite);
    records(index).total = numel(outcomes);
    records(index).passed = sum([outcomes.Passed]);
    records(index).failed = sum([outcomes.Failed]);
    records(index).incomplete = sum([outcomes.Incomplete]);
    if records(index).failed > 0 || records(index).incomplete > 0
        records(index).status = 'FAILED';
    else
        records(index).status = 'PASSED';
    end
end

result = struct();
result.schema_version = uint16(1);
result.environment = struct('matlab_version', version, 'computer', computer);
result.categories = records;
result.total = sum([records.total]);
result.passed = sum([records.passed]);
result.failed = sum([records.failed]);
result.incomplete = sum([records.incomplete]);
result.not_implemented = sum(strcmp({records.status}, 'NOT_IMPLEMENTED'));

fprintf('%s\n', jsonencode(result, PrettyPrint=true));
if result.failed > 0 || result.incomplete > 0
    error('DSP-SimBridge:Tests:Failed', ...
        'Test run failed: %u failed, %u incomplete.', result.failed, result.incomplete);
end
end

function record = empty_record()
record = struct( ...
    'category', '', ...
    'status', 'NOT_IMPLEMENTED', ...
    'total', 0, ...
    'passed', 0, ...
    'failed', 0, ...
    'incomplete', 0, ...
    'unverified', {{}});
end
