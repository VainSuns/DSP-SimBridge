function rendered = c2837x_block_render_dsp_project_files(project)
%C2837X_BLOCK_RENDER_DSP_PROJECT_FILES Render deterministic project C files.

c2837x_block_validate_project_structure(project);
model = c2837x_block_build_dsp_output_model(project);
platformConfig = model.platform_config;
header = sprintf([ ...
    '#ifndef C2837X_BLOCK_PROJECT_H\n' ...
    '#define C2837X_BLOCK_PROJECT_H\n\n' ...
    '/*\n' ...
    ' * AUTO-GENERATED FILE\n' ...
    ' * Manual changes will be overwritten.\n' ...
    ' */\n\n' ...
    '#define C2837X_BLOCK_PLATFORM_HAS_W5300  %uu\n' ...
    '#define C2837X_BLOCK_PLATFORM_HAS_SCI    %uu\n' ...
    '#define C2837X_BLOCK_PLATFORM_CONFIG_EXTERN\n' ...
    '#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION  2u\n' ...
    '#include "c2837x_block.h"\n\n'], ...
    double(platformConfig.use_w5300), ...
    double(~isempty(platformConfig.sci_descriptors)));
source = [ ...
    '#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION  2u' newline ...
    '#include "c2837x_block_internal.h"' newline ...
    '#include "c2837x_block_platform.h"'];
source = [source newline];
supports = {};
includes = {};
sourceSupport = {};
for index = 1:numel(project.instances)
    [definition, found] = c2837x_block_get_iodevice_definition( ...
        project.instances(index).iodevice.type);
    if ~found
        error('C2837xBlock:IoDevice:Unsupported', ...
            'Cannot render unsupported IoDevice type "%s".', ...
            char(project.instances(index).iodevice.type));
    end
    if ~any(strcmp(supports, definition.type))
        support = definition.render_project_support(project);
        supports{end + 1} = definition.type; %#ok<AGROW>
        includes = [includes support.includes]; %#ok<AGROW>
        sourceSupport{numel(supports)} = support.source; %#ok<AGROW>
    end
end
includes = unique(includes, 'stable');
for index = 1:numel(includes)
    source = [source sprintf('#include "%s"\n', includes{index})]; %#ok<AGROW>
end
for index = 1:numel(project.instances)
    name = valid_name(project.instances(index).internal_name);
    header = [header sprintf('extern C2837xBlock g_%s;\n', name)]; %#ok<AGROW>
end
header = [header sprintf('\n#endif /* C2837X_BLOCK_PROJECT_H */\n')];
source = [source newline];
source = [source platform_config_source(platformConfig) newline]; %#ok<AGROW>
for index = 1:numel(sourceSupport)
    source = [source sourceSupport{index} newline]; %#ok<AGROW>
end
for index = 1:numel(project.instances)
    name = valid_name(project.instances(index).internal_name);
    source = [source sprintf([ ...
        'extern const C2837xBlock_Config\n' ...
        '    c2837x_block_%s_config;\n\n'], name)]; %#ok<AGROW>
end
for index = 1:numel(project.instances)
    name = valid_name(project.instances(index).internal_name);
    source = [source sprintf([ ...
        'C2837xBlock g_%s =\n' ...
        '    C2837X_BLOCK_INSTANCE_INITIALIZER(\n' ...
        '        &c2837x_block_%s_config);\n'], name, name)]; %#ok<AGROW>
    if index < numel(project.instances)
        source = [source newline]; %#ok<AGROW>
    end
end
rendered = struct('header_bytes', text_bytes(header), ...
    'source_bytes', text_bytes(source));
end

function text = platform_config_source(platformConfig)
descriptorCount = numel(platformConfig.sci_descriptors);
useW5300 = double(platformConfig.use_w5300);
fields = {};
if useW5300 ~= 0
    fields{end + 1} = '    1u'; %#ok<AGROW>
end
if descriptorCount ~= 0
    fields{end + 1} = sprintf( ...
        '    { c2837x_block_project_sci_descriptors, %uu }', ...
        descriptorCount); %#ok<AGROW>
end
text = sprintf([ ...
    '%s' ...
    'const C2837xBlock_PlatformConfig\n' ...
    '    c2837x_block_platform_config =\n' ...
    '{\n' ...
    '%s\n' ...
    '};\n'], ...
    sci_declaration(platformConfig), strjoin(fields, sprintf(',\n')));
end

function text = sci_declaration(platformConfig)
if isempty(platformConfig.sci_descriptors)
    text = '';
else
    text = sprintf([ ...
        'extern const C2837xBlock_SciDescriptor\n' ...
        '    c2837x_block_project_sci_descriptors[];\n\n']);
end
end

function name = valid_name(value)
[valid, message] = c2837x_block_validate_name(value, {});
if ~valid
    error('C2837xBlock:DspProject:InvalidInstanceName', '%s', message);
end
name = char(value);
end

function bytes = text_bytes(text)
text = strrep(text, [char(13) newline], newline);
text = strrep(text, char(13), newline);
while ~isempty(text) && text(end) == newline
    text(end) = [];
end
bytes = reshape(uint8(unicode2native([text newline], 'UTF-8')), 1, []);
end
