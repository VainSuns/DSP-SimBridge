function [candidates, dependencies, issues] = ...
        c2837x_block_build_dsp_candidates(project)
%C2837X_BLOCK_BUILD_DSP_CANDIDATES Build deterministic DSP candidates.

model = c2837x_block_build_dsp_output_model(project);
availableFiles = model.files([model.files.candidate_available]);
prototype = struct('target_path', '', 'category', '', 'owner', '', ...
    'instance_index', 0, 'content_bytes', zeros(1, 0, 'uint8'));
definitions = repmat(prototype, 1, numel(availableFiles));
rendered = c2837x_block_render_dsp_project_files(project);
projectBytes = {rendered.header_bytes, rendered.source_bytes};
projectIndex = 0;
for index = 1:numel(availableFiles)
    file = availableFiles(index);
    switch file.file_scope
        case 'core'
            contentBytes = normalized_core_bytes(file.source_path);
        case 'project'
            projectIndex = projectIndex + 1;
            contentBytes = projectBytes{projectIndex};
        otherwise
            error('C2837xBlock:Generation:UnavailableFileScope', ...
                'Candidate generation is unavailable for file scope "%s".', ...
                file.file_scope);
    end
    definitions(index) = struct('target_path', file.target_path, ...
        'category', file.category, 'owner', file.owner, ...
        'instance_index', file.instance_index, ...
        'content_bytes', contentBytes);
end
candidates = c2837x_block_build_candidate_files(definitions);
dependencies = build_dependencies(model.files(strcmp({model.files.file_scope}, 'core')));
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end

function dependencies = build_dependencies(coreFiles)
appRoot = fileparts(mfilename('fullpath'));
prototype = struct('role', '', 'identity', '', 'source_kind', 'file', ...
    'source_path', '', 'content_bytes', zeros(1, 0, 'uint8'));
templates = { ...
    'build-output-model', 'c2837x_block_build_dsp_output_model.m'; ...
    'build-candidates', 'c2837x_block_build_dsp_candidates.m'; ...
    'render-project-files', 'c2837x_block_render_dsp_project_files.m'; ...
    'resolve-iodevice-definition', 'c2837x_block_get_iodevice_definition.m'; ...
    'w5300-tcp-definition', 'c2837x_block_iodevice_w5300_tcp_definition.m'};
dependencies = repmat(prototype, 1, numel(coreFiles) + size(templates, 1));
for index = 1:size(templates, 1)
    dependencies(index) = dependency('generator_template', ...
        ['dsp-generator:' templates{index, 1}], fullfile(appRoot, templates{index, 2}));
end
for index = 1:numel(coreFiles)
    dependencies(index + size(templates, 1)) = dependency('core_source', ...
        ['dsp-core-source:' coreFiles(index).relative_path], ...
        coreFiles(index).source_path);
end

    function value = dependency(role, identity, sourcePath)
        value = struct('role', role, 'identity', identity, ...
            'source_kind', 'file', ...
            'source_path', c2837x_block_normalize_absolute_path(sourcePath), ...
            'content_bytes', zeros(1, 0, 'uint8'));
    end
end

function bytes = normalized_core_bytes(path)
fileID = fopen(path, 'rb');
if fileID < 0
    error('C2837xBlock:Generation:CoreSourceUnreadable', ...
        'Core source could not be read: %s', path);
end
cleanup = onCleanup(@() fclose(fileID));
raw = reshape(fread(fileID, Inf, '*uint8'), 1, []);
clear cleanup

text = native2unicode(raw, 'UTF-8');
if ~isempty(text) && text(1) == char(65279)
    text(1) = [];
end
text = strrep(text, [char(13) newline], newline);
text = strrep(text, char(13), newline);
while ~isempty(text) && text(end) == newline
    text(end) = [];
end
if ~contains(text, 'DSP-SimBridge core source')
    text = ['/* DSP-SimBridge core source */' newline text];
end
text = [text newline];
bytes = reshape(uint8(unicode2native(text, 'UTF-8')), 1, []);
end
