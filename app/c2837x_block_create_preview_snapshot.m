function [snapshot, issues, summary] = ...
        c2837x_block_create_preview_snapshot(project, candidates, dependencies)
%C2837X_BLOCK_CREATE_PREVIEW_SNAPSHOT Capture a deterministic preview state.

snapshot = struct();
issues = empty_issues();
summary = empty_summary();

try
    projectIssues = c2837x_block_validate_project(project, 'full');
catch
    projectIssues = make_issue('Error', 'PROJECT_STRUCTURE_INVALID', ...
        'Project validation could not inspect the supplied project.', ...
        'project', 0, '');
end
issues = [issues projectIssues];
if has_errors(issues)
    return;
end

try
    candidateIssues = c2837x_block_validate_candidate_files(candidates);
catch
    candidateIssues = make_issue('Error', 'CANDIDATES_INVALID', ...
        'Candidates could not be validated.', 'candidates', 0, '');
end
issues = [issues candidateIssues];
[capturedDependencies, dependencyIssues] = capture_dependencies(dependencies);
issues = [issues dependencyIssues];
if has_errors(issues)
    return;
end

[interfaceSpecs, interfaceIssues] = capture_interfaces(project);
[externalSources, externalIssues] = capture_external_sources(project);
issues = [issues interfaceIssues externalIssues];
if has_errors(issues)
    return;
end

try
    [comparisons, comparisonIssues] = ...
        c2837x_block_compare_candidate_files(candidates);
catch
    comparisons = empty_comparisons();
    comparisonIssues = make_issue('Error', 'CANDIDATES_INVALID', ...
        'Candidates could not be compared.', 'candidates', 0, '');
end
issues = [issues comparisonIssues];
if has_errors(issues)
    return;
end

[firstTargetStates, firstTargetIssues] = capture_targets(candidates);
[secondComparisons, secondComparisonIssues] = ...
    c2837x_block_compare_candidate_files(candidates);
[targetStates, secondTargetIssues] = capture_targets(candidates);
issues = [issues firstTargetIssues secondComparisonIssues secondTargetIssues];
if has_errors(issues)
    return;
end
if ~isequaln(comparisons, secondComparisons) || ...
        ~isequaln(firstTargetStates, targetStates) || ...
        ~comparison_matches_targets(comparisons, candidates, targetStates)
    issues(end + 1) = make_issue('Error', ...
        'SNAPSHOT_TARGET_CHANGED_DURING_CAPTURE', ...
        'A candidate target changed while the preview was captured.', ...
        'candidates', 0, '');
    return;
end

outputPaths = struct('dsp_root', project.output.dsp_root, ...
    'sfun_root', project.output.sfun_root);
snapshot = struct( ...
    'schema_version', uint16(1), ...
    'project', project, ...
    'output_paths', outputPaths, ...
    'interface_specs', interfaceSpecs, ...
    'dependencies', capturedDependencies, ...
    'external_sources', externalSources, ...
    'candidates', candidates, ...
    'comparison_baseline', comparisons, ...
    'target_states', targetStates);
summary = build_summary(snapshot);
end

function [captured, issues] = capture_dependencies(dependencies)
prototype = struct('role', '', 'identity', '', 'source_kind', '', ...
    'source_path', '', 'content_bytes', zeros(1, 0, 'uint8'), ...
    'content_size_octets', 0);
captured = repmat(prototype, 1, 0);
issues = empty_issues();
required = {'role', 'identity', 'source_kind', 'source_path', 'content_bytes'};
if ~isstruct(dependencies) || ~all(isfield(dependencies, required))
    issues = dependency_invalid('Dependencies must use the fixed input model.', 0);
    return;
end

captured = repmat(prototype, 1, numel(dependencies));
identities = cell(1, numel(dependencies));
roles = cell(1, numel(dependencies));
valid = true(1, numel(dependencies));
for index = 1:numel(dependencies)
    dependency = dependencies(index);
    [roleValid, role] = text_value(dependency.role, false);
    [identityValid, identity] = text_value(dependency.identity, false);
    [kindValid, sourceKind] = text_value(dependency.source_kind, false);
    [pathValid, sourcePath] = text_value(dependency.source_path, true);
    bytesValid = isa(dependency.content_bytes, 'uint8') && ...
        ismatrix(dependency.content_bytes) && ...
        size(dependency.content_bytes, 1) == 1;
    modelValid = roleValid && any(strcmp(role, ...
        {'generator_template', 'core_source'})) && identityValid && ...
        ~isempty(identity) && kindValid && any(strcmp(sourceKind, ...
        {'memory', 'file'})) && pathValid && bytesValid;
    if modelValid && strcmp(sourceKind, 'memory')
        modelValid = isempty(sourcePath);
    elseif modelValid
        modelValid = isempty(dependency.content_bytes) && ...
            canonical_path(sourcePath);
    end
    if ~modelValid
        issues(end + 1) = dependency_invalid( ...
            'Dependency fields do not satisfy the fixed input model.', index); %#ok<AGROW>
        valid(index) = false;
        continue;
    end
    identities{index} = identity;
    roles{index} = role;
    captured(index).role = role;
    captured(index).identity = identity;
    captured(index).source_kind = sourceKind;
    captured(index).source_path = sourcePath;
    if strcmp(sourceKind, 'memory')
        captured(index).content_bytes = dependency.content_bytes;
    else
        [bytes, code] = read_required_file(sourcePath, ...
            'SNAPSHOT_DEPENDENCY_UNREADABLE', ...
            'SNAPSHOT_DEPENDENCY_READ_FAILED');
        if ~isempty(code)
            issues(end + 1) = make_issue('Error', code, ...
                'Dependency content could not be captured.', ...
                sprintf('dependencies(%u).source_path', index), 0, sourcePath); %#ok<AGROW>
            valid(index) = false;
            continue;
        end
        captured(index).content_bytes = bytes;
    end
    captured(index).content_size_octets = ...
        double(numel(captured(index).content_bytes));
