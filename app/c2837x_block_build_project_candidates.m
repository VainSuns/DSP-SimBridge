function [candidates, dependencies, issues] = ...
        c2837x_block_build_project_candidates(project)
%C2837X_BLOCK_BUILD_PROJECT_CANDIDATES Build all project candidates.

[dspCandidates, dspDependencies, dspIssues] = ...
    c2837x_block_build_dsp_candidates(project);
[sfunCandidates, sfunDependencies, sfunIssues] = ...
    c2837x_block_build_sfun_candidates(project);
candidates = [dspCandidates sfunCandidates];
[dependencies, mergeIssues] = merge_dependencies( ...
    [dspDependencies sfunDependencies]);
projectIssues = c2837x_block_validate_project(project, 'instant');
rootCodes = {'OUTPUT_ROOTS_EQUAL', 'DSP_ROOT_CONTAINS_SFUN_ROOT', ...
    'SFUN_ROOT_CONTAINS_DSP_ROOT'};
projectIssues = projectIssues(ismember({projectIssues.code}, rootCodes));
issues = [dspIssues sfunIssues mergeIssues ...
    c2837x_block_validate_candidate_files(candidates) projectIssues];
end

function [merged, issues] = merge_dependencies(input)
merged = input([]);
issues = empty_issues();
for index = 1:numel(input)
    dependency = input(index);
    identityMatch = find(strcmp({merged.identity}, dependency.identity), 1);
    pathMatch = [];
    if ~isempty(dependency.source_path)
        pathMatch = find(strcmp({merged.source_path}, dependency.source_path), 1);
    end
    if ~isempty(identityMatch) && ~same_source(merged(identityMatch), dependency)
        issues(end + 1) = issue('PROJECT_DEPENDENCY_IDENTITY_CONFLICT', ...
            'A dependency identity refers to different sources.', index, dependency); %#ok<AGROW>
        continue;
    end
    if ~isempty(pathMatch)
        if ~strcmp(merged(pathMatch).source_kind, dependency.source_kind)
            issues(end + 1) = issue('PROJECT_DEPENDENCY_KIND_CONFLICT', ...
                'A dependency path has different source kinds.', index, dependency); %#ok<AGROW>
        elseif ~same_content(merged(pathMatch), dependency)
            issues(end + 1) = issue('PROJECT_DEPENDENCY_CONTENT_CONFLICT', ...
                'A dependency source has conflicting content.', index, dependency); %#ok<AGROW>
        end
        continue;
    end
    if isempty(identityMatch)
        merged(end + 1) = dependency; %#ok<AGROW>
    end
end
end

function tf = same_source(first, second)
tf = strcmp(first.source_kind, second.source_kind) && ...
    strcmp(first.source_path, second.source_path) && same_content(first, second);
end

function tf = same_content(first, second)
if strcmp(first.source_kind, 'memory') || strcmp(second.source_kind, 'memory')
    tf = isequal(first.content_bytes, second.content_bytes);
    return;
end
tf = isequal(read_bytes(first.source_path), read_bytes(second.source_path));
end

function bytes = read_bytes(path)
file = fopen(path, 'rb');
if file < 0
    bytes = [];
    return;
end
cleanup = onCleanup(@() fclose(file));
bytes = reshape(fread(file, Inf, '*uint8'), 1, []);
clear cleanup
end

function value = issue(code, message, index, dependency)
value = struct('severity', 'Error', 'code', code, 'message', message, ...
    'field_path', sprintf('dependencies(%u)', index), ...
    'instance_index', 0, 'file_path', dependency.source_path);
end

function issues = empty_issues()
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end
