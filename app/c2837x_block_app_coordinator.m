classdef c2837x_block_app_coordinator < handle
%C2837X_BLOCK_APP_COORDINATOR Coordinate App state with Phase 1 services.

    properties (SetAccess = private)
        Session
        PreviewStatus = 'none'
        PreviewSnapshot = struct()
        PreviewCandidates = struct([])
        PreviewDependencies = struct([])
        PreviewIssues = struct('severity', {}, 'code', {}, 'message', {}, ...
            'field_path', {}, 'instance_index', {}, 'file_path', {})
        PreviewSummary = struct()
        LastCommitResult = struct()
        EditorLegacyFileRisks = struct('action', {}, 'internal_name', {}, ...
            'reason', {})
    end

    properties (Dependent)
        LegacyFileRisks
    end

    properties (Access = private)
        PreviewProvider = []
    end

    methods
        function coordinator = c2837x_block_app_coordinator(session, provider)
            if nargin < 1 || ~isa(session, 'c2837x_block_project_session') || ...
                    ~isscalar(session)
                error('C2837xBlock:App:InvalidSession', ...
                    'Session must be a scalar project session.');
            end
            if nargin < 2
                provider = [];
            end
            if ~(isempty(provider) || ...
                    (isa(provider, 'function_handle') && isscalar(provider)))
                error('C2837xBlock:App:InvalidPreviewProvider', ...
                    'Preview provider must be empty or a scalar function handle.');
            end
            coordinator.Session = session;
            coordinator.PreviewProvider = provider;
        end

        function issues = validateProject(coordinator, mode)
            issues = c2837x_block_validate_project(coordinator.Session.Project, mode);
        end

        function risks = get.LegacyFileRisks(coordinator)
            risks = [coordinator.Session.LegacyFileRisks, ...
                coordinator.EditorLegacyFileRisks];
        end

        function [applied, issues] = updateProjectDraft(coordinator, draftProject)
            issues = c2837x_block_validate_project(draftProject, 'instant');
            coordinator.invalidatePreview();
            if any(strcmp({issues.code}, 'PROJECT_STRUCTURE_INVALID'))
                applied = false;
                return;
            end
            coordinator.captureEditorRenameRisks(draftProject);
            if ~has_errors(issues)
                draftProject = normalize_integer_types(draftProject);
            end
            coordinator.Session.updateProject(draftProject);
            applied = true;
        end

        function [saved, issues, requiresConfirmation] = ...
                saveProject(coordinator, filePath, allowValidationIssues)
            if ~islogical(allowValidationIssues) || ...
                    ~isscalar(allowValidationIssues)
                error('C2837xBlock:App:InvalidSaveInput', ...
                    'allowValidationIssues must be a logical scalar.');
            end
            issues = coordinator.validateProject('full');
            requiresConfirmation = any(ismember({issues.severity}, ...
                {'Error', 'Warning'}));
            saved = false;
            if requiresConfirmation && ~allowValidationIssues
                return;
            end
            try
                coordinator.Session.saveProject(filePath);
                saved = true;
            catch
                issues(end + 1) = app_issue('APP_PROJECT_SAVE_FAILED', ...
                    'The project could not be saved.', 'project', 0, char(string(filePath)));
            end
        end

        function [loaded, issues] = loadProject(coordinator, filePath)
            issues = empty_issues();
            try
                loaded = coordinator.Session.loadProject( ...
                    filePath, 'Don''t Save', '');
            catch cause
                loaded = false;
                if strcmp(cause.identifier, ...
                        'C2837xBlock:Project:UnsupportedVersion')
                    issues = app_issue('APP_PROJECT_VERSION_UNSUPPORTED', ...
                        ['The project uses a format or protocol version higher ' ...
                        'than this App supports. The current App cannot load ' ...
                        'it; use a newer version of the App.'], ...
                        'project', 0, char(string(filePath)));
                else
                    issues = app_issue('APP_PROJECT_LOAD_FAILED', ...
                        'The project could not be loaded.', ...
                        'project', 0, char(string(filePath)));
                end
                return;
            end
            if loaded
                coordinator.invalidatePreview();
                coordinator.LastCommitResult = struct();
                coordinator.EditorLegacyFileRisks = ...
                    struct('action', {}, 'internal_name', {}, 'reason', {});
            end
        end

        function updateProject(coordinator, project)
            coordinator.Session.updateProject(project);
            coordinator.invalidatePreview();
        end

        function addInstance(coordinator, changes)
            coordinator.Session.addInstance(changes);
            coordinator.invalidatePreview();
        end

        function updateInstance(coordinator, index, changes)
            coordinator.Session.updateInstance(index, changes);
            coordinator.invalidatePreview();
        end

        function switchIoDevice(coordinator, index, type)
            coordinator.Session.switchIoDevice(index, type);
            coordinator.invalidatePreview();
        end

        function copyInstance(coordinator, index, displayName, internalName, varargin)
            coordinator.Session.copyInstance( ...
                index, displayName, internalName, varargin{:});
            coordinator.invalidatePreview();
        end

        function renameInstance(coordinator, index, displayName, internalName)
            coordinator.Session.renameInstance(index, displayName, internalName);
            coordinator.invalidatePreview();
        end

        function deleteInstance(coordinator, index)
            coordinator.Session.deleteInstance(index);
            coordinator.invalidatePreview();
        end

        function [view, issues] = createPreview(coordinator)
            coordinator.clearPreviewData();
            issues = coordinator.validateProject('full');
            if has_errors(issues)
                [view, issues] = coordinator.blockPreview(issues);
                return;
            end
            if isempty(coordinator.PreviewProvider)
                issues(end + 1) = app_issue('APP_PREVIEW_PROVIDER_UNAVAILABLE', ...
                    'No preview provider is available.', 'preview_provider', 0, '');
                [view, issues] = coordinator.blockPreview(issues);
                return;
            end
            try
                [candidates, dependencies, providerIssues] = ...
                    coordinator.PreviewProvider(coordinator.Session.Project);
            catch
                issues(end + 1) = app_issue('APP_PREVIEW_PROVIDER_FAILED', ...
                    'The preview provider failed.', 'preview_provider', 0, '');
                [view, issues] = coordinator.blockPreview(issues);
                return;
            end
            if ~valid_provider_result(candidates, dependencies, providerIssues)
                issues(end + 1) = app_issue('APP_PREVIEW_PROVIDER_RESULT_INVALID', ...
                    'The preview provider returned an invalid result.', ...
                    'preview_provider', 0, '');
                [view, issues] = coordinator.blockPreview(issues);
                return;
            end
            issues = [issues providerIssues];
            if has_errors(issues)
                [view, issues] = coordinator.blockPreview(issues);
                return;
            end
            [snapshot, snapshotIssues, summary] = ...
                c2837x_block_create_preview_snapshot( ...
                coordinator.Session.Project, candidates, dependencies);
            invalidCodes = {'CANDIDATES_INVALID', 'SNAPSHOT_DEPENDENCIES_INVALID'};
            if any(ismember({snapshotIssues.code}, invalidCodes))
                issues(end + 1) = app_issue( ...
                    'APP_PREVIEW_PROVIDER_RESULT_INVALID', ...
                    'The preview provider returned an invalid result.', ...
                    'preview_provider', 0, '');
                [view, issues] = coordinator.blockPreview(issues);
                return;
            end
            issues = [issues snapshotIssues];
            if has_errors(issues) || isempty(fieldnames(snapshot))
                [view, issues] = coordinator.blockPreview(issues);
                return;
            end
            coordinator.PreviewStatus = 'valid';
            coordinator.PreviewSnapshot = snapshot;
            coordinator.PreviewCandidates = candidates;
            coordinator.PreviewDependencies = dependencies;
            coordinator.PreviewIssues = issues;
            coordinator.PreviewSummary = summary;
            view = coordinator.currentView();
        end

        function issues = setCandidateAction(coordinator, index, action)
            if ~strcmp(coordinator.PreviewStatus, 'valid')
                issues = app_issue('APP_PREVIEW_REQUIRED', ...
                    'A valid preview is required.', 'preview', 0, '');
                return;
            end
            comparisons = coordinator.PreviewSnapshot.comparison_baseline;
            if ~isnumeric(index) || ~isscalar(index) || index ~= fix(index) || ...
                    index < 1 || index > numel(comparisons)
                issues = app_issue('CANDIDATE_ACTION_INVALID', ...
                    'Candidate index is out of range.', 'comparison', 0, '');
                return;
            end
            comparisons(index).selected_action = char(string(action));
            issues = c2837x_block_validate_candidate_actions(comparisons);
            if ~has_errors(issues)
                coordinator.PreviewSnapshot.comparison_baseline(index).selected_action = ...
                    comparisons(index).selected_action;
            end
        end

        function [result, issues] = commitPreview(coordinator)
            if ~strcmp(coordinator.PreviewStatus, 'valid')
                result = struct();
                issues = app_issue('APP_PREVIEW_REQUIRED', ...
                    'A valid preview is required.', 'preview', 0, '');
                return;
            end
            [result, issues] = c2837x_block_commit_preview_snapshot( ...
                coordinator.PreviewSnapshot, coordinator.Session.Project, ...
                coordinator.PreviewCandidates, coordinator.PreviewDependencies);
            coordinator.LastCommitResult = result;
            if result.success
                coordinator.PreviewStatus = 'committed';
            else
                coordinator.PreviewStatus = 'stale';
            end
        end
    end

    methods (Access = private)
        function invalidatePreview(coordinator)
            if ~strcmp(coordinator.PreviewStatus, 'none')
                coordinator.PreviewStatus = 'stale';
            end
            coordinator.clearPreviewData();
        end

        function clearPreviewData(coordinator)
            coordinator.PreviewSnapshot = struct();
            coordinator.PreviewCandidates = struct([]);
            coordinator.PreviewDependencies = struct([]);
            coordinator.PreviewIssues = empty_issues();
            coordinator.PreviewSummary = struct();
        end

        function [view, issues] = blockPreview(coordinator, issues)
            coordinator.PreviewStatus = 'blocked';
            coordinator.PreviewIssues = issues;
            view = coordinator.currentView();
        end

        function view = currentView(coordinator)
            comparisons = empty_comparisons();
            if isfield(coordinator.PreviewSnapshot, 'comparison_baseline')
                comparisons = coordinator.PreviewSnapshot.comparison_baseline;
            end
            view = struct('status', coordinator.PreviewStatus, ...
                'snapshot', coordinator.PreviewSnapshot, ...
                'comparisons', comparisons, ...
                'summary', coordinator.PreviewSummary, ...
                'legacy_file_risks', coordinator.LegacyFileRisks);
        end

        function captureEditorRenameRisks(coordinator, draftProject)
            current = coordinator.Session.Project.instances;
            drafts = draftProject.instances;
            for index = 1:min(numel(current), numel(drafts))
                oldName = char(current(index).internal_name);
                newName = char(drafts(index).internal_name);
                if ~strcmp(oldName, newName) && is_general_identifier(oldName)
                    risk = struct('action', 'rename', 'internal_name', oldName, ...
                        'reason', ['Internal name changed; old generated files ' ...
                        'may remain.']);
                    existing = coordinator.EditorLegacyFileRisks;
                    duplicate = ~isempty(existing) && any(strcmp( ...
                        {existing.action}, risk.action) & strcmp( ...
                        {existing.internal_name}, risk.internal_name));
                    if ~duplicate
                        coordinator.EditorLegacyFileRisks(end + 1) = risk;
                    end
                end
            end
        end
    end
