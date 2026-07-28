function rendered = c2837x_block_render_dsp_project_files(project)
%C2837X_BLOCK_RENDER_DSP_PROJECT_FILES Render deterministic project C files.

c2837x_block_validate_project_structure(project);
header = sprintf([ ...
    '#ifndef C2837X_BLOCK_PROJECT_H\n' ...
    '#define C2837X_BLOCK_PROJECT_H\n\n' ...
    '/*\n' ...
    ' * AUTO-GENERATED FILE\n' ...
    ' * Manual changes will be overwritten.\n' ...
    ' */\n\n' ...
    '#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION  1u\n' ...
    '#include "c2837x_block.h"\n\n']);
source = '#include "c2837x_block_internal.h"';
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
    source = [source sprintf('#include "%s_config.h"\n', name)]; %#ok<AGROW>
    header = [header sprintf('extern C2837xBlock g_%s;\n', name)]; %#ok<AGROW>
end
header = [header sprintf('\n#endif /* C2837X_BLOCK_PROJECT_H */\n')];
source = [source newline];
for index = 1:numel(sourceSupport)
    source = [source sourceSupport{index} newline]; %#ok<AGROW>
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
