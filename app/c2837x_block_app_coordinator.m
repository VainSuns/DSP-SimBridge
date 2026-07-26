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

        function copyInstance(coordinator, index, displayName, internalName, socket, port)
            coordinator.Session.copyInstance(index, displayName, internalName, socket, port);
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
                'legacy_file_risks', coordinator.Session.LegacyFileRisks);
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
valid = isstruct(issues) && all(isfield(issues, required));
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
