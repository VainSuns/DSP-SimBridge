classdef c2837x_block_project_session < handle
%C2837X_BLOCK_PROJECT_SESSION Persist a V3 project and track session state.

    properties (Constant)
        DefaultFileName = 'dsp_simbridge_project.mat'
    end

    properties (SetAccess = private)
        Project
        FilePath = ''
        Dirty = false
        LegacyFileRisks = struct('action', {}, 'internal_name', {}, 'reason', {})
    end

    properties (Dependent)
        State
    end

    methods
        function session = c2837x_block_project_session(project)
            if nargin < 1
                project = c2837x_block_create_default_project();
            end
            c2837x_block_validate_project_structure(project);
            session.Project = project;
        end

        function state = get.State(session)
            if isempty(session.FilePath)
                state = 'never_saved';
            elseif session.Dirty
                state = 'saved_dirty';
            else
                state = 'saved_clean';
            end
        end

        function updateProject(session, project)
            c2837x_block_validate_project_structure(project);
            session.Project = project;
            session.Dirty = true;
        end

        function addInstance(session, changes)
            instance = merge_changes(c2837x_block_create_default_instance(), changes);
            validate_instance_operation(instance);
            validate_instance_conflicts(instance, session.Project.instances, []);
            project = session.Project;
            project.instances(end + 1) = instance;
            session.updateProject(project);
        end

        function updateInstance(session, index, changes)
            index = valid_instance_index(session.Project, index);
            oldName = session.Project.instances(index).internal_name;
            instance = merge_instance_changes( ...
                session.Project.instances(index), changes);
            validate_instance_operation(instance);
            validate_instance_conflicts(instance, session.Project.instances, index);
            project = session.Project;
            project.instances(index) = instance;
            session.updateProject(project);
            if ~strcmp(char(oldName), char(instance.internal_name))
                session.LegacyFileRisks(end + 1) = legacy_risk( ...
                    'rename', oldName, 'Internal name changed; old generated files may remain.');
            end
        end

        function switchIoDevice(session, index, type)
            session.updateInstance(index, struct('iodevice', struct('type', type)));
        end

        function copyInstance(session, index, displayName, internalName, varargin)
            index = valid_instance_index(session.Project, index);
            source = session.Project.instances(index);
            instance = c2837x_block_create_default_instance();
            instance.display_name = displayName;
            instance.internal_name = internalName;
            instance.iodevice = source.iodevice;
            switch char(source.iodevice.type)
                case 'w5300_tcp'
                    if numel(varargin) ~= 2
                        instance_error('CopyResourcesRequired', ...
                            'W5300 copy requires a new socket number and TCP port.');
                    end
                    instance.iodevice.settings.socket_number = varargin{1};
                    instance.iodevice.settings.tcp_port = varargin{2};
                case 'sci'
                    if ~isempty(varargin)
                        instance_error('InvalidCopyResources', ...
                            'SCI copy does not accept exclusive resource values.');
                    end
                    instance.iodevice.settings.module = '';
                    instance.iodevice.settings.pin_group = '';
                    instance.iodevice.settings.ctrl_gpio = 'None';
                otherwise
                    instance_error('UnsupportedIoDevice', ...
                        'Copy is unsupported for IoDevice type %s.', ...
                        char(source.iodevice.type));
            end
            instance.sample_time_sec = source.sample_time_sec;
            instance.max_payload_size_bytes = source.max_payload_size_bytes;
            instance.inputs = source.inputs;
            instance.outputs = source.outputs;
            instance.algorithm = source.algorithm;
            validate_instance_operation(instance);
            validate_instance_conflicts(instance, session.Project.instances, []);
            project = session.Project;
            project.instances(end + 1) = instance;
            session.updateProject(project);
        end

        function renameInstance(session, index, displayName, internalName)
            changes = struct('display_name', displayName, ...
                'internal_name', internalName);
            session.updateInstance(index, changes);
        end

        function deleteInstance(session, index)
            index = valid_instance_index(session.Project, index);
            oldName = session.Project.instances(index).internal_name;
            project = session.Project;
            project.instances(index) = [];
            session.updateProject(project);
            session.LegacyFileRisks(end + 1) = legacy_risk( ...
                'delete', oldName, 'Instance deleted; old generated files may remain.');
        end

        function saveProject(session, filePath)
            filePath = valid_file_path(filePath);
            project = session.Project;
            try
                save(filePath, 'project');
            catch cause
                failure = MException('C2837xBlock:Project:SaveFailed', ...
                    'Failed to save project to %s.', filePath);
                throwAsCaller(addCause(failure, cause));
            end
            session.FilePath = filePath;
            session.Dirty = false;
        end

        function loaded = loadProject(session, filePath, choice, savePath)
            filePath = valid_file_path(filePath);
            if nargin < 3
                choice = '';
            end
            if nargin < 4
                savePath = '';
            end
            if session.Dirty && strcmp(char(string(choice)), 'Cancel')
                loaded = false;
                return;
            end

            variables = who('-file', filePath);
            migrated = false;
            if ismember('project', variables)
                data = load(filePath, 'project');
                project = data.project;
                version = project_version(project);
                if version == uint16(2)
                    project = c2837x_block_migrate_project_v2(project);
                    migrated = true;
                end
            elseif ismember('config', variables)
                data = load(filePath, 'config');
                project = c2837x_block_migrate_legacy_config(data.config);
                migrated = true;
            else
                error('C2837xBlock:Project:MissingProject', ...
                    'Project file does not contain a project or config variable.');
            end
            c2837x_block_validate_project_structure(project);
            [project, hashMismatch] = refresh_interface_hashes(project);

            loaded = session.canDiscardChanges(choice, savePath);
            if ~loaded
                return;
            end

            session.Project = project;
            session.LegacyFileRisks = struct( ...
                'action', {}, 'internal_name', {}, 'reason', {});
            if migrated
                session.FilePath = '';
                session.Dirty = true;
            else
                session.FilePath = filePath;
                session.Dirty = hashMismatch;
            end
        end

        function proceed = canDiscardChanges(session, choice, savePath)
            if ~session.Dirty
                proceed = true;
                return;
            end
            if nargin < 3
                savePath = '';
            end

            switch char(string(choice))
                case 'Save'
                    if isempty(session.FilePath) && isempty(savePath)
                        proceed = false;
                        return;
                    end
                    if isempty(savePath)
                        savePath = session.FilePath;
                    end
                    session.saveProject(savePath);
                    proceed = true;
                case 'Don''t Save'
                    proceed = true;
                case 'Cancel'
                    proceed = false;
                otherwise
                    error('C2837xBlock:Project:DecisionRequired', ...
                        'Choose Save, Don''t Save, or Cancel.');
            end
        end
    end