end

for later = 2:numel(dependencies)
    if ~valid(later)
        continue;
    end
    for earlier = 1:later - 1
        if valid(earlier) && strcmp(identities{later}, identities{earlier})
            issues(end + 1) = dependency_invalid( ...
                'Dependency identities must be exactly unique.', later); %#ok<AGROW>
            valid(later) = false;
            break;
        end
    end
end
if ~any(strcmp(roles(valid), 'generator_template'))
    issues(end + 1) = dependency_invalid( ...
        'At least one generator_template dependency is required.', 0);
end
if ~any(strcmp(roles(valid), 'core_source'))
    issues(end + 1) = dependency_invalid( ...
        'At least one core_source dependency is required.', 0);
end
end

function issue = dependency_invalid(message, index)
if index == 0
    fieldPath = 'dependencies';
else
    fieldPath = sprintf('dependencies(%u)', index);
end
issue = make_issue('Error', 'SNAPSHOT_DEPENDENCIES_INVALID', ...
    message, fieldPath, 0, '');
end

function [specs, issues] = capture_interfaces(project)
prototype = struct('instance_index', 0, 'internal_name', '', ...
    'canonical_text', '', 'interface_hash', uint32(0));
specs = repmat(prototype, 1, numel(project.instances));
issues = empty_issues();
for index = 1:numel(project.instances)
    try
        [canonicalText, interfaceHash] = ...
            c2837x_block_build_interface_hash(project, index);
        specs(index) = struct('instance_index', double(index), ...
            'internal_name', project.instances(index).internal_name, ...
            'canonical_text', canonicalText, ...
            'interface_hash', interfaceHash);
    catch
        issues(end + 1) = make_issue('Error', ...
            'SNAPSHOT_INTERFACE_BUILD_FAILED', ...
            'An Interface Hash specification could not be captured.', ...
            sprintf('project.instances(%u)', index), index, ''); %#ok<AGROW>
    end
end
end

function [sources, issues] = capture_external_sources(project)
prototype = struct('instance_index', 0, 'mode', '', 'source_path', '', ...
    'content_bytes', zeros(1, 0, 'uint8'), 'content_size_octets', 0);
externalCount = sum(arrayfun(@(instance) any(strcmp( ...
    instance.algorithm.mode, {'external_copy', 'external_reference'})), ...
    project.instances));
sources = repmat(prototype, 1, externalCount);
issues = empty_issues();
sourceIndex = 0;
for index = 1:numel(project.instances)
    algorithm = project.instances(index).algorithm;
    if ~any(strcmp(algorithm.mode, {'external_copy', 'external_reference'}))
        continue;
    end
    [bytes, code] = read_required_file(algorithm.source_path, ...
        'SNAPSHOT_EXTERNAL_SOURCE_UNREADABLE', ...
        'SNAPSHOT_EXTERNAL_SOURCE_READ_FAILED');
    if ~isempty(code)
        issues(end + 1) = make_issue('Error', code, ...
            'External algorithm source content could not be captured.', ...
            sprintf('project.instances(%u).algorithm.source_path', index), ...
            index, algorithm.source_path); %#ok<AGROW>
        continue;
    end
    sourceIndex = sourceIndex + 1;
    sources(sourceIndex) = struct('instance_index', double(index), ...
        'mode', algorithm.mode, 'source_path', algorithm.source_path, ...
        'content_bytes', bytes, 'content_size_octets', double(numel(bytes)));
end
end

function [states, issues] = capture_targets(candidates)
prototype = struct('target_path', '', 'state', '', ...
    'content_bytes', zeros(1, 0, 'uint8'), 'content_size_octets', 0);