end

function valid = valid_provider_result(candidates, dependencies, issues)
valid = valid_issues(issues) && isstruct(candidates) && isstruct(dependencies);
if ~valid
    return;
end
try
    candidateIssues = c2837x_block_validate_candidate_files(candidates);
    valid = ~any(strcmp({candidateIssues.code}, 'CANDIDATES_INVALID')) && ...
        all(isfield(dependencies, ...
        {'role', 'identity', 'source_kind', 'source_path', 'content_bytes'}));
catch
    valid = false;
end
end

function valid = valid_issues(issues)
required = {'severity', 'code', 'message', 'field_path', ...
    'instance_index', 'file_path'};
valid = isstruct(issues) && isequal(sort(fieldnames(issues)), sort(required(:)));
if ~valid || isempty(issues)
    return;
end
for index = 1:numel(issues)
    issue = issues(index);
    try
        valid = valid_text(issue.severity, false) && ...
            any(strcmp(char(issue.severity), {'Error', 'Warning', 'Information'})) && ...
            valid_text(issue.code, false) && valid_text(issue.message, true) && ...
            valid_text(issue.field_path, true) && valid_text(issue.file_path, true) && ...
            isnumeric(issue.instance_index) && isreal(issue.instance_index) && ...
            isscalar(issue.instance_index) && isfinite(issue.instance_index) && ...
            issue.instance_index >= 0 && ...
            issue.instance_index == fix(issue.instance_index);
    catch
        valid = false;
    end
    if ~valid
        return;
    end