end

function version = project_version(project)
if ~isstruct(project) || ~isscalar(project) || ...
        ~isfield(project, 'format_version')
    error('C2837xBlock:Project:InvalidStructure', ...
        'project must contain format_version.');
end
version = project.format_version;
if ~isa(version, 'uint16') || ~isscalar(version) || version == 0
    error('C2837xBlock:Project:InvalidVersion', ...
        'format_version must be a nonzero uint16 scalar.');
end
if version > uint16(3)
    error('C2837xBlock:Project:UnsupportedVersion', ...
        'format_version %g is newer than supported version 3.', version);
end
if version ~= uint16(2) && version ~= uint16(3)
    error('C2837xBlock:Project:InvalidVersion', ...
        'format_version must equal 2 or 3.');
end
end

function [project, mismatch] = refresh_interface_hashes(project)
mismatch = false;
for index = 1:numel(project.instances)
    savedHash = project.instances(index).interface_hash;
    [~, interfaceHash] = c2837x_block_build_interface_hash(project, index);
    mismatch = mismatch || ~numeric_values_equal(savedHash, interfaceHash);
    project.instances(index).interface_hash = interfaceHash;
end
end

function instance = merge_changes(instance, changes)
if ~isstruct(changes) || ~isscalar(changes)
    instance_error('InvalidChanges', 'Instance changes must be a scalar struct.');
end
names = fieldnames(changes);
for index = 1:numel(names)
    name = names{index};
    if ~isfield(instance, name)
        instance_error('InvalidChanges', 'Unknown instance field %s.', name);
    end
    if isstruct(instance.(name)) && isstruct(changes.(name)) && ...
            isscalar(instance.(name)) && isscalar(changes.(name))
        instance.(name) = merge_changes(instance.(name), changes.(name));
    else
        instance.(name) = changes.(name);
    end
end
end

function instance = merge_instance_changes(instance, changes)
if isstruct(changes) && isscalar(changes) && isfield(changes, 'iodevice') && ...
        isstruct(changes.iodevice) && isscalar(changes.iodevice) && ...
        isfield(changes.iodevice, 'type') && ...
        ~strcmp(char(string(changes.iodevice.type)), ...
        char(string(instance.iodevice.type)))
    iodevice = c2837x_block_create_iodevice(changes.iodevice.type);
    iodevice = merge_changes(iodevice, changes.iodevice);
    remaining = rmfield(changes, 'iodevice');
    instance = merge_changes(instance, remaining);
    instance.iodevice = iodevice;
