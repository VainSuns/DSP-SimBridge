function [candidates, dependencies, issues] = ...
        c2837x_block_build_dsp_candidates(project)
%C2837X_BLOCK_BUILD_DSP_CANDIDATES Build deterministic DSP candidates.

algorithmFiles = c2837x_block_render_dsp_algorithm_files(project);
model = c2837x_block_build_dsp_output_model(project);
availableFiles = model.files([model.files.candidate_available]);
prototype = struct('target_path', '', 'category', '', 'owner', '', ...
    'instance_index', 0, 'content_bytes', zeros(1, 0, 'uint8'));
definitions = repmat(prototype, 1, numel(availableFiles));
rendered = c2837x_block_render_dsp_project_files(project);
projectBytes = {rendered.header_bytes, rendered.source_bytes};
projectIndex = 0;
instanceFiles = c2837x_block_render_dsp_instance_config_files(project);
ioFiles = c2837x_block_render_dsp_instance_io_files(project);
for index = 1:numel(availableFiles)
    file = availableFiles(index);
    switch file.file_scope
        case 'core'
            contentBytes = normalized_core_bytes(file.source_path);
        case 'project'
            projectIndex = projectIndex + 1;
            contentBytes = projectBytes{projectIndex};
        case 'instance'
            contentBytes = instance_bytes(file, instanceFiles, ioFiles, algorithmFiles);
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
dependencies = build_dependencies(project, ...
    model.files(strcmp({model.files.file_scope}, 'core')));
issues = struct('severity', {}, 'code', {}, 'message', {}, ...
    'field_path', {}, 'instance_index', {}, 'file_path', {});
end

function dependencies = build_dependencies(project, coreFiles)
appRoot = fileparts(mfilename('fullpath'));
prototype = struct('role', '', 'identity', '', 'source_kind', 'file', ...
    'source_path', '', 'content_bytes', zeros(1, 0, 'uint8'));
templates = { ...
    'build-output-model', 'c2837x_block_build_dsp_output_model.m'; ...
    'build-candidates', 'c2837x_block_build_dsp_candidates.m'; ...
    'render-project-files', 'c2837x_block_render_dsp_project_files.m'; ...
    'resolve-iodevice-definition', 'c2837x_block_get_iodevice_definition.m'; ...
    'render-instance-config-files', 'c2837x_block_render_dsp_instance_config_files.m'; ...
    'build-wire-layout', 'c2837x_block_build_dsp_wire_layout.m'; ...
    'render-instance-io-files', 'c2837x_block_render_dsp_instance_io_files.m'; ...
    'render-algorithm-files', 'c2837x_block_render_dsp_algorithm_files.m'; ...
    'resolve-external-algorithm-source', 'c2837x_block_resolve_external_algorithm_source.m'; ...
    'build-instance-c-names', 'c2837x_block_build_instance_c_names.m'; ...
    'build-interface-hash', 'c2837x_block_build_interface_hash.m'; ...
    'build-interface-text', 'c2837x_block_build_interface_text.m'; ...
    'crc32', 'c2837x_block_crc32.m'};
definitionTypes = {};
definitionPaths = {};
for index = 1:numel(project.instances)
    [definition, found, sourcePath] = c2837x_block_get_iodevice_definition( ...
        project.instances(index).iodevice.type);
    if ~found
        error('C2837xBlock:IoDevice:Unsupported', ...
            'Cannot build dependencies for unsupported IoDevice type "%s".', ...
            char(project.instances(index).iodevice.type));
    end
    if ~any(strcmp(definitionTypes, definition.type))
        definitionTypes{end + 1} = definition.type; %#ok<AGROW>
        definitionPaths{end + 1} = sourcePath; %#ok<AGROW>
    end
end
if any(strcmp(definitionTypes, 'sci'))
    templates = [templates; ...
        {'sci-baud-service', 'c2837x_block_calculate_sci_baud.m'; ...
         'sci-clock-service', 'c2837x_block_get_sci_clock_config.m'; ...
         'sci-capability-loader', 'c2837x_block_load_device_capability.m'; ...
         'sci-capability-data', fullfile('capabilities', ...
         'TMS320F28377D_PTP.json')}]; %#ok<AGROW>
end
templateCount = size(templates, 1);
definitionCount = numel(definitionTypes);
dependencies = repmat(prototype, 1, ...
    numel(coreFiles) + templateCount + definitionCount);
for index = 1:size(templates, 1)
    dependencies(index) = dependency('generator_template', ...
        ['dsp-generator:' templates{index, 1}], fullfile(appRoot, templates{index, 2}));
end
for index = 1:definitionCount
    dependencies(templateCount + index) = dependency('generator_template', ...
        ['dsp-generator:iodevice-definition:' definitionTypes{index}], ...
        definitionPaths{index});
end
for index = 1:numel(coreFiles)
    dependencies(index + templateCount + definitionCount) = dependency('core_source', ...
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

function bytes = instance_bytes(file, configFiles, ioFiles, algorithmFiles)
configMatches = find([configFiles.instance_index] == file.instance_index);
ioMatches = find([ioFiles.instance_index] == file.instance_index);
algorithmMatches = find([algorithmFiles.instance_index] == file.instance_index);
if numel(configMatches) ~= 1 || numel(ioMatches) ~= 1 || ...
        numel(algorithmMatches) ~= 1
    error('C2837xBlock:Generation:InstanceRenderMismatch', ...
        'Expected exactly one rendered result for instance %u.', ...
        file.instance_index);
end
config = configFiles(configMatches);
io = ioFiles(ioMatches);
algorithm = algorithmFiles(algorithmMatches);
if ~strcmp(config.internal_name, io.internal_name) || ...
        ~strcmp(config.internal_name, algorithm.internal_name)
    error('C2837xBlock:Generation:InstanceRenderMismatch', ...
        'Rendered instance names do not match for instance %u.', ...
        file.instance_index);
end
expectedName = config.internal_name;
switch file.relative_path
    case ['inc/' expectedName '_config.h']
        bytes = config.config_header_bytes;
    case ['inc/' expectedName '_user_config.h']
        bytes = config.user_config_header_bytes;
    case ['inc/' expectedName '_algorithm.h']
        bytes = algorithm.algorithm_header_bytes;
    case ['src/' expectedName '_config.c']
        bytes = config.config_source_bytes;
    case ['src/' expectedName '_io.c']
        bytes = io.io_source_bytes;
    case ['src/' expectedName '_algorithm.c']
        if ~algorithm.algorithm_source_available
            error('C2837xBlock:Generation:InstanceRenderMismatch', ...
                'Algorithm source is unavailable for "%s".', file.relative_path);
        end
        bytes = algorithm.algorithm_source_bytes;
    otherwise
        error('C2837xBlock:Generation:InstanceRenderMismatch', ...
            'No rendered instance file matches "%s".', file.relative_path);
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
