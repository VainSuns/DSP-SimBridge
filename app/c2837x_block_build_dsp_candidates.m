function [candidates, dependencies, issues] = ...
        c2837x_block_build_dsp_candidates(project)
%C2837X_BLOCK_BUILD_DSP_CANDIDATES Build deterministic public Core candidates.

model = c2837x_block_build_dsp_output_model(project);
coreFiles = model.files([model.files.candidate_available]);
prototype = struct('target_path', '', 'category', '', 'owner', '', ...
    'instance_index', 0, 'content_bytes', zeros(1, 0, 'uint8'));
definitions = repmat(prototype, 1, numel(coreFiles));
for index = 1:numel(coreFiles)
    file = coreFiles(index);
    definitions(index) = struct('target_path', file.target_path, ...
        'category', file.category, 'owner', file.owner, ...
        'instance_index', file.instance_index, ...
        'content_bytes', normalized_core_bytes(file.source_path));
end
candidates = c2837x_block_build_candidate_files(definitions);
dependencies = build_dependencies(coreFiles);
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end

function dependencies = build_dependencies(coreFiles)
appRoot = fileparts(mfilename('fullpath'));
prototype = struct('role', '', 'identity', '', 'source_kind', 'file', ...
    'source_path', '', 'content_bytes', zeros(1, 0, 'uint8'));
dependencies = repmat(prototype, 1, numel(coreFiles) + 2);
dependencies(1) = dependency('generator_template', ...
    'dsp-generator:build-output-model', ...
    fullfile(appRoot, 'c2837x_block_build_dsp_output_model.m'));
dependencies(2) = dependency('generator_template', ...
    'dsp-generator:build-core-candidates', [mfilename('fullpath') '.m']);
for index = 1:numel(coreFiles)
    dependencies(index + 2) = dependency('core_source', ...
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