else
    instance = merge_changes(instance, changes);
end
end

function index = valid_instance_index(project, index)
if ~isnumeric(index) || ~isscalar(index) || ~isreal(index) || ...
        ~isfinite(index) || index ~= fix(index) || index < 1 || ...
        index > numel(project.instances)
    instance_error('InvalidIndex', 'Instance index is out of range.');
end
index = double(index);
end

function validate_instance_operation(instance)
try
    project = c2837x_block_create_default_project();
    project.instances = instance;
    c2837x_block_validate_project_structure(project);
catch cause
    failure = MException('C2837xBlock:Instance:InvalidConfiguration', ...
        'Instance configuration is malformed.');
    throwAsCaller(addCause(failure, cause));
end
if ~is_nonempty_text(instance.display_name)
    instance_error('InvalidDisplayName', 'Display name must be nonempty text.');
end
[valid, message] = c2837x_block_validate_name(instance.internal_name, {});
if ~valid
    instance_error('InvalidName', '%s', message);
end
if isempty(instance.inputs) || isempty(instance.outputs)
    instance_error('InvalidVariables', ...
        'Each instance requires at least one input and one output.');
end
variables = [instance.inputs(:); instance.outputs(:)];
names = cell(1, numel(variables));
supportedTypes = {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'};
for index = 1:numel(variables)
    variable = variables(index);
    if ~isstruct(variable) || ~isscalar(variable) || ...
            ~all(isfield(variable, {'name', 'type', 'dim'}))
        instance_error('InvalidVariables', 'Variables must contain name, type, and dim.');
    end
    [valid, message] = c2837x_block_validate_name(variable.name, names(1:index - 1));
    if ~valid
        instance_error('InvalidName', '%s', message);
    end
    names{index} = char(variable.name);
    if ~(ischar(variable.type) && isrow(variable.type)) && ...
            ~(isstring(variable.type) && isscalar(variable.type))
        instance_error('InvalidVariables', 'Variable type must be text.');
    end
    if ~any(strcmp(char(variable.type), supportedTypes))
        instance_error('InvalidVariables', 'Unsupported variable type %s.', ...
            char(variable.type));
    end
    dim = variable.dim;
    if ~isnumeric(dim) || ~isscalar(dim) || ~isreal(dim) || ...
            ~isfinite(dim) || dim <= 0 || dim ~= fix(dim)
        instance_error('InvalidVariables', 'Variable dim must be a finite positive integer scalar.');
    end
end
end

function validate_instance_conflicts(instance, instances, excludedIndex)
indices = 1:numel(instances);
if ~isempty(excludedIndex)
    indices(indices == excludedIndex) = [];
end
if any(strcmpi(instance.internal_name, {instances(indices).internal_name}))
    instance_error('DuplicateName', 'Internal name must be unique within the project.');
end
for index = indices
    other = instances(index);
    if ~strcmp(char(instance.iodevice.type), 'w5300_tcp') || ...
            ~strcmp(char(other.iodevice.type), 'w5300_tcp')
        continue;
    end
    if numeric_values_equal(instance.iodevice.settings.socket_number, ...
            other.iodevice.settings.socket_number)
        instance_error('DuplicateSocket', 'Socket number is already used.');
    end
    if numeric_values_equal(instance.iodevice.settings.tcp_port, ...
            other.iodevice.settings.tcp_port)
        instance_error('DuplicatePort', 'TCP port is already used.');
    end
end
end

function tf = numeric_values_equal(left, right)
tf = double(left) == double(right);
end

function tf = is_nonempty_text(value)
tf = ((ischar(value) && isrow(value)) || ...
    (isstring(value) && isscalar(value))) && ~isempty(char(value));
end

function risk = legacy_risk(action, internalName, reason)
risk = struct('action', action, 'internal_name', internalName, 'reason', reason);
end

function instance_error(suffix, message, varargin)
error(['C2837xBlock:Instance:' suffix], message, varargin{:});
end

function filePath = valid_file_path(filePath)
if ~(ischar(filePath) && isrow(filePath)) && ...
        ~(isstring(filePath) && isscalar(filePath))
    error('C2837xBlock:Project:InvalidPath', ...
        'Project file path must be text.');
end
filePath = char(filePath);
if isempty(filePath)
    error('C2837xBlock:Project:InvalidPath', ...
        'Project file path must not be empty.');
end
end