states = repmat(prototype, 1, numel(candidates));
issues = empty_issues();
for index = 1:numel(candidates)
    path = candidates(index).target_path;
    states(index).target_path = path;
    if isfolder(path)
        issues(end + 1) = make_issue('Error', 'SNAPSHOT_TARGET_UNREADABLE', ...
            'A candidate target is not a regular readable file.', ...
            sprintf('candidates(%u).target_path', index), ...
            candidates(index).instance_index, path); %#ok<AGROW>
    elseif ~isfile(path)
        states(index).state = 'missing';
    else
        [bytes, code] = read_required_file(path, ...
            'SNAPSHOT_TARGET_UNREADABLE', 'SNAPSHOT_TARGET_READ_FAILED');
        if ~isempty(code)
            issues(end + 1) = make_issue('Error', code, ...
                'Candidate target content could not be captured.', ...
                sprintf('candidates(%u).target_path', index), ...
                candidates(index).instance_index, path); %#ok<AGROW>
        else
            states(index).state = 'file';
            states(index).content_bytes = bytes;
            states(index).content_size_octets = double(numel(bytes));
        end
    end
end
end

function tf = comparison_matches_targets(comparisons, candidates, states)
tf = numel(comparisons) == numel(states);
for index = 1:numel(comparisons)
    if ~tf
        return;
    end
    if strcmp(states(index).state, 'missing')
        expected = 'missing';
    elseif isequal(states(index).content_bytes, candidates(index).content_bytes)
        expected = 'same';
    else
        expected = 'different';
    end
    tf = strcmp(comparisons(index).target_state, expected) && ...
        comparisons(index).existing_size_octets == ...
        states(index).content_size_octets;
end
end

function [bytes, code] = read_required_file(path, unreadableCode, readCode)
bytes = zeros(1, 0, 'uint8');
code = '';
if isfolder(path) || ~isfile(path)
    code = unreadableCode;
    return;
end
fileID = fopen(path, 'rb');
if fileID < 0
    code = unreadableCode;
    return;
end
cleanup = onCleanup(@() fclose(fileID));
try
    bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
    [~, errorNumber] = ferror(fileID);
    if errorNumber ~= 0 && errorNumber ~= -4
        bytes = zeros(1, 0, 'uint8');
        code = readCode;
    end
catch
    bytes = zeros(1, 0, 'uint8');
    code = readCode;
end
clear cleanup
end

function tf = canonical_path(path)
tf = false;
if isempty(path)
    return;
end
try
    tf = strcmp(path, c2837x_block_normalize_absolute_path(path));
catch
end
end

function [valid, value] = text_value(rawValue, allowEmpty)
valid = (ischar(rawValue) && (isrow(rawValue) || isempty(rawValue))) || ...
    (isstring(rawValue) && isscalar(rawValue) && ~ismissing(rawValue));
if valid
    value = char(rawValue);
    valid = allowEmpty || ~isempty(value);
else
    value = '';
end
end

function summary = build_summary(snapshot)
comparisons = snapshot.comparison_baseline;
states = snapshot.target_states;
summary = empty_summary();
summary.instance_count = double(numel(snapshot.project.instances));
summary.candidate_count = double(numel(snapshot.candidates));
summary.dependency_count = double(numel(snapshot.dependencies));
summary.external_source_count = double(numel(snapshot.external_sources));
summary.target_file_count = double(sum(strcmp({states.state}, 'file')));
summary.missing_target_count = double(sum(strcmp({states.state}, 'missing')));
summary.create_count = double(sum(strcmp({comparisons.default_action}, 'create')));
summary.skip_count = double(sum(strcmp({comparisons.default_action}, 'skip')));
summary.replace_count = double(sum(strcmp({comparisons.default_action}, 'replace')));
summary.keep_count = double(sum(strcmp({comparisons.default_action}, 'keep')));
summary.dsp_root = snapshot.output_paths.dsp_root;
summary.sfun_root = snapshot.output_paths.sfun_root;
summary.interface_hashes = reshape([snapshot.interface_specs.interface_hash], 1, []);
end

function summary = empty_summary()
summary = struct('instance_count', 0, 'candidate_count', 0, ...
    'dependency_count', 0, 'external_source_count', 0, ...
    'target_file_count', 0, 'missing_target_count', 0, ...
    'create_count', 0, 'skip_count', 0, 'replace_count', 0, ...
    'keep_count', 0, 'dsp_root', '', 'sfun_root', '', ...
    'interface_hashes', zeros(1, 0, 'uint32'));
end

function comparisons = empty_comparisons()
comparisons = struct('target_path', {}, 'category', {}, 'owner', {}, ...
    'instance_index', {}, 'content_bytes', {}, 'content_size_octets', {}, ...
    'target_state', {}, 'default_action', {}, 'selected_action', {}, ...
    'action_mandatory', {}, 'existing_size_octets', {});
end

function tf = has_errors(issues)
tf = any(strcmp({issues.severity}, 'Error'));
end

function value = make_issue(severity, code, message, fieldPath, instanceIndex, filePath)
value = struct('severity', severity, 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', instanceIndex, ...
    'file_path', filePath);
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end
