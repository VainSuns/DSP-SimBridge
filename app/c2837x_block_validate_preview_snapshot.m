function [isValid, issues, currentSummary] = ...
        c2837x_block_validate_preview_snapshot( ...
        snapshot, project, candidates, dependencies)
%C2837X_BLOCK_VALIDATE_PREVIEW_SNAPSHOT Check a preview against current state.

issues = empty_issues();
currentSummary = empty_summary();
if ~valid_snapshot(snapshot)
    issues = make_issue('SNAPSHOT_INVALID', ...
        'Snapshot does not use the supported fixed model.', 'snapshot');
    isValid = false;
    return;
end

[current, currentIssues, currentSummary] = ...
    c2837x_block_create_preview_snapshot(project, candidates, dependencies);
issues = [issues currentIssues];
if any(strcmp({issues.severity}, 'Error'))
    isValid = false;
    return;
end

if ~isequaln(snapshot.project, current.project)
    issues(end + 1) = changed_issue('SNAPSHOT_PROJECT_CHANGED', ...
        'Project configuration changed.', 'project');
end
if ~isequaln(snapshot.output_paths, current.output_paths)
    issues(end + 1) = changed_issue('SNAPSHOT_OUTPUT_PATH_CHANGED', ...
        'Output paths changed.', 'project.output');
end
if ~isequaln(snapshot.interface_specs, current.interface_specs)
    issues(end + 1) = changed_issue('SNAPSHOT_INTERFACE_CHANGED', ...
        'Interface Hash specification changed.', 'interface_specs');
end
if ~isequaln(snapshot.dependencies, current.dependencies)
    issues(end + 1) = changed_issue('SNAPSHOT_DEPENDENCY_CHANGED', ...
        'Template or Core dependency content changed.', 'dependencies');
end
if ~isequaln(snapshot.external_sources, current.external_sources)
    issues(end + 1) = changed_issue('SNAPSHOT_EXTERNAL_SOURCE_CHANGED', ...
        'External algorithm source content changed.', 'external_sources');
end
if ~isequaln(snapshot.candidates, current.candidates)
    issues(end + 1) = changed_issue('SNAPSHOT_CANDIDATE_CHANGED', ...
        'Candidate files changed.', 'candidates');
end
if ~comparisons_equal(snapshot.comparison_baseline, ...
        current.comparison_baseline)
    issues(end + 1) = changed_issue('SNAPSHOT_COMPARISON_CHANGED', ...
        'Candidate comparison baseline changed.', 'comparison_baseline');
end
if ~isequaln(snapshot.target_states, current.target_states)
    issues(end + 1) = changed_issue('SNAPSHOT_TARGET_CHANGED', ...
        'Candidate target content or type changed.', 'target_states');
end
isValid = ~any(strcmp({issues.severity}, 'Error'));
end

function tf = valid_snapshot(snapshot)
required = {'schema_version', 'project', 'output_paths', ...
    'interface_specs', 'dependencies', 'external_sources', 'candidates', ...
    'comparison_baseline', 'target_states'};
tf = isstruct(snapshot) && isscalar(snapshot) && exact_fields(snapshot, required) && ...
    isa(snapshot.schema_version, 'uint16') && isscalar(snapshot.schema_version) && ...
    snapshot.schema_version == uint16(1) && ...
    isstruct(snapshot.project) && isscalar(snapshot.project) && ...
    valid_output_paths(snapshot.output_paths) && ...
    valid_interfaces(snapshot.interface_specs) && ...
    valid_dependencies(snapshot.dependencies) && ...
    valid_external_sources(snapshot.external_sources) && ...
    valid_candidates(snapshot.candidates) && ...
    valid_comparisons(snapshot.comparison_baseline) && ...
    valid_target_states(snapshot.target_states);
end

function tf = valid_output_paths(value)
tf = isstruct(value) && isscalar(value) && ...
    exact_fields(value, {'dsp_root', 'sfun_root'}) && ...
    valid_text(value.dsp_root, true) && valid_text(value.sfun_root, true);
end

function tf = valid_interfaces(values)
required = {'instance_index', 'internal_name', 'canonical_text', 'interface_hash'};
if ~isstruct(values) || ~exact_fields(values, required)
    tf = false;
    return;
end
tf = true;
for index = 1:numel(values)
    value = values(index);
    tf = tf && valid_integer(value.instance_index, 1) && ...
        valid_text(value.internal_name, false) && ...
        valid_text(value.canonical_text, true) && ...
        isa(value.interface_hash, 'uint32') && isscalar(value.interface_hash);
end
end

function tf = valid_dependencies(values)
required = {'role', 'identity', 'source_kind', 'source_path', ...
    'content_bytes', 'content_size_octets'};
if ~isstruct(values) || ~exact_fields(values, required)
    tf = false;
    return;
end
tf = true;
identities = cell(1, numel(values));
roles = cell(1, numel(values));
for index = 1:numel(values)
    value = values(index);
    roles{index} = text_or_empty(value.role);
    identities{index} = text_or_empty(value.identity);
    kind = text_or_empty(value.source_kind);
    tf = tf && any(strcmp(roles{index}, {'generator_template', 'core_source'})) && ...
        ~isempty(identities{index}) && any(strcmp(kind, {'memory', 'file'})) && ...
        valid_text(value.source_path, true) && valid_bytes(value.content_bytes) && ...
        valid_size(value.content_size_octets, value.content_bytes);
    if strcmp(kind, 'memory')
        tf = tf && isempty(value.source_path);
    elseif strcmp(kind, 'file')
        tf = tf && ~isempty(value.source_path);
    end