end
end

function valid = valid_text(value, allowEmpty)
valid = (ischar(value) && (isrow(value) || isempty(value))) || ...
    (isstring(value) && isscalar(value) && ~ismissing(value));
if valid && ~allowEmpty
    valid = ~isempty(char(value));
end
end

function project = normalize_integer_types(project)
for index = 1:numel(project.instances)
    type = char(project.instances(index).iodevice.type);
    if strcmp(type, 'w5300_tcp')
        project.instances(index).iodevice.settings.socket_number = ...
            uint16(project.instances(index).iodevice.settings.socket_number);
        project.instances(index).iodevice.settings.tcp_port = ...
            uint16(project.instances(index).iodevice.settings.tcp_port);
    elseif strcmp(type, 'sci')
        project.instances(index).iodevice.settings.baud = ...
            uint32(project.instances(index).iodevice.settings.baud);
    end
    project.instances(index).max_payload_size_bytes = ...
        uint32(project.instances(index).max_payload_size_bytes);
end
end

function valid = is_general_identifier(value)
valid = ~isempty(regexp(value, '^[A-Za-z][A-Za-z0-9_]*$', 'once'));
end

function tf = has_errors(issues)
tf = ~isempty(issues) && any(strcmp({issues.severity}, 'Error'));
end

function issue = app_issue(code, message, fieldPath, instanceIndex, filePath)
issue = struct('severity', 'Error', 'code', code, 'message', message, ...
    'field_path', fieldPath, 'instance_index', double(instanceIndex), ...
    'file_path', filePath);
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end

function comparisons = empty_comparisons()
comparisons = struct('target_path', {}, 'category', {}, 'owner', {}, ...
    'instance_index', {}, 'content_bytes', {}, 'content_size_octets', {}, ...
    'target_state', {}, 'default_action', {}, 'selected_action', {}, ...
    'action_mandatory', {}, 'existing_size_octets', {});
end
