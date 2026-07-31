function model = c2837x_block_build_sfun_output_model(project)
%C2837X_BLOCK_BUILD_SFUN_OUTPUT_MODEL Describe S4-01 S-Function outputs.

c2837x_block_validate_project_structure(project);
sfunRoot = canonical_root(project.output.sfun_root);
suffixes = {'sfun.c', 'sfun.h', 'sfun_io.c', 'sfun_config.h', ...
    'pc_socket.c', 'pc_socket.h', 'protocol.c', 'protocol.h'};
responsibilities = { ...
    'Normal-mode C MEX S-Function callbacks and private context lifetime.', ...
    'Instance context type and externally linked helper declarations.', ...
    'Compile-time Simulink input and output port configuration.', ...
    'Generated S-Function name, sample time, and port constants.', ...
    'Instance-private cross-platform TCP implementation.', ...
    'Instance-private Socket context and structured PC error API.', ...
    'Instance-private V1 frame serialization and receive validation.', ...
    'Instance-private V1 wire constants and protocol API.'};
prototype = struct('relative_path', '', 'target_path', '', 'category', '', ...
    'owner', '', 'instance_index', 0, 'file_scope', '', ...
    'responsibility', '', 'source_path', '', 'candidate_available', false);
files = repmat(prototype, 1, numel(suffixes) * numel(project.instances));
fileIndex = 0;
for instanceIndex = 1:numel(project.instances)
    names = c2837x_block_build_instance_c_names( ...
        project.instances(instanceIndex).internal_name);
    instanceRoot = c2837x_block_normalize_absolute_path( ...
        fullfile(sfunRoot, names.internal_name));
    for suffixIndex = 1:numel(suffixes)
        fileName = [names.internal_name '_' suffixes{suffixIndex}];
        relativePath = [names.internal_name '/' fileName];
        targetPath = c2837x_block_normalize_absolute_path( ...
            fullfile(instanceRoot, fileName));
        if ~is_descendant(instanceRoot, targetPath)
            error('C2837xBlock:SfunOutput:PathEscape', ...
                'S-Function output path escapes its instance directory.');
        end
        fileIndex = fileIndex + 1;
        files(fileIndex) = struct('relative_path', relativePath, ...
            'target_path', targetPath, 'category', 'auto_generated', ...
            'owner', ['sfun-instance:' names.internal_name ':' relativePath], ...
            'instance_index', double(instanceIndex), 'file_scope', 'instance', ...
            'responsibility', responsibilities{suffixIndex}, 'source_path', '', ...
            'candidate_available', true);
    end
end
paths = lower_cell({files.target_path});
if numel(unique(paths)) ~= numel(paths)
    error('C2837xBlock:SfunOutput:PathConflict', ...
        'S-Function output model contains duplicate or case-conflicting paths.');
end
model = struct('schema_version', uint16(1), 'sfun_root', sfunRoot, ...
    'files', files);
end

function root = canonical_root(value)
if ~((ischar(value) && isrow(value)) || ...
        (isstring(value) && isscalar(value) && ~ismissing(value)))
    invalid_root();
end
value = char(value);
try
    root = c2837x_block_normalize_absolute_path(value);
catch
    invalid_root();
end
if isempty(root) || ~strcmp(value, root)
    invalid_root();
end
end

function invalid_root()
error('C2837xBlock:SfunOutput:InvalidRoot', ...
    'project.output.sfun_root must be canonical absolute text.');
end

function values = lower_cell(values)
values = cellfun(@lower, values, 'UniformOutput', false);
end

function tf = is_descendant(root, path)
prefix = [root filesep];
if ispc
    tf = startsWith(path, prefix, 'IgnoreCase', true);
else
    tf = startsWith(path, prefix);
end
end