end
tf = tf && numel(unique(identities)) == numel(identities) && ...
    any(strcmp(roles, 'generator_template')) && any(strcmp(roles, 'core_source'));
end

function tf = valid_external_sources(values)
required = {'instance_index', 'mode', 'source_path', ...
    'content_bytes', 'content_size_octets'};
if ~isstruct(values) || ~exact_fields(values, required)
    tf = false;
    return;
end
tf = true;
for index = 1:numel(values)
    value = values(index);
    tf = tf && valid_integer(value.instance_index, 1) && ...
        any(strcmp(text_or_empty(value.mode), ...
        {'external_copy', 'external_reference'})) && ...
        valid_text(value.source_path, false) && valid_bytes(value.content_bytes) && ...
        valid_size(value.content_size_octets, value.content_bytes);
end
end

function tf = valid_candidates(values)
required = {'target_path', 'category', 'owner', 'instance_index', ...
    'content_bytes', 'content_size_octets'};
if ~isstruct(values) || ~exact_fields(values, required)
    tf = false;
    return;
end
tf = true;
for index = 1:numel(values)
    value = values(index);
    tf = tf && valid_text(value.target_path, false) && ...
        any(strcmp(text_or_empty(value.category), ...
        {'auto_generated', 'core', 'user'})) && ...
        valid_text(value.owner, false) && valid_integer(value.instance_index, 0) && ...
        valid_bytes(value.content_bytes) && ...
        valid_size(value.content_size_octets, value.content_bytes);
end
end

function tf = valid_comparisons(values)
required = {'target_path', 'category', 'owner', 'instance_index', ...
    'content_bytes', 'content_size_octets', 'target_state', ...
    'default_action', 'selected_action', 'action_mandatory', ...
    'existing_size_octets'};
if ~isstruct(values) || ~exact_fields(values, required)
    tf = false;
    return;
end
tf = true;
for index = 1:numel(values)
    value = values(index);
    tf = tf && valid_text(value.target_path, false) && ...
        any(strcmp(text_or_empty(value.category), ...
        {'auto_generated', 'core', 'user'})) && ...
        valid_text(value.owner, false) && valid_integer(value.instance_index, 0) && ...
        valid_bytes(value.content_bytes) && ...
        valid_size(value.content_size_octets, value.content_bytes) && ...
        any(strcmp(text_or_empty(value.target_state), ...
        {'missing', 'same', 'different'})) && ...
        any(strcmp(text_or_empty(value.default_action), ...
        {'create', 'skip', 'replace', 'keep'})) && ...
        any(strcmp(text_or_empty(value.selected_action), ...
        {'create', 'skip', 'replace', 'keep'})) && ...
        islogical(value.action_mandatory) && isscalar(value.action_mandatory) && ...
        valid_integer(value.existing_size_octets, 0);
end
end

function tf = valid_target_states(values)
required = {'target_path', 'state', 'content_bytes', 'content_size_octets'};
if ~isstruct(values) || ~exact_fields(values, required)
    tf = false;
    return;
end
tf = true;
for index = 1:numel(values)
    value = values(index);
    state = text_or_empty(value.state);
    tf = tf && valid_text(value.target_path, false) && ...
        any(strcmp(state, {'missing', 'file'})) && ...
        valid_bytes(value.content_bytes) && ...
        valid_size(value.content_size_octets, value.content_bytes);
    if strcmp(state, 'missing')
        tf = tf && isempty(value.content_bytes) && value.content_size_octets == 0;
    end
end
end

function tf = comparisons_equal(first, second)
if numel(first) ~= numel(second)
    tf = false;
    return;
end
for index = 1:numel(first)
    first(index).selected_action = first(index).default_action;
    second(index).selected_action = second(index).default_action;
end
tf = isequaln(first, second);
end

function tf = exact_fields(value, expected)
tf = isequal(sort(fieldnames(value)), sort(expected(:)));
end

function tf = valid_text(value, allowEmpty)
tf = (ischar(value) && (isrow(value) || isempty(value))) || ...
    (isstring(value) && isscalar(value) && ~ismissing(value));
if tf && ~allowEmpty
    tf = ~isempty(char(value));
end
end

function value = text_or_empty(rawValue)
if valid_text(rawValue, true)
    value = char(rawValue);
else
    value = '';
end
end

function tf = valid_bytes(value)
tf = isa(value, 'uint8') && ismatrix(value) && size(value, 1) == 1;
end

function tf = valid_size(value, bytes)
tf = valid_integer(value, 0) && value == numel(bytes);
end

function tf = valid_integer(value, minimum)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= minimum && value == fix(value);
end

function value = changed_issue(code, message, fieldPath)
value = make_issue(code, message, fieldPath);
end

function value = make_issue(code, message, fieldPath)
value = struct('severity', 'Error', 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', 0, 'file_path', '');
end

function summary = empty_summary()
summary = struct('instance_count', 0, 'candidate_count', 0, ...
    'dependency_count', 0, 'external_source_count', 0, ...
    'target_file_count', 0, 'missing_target_count', 0, ...
    'create_count', 0, 'skip_count', 0, 'replace_count', 0, ...
    'keep_count', 0, 'dsp_root', '', 'sfun_root', '', ...
    'interface_hashes', zeros(1, 0, 'uint32'));
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end
