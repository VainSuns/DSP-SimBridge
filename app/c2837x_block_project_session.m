classdef c2837x_block_project_session < handle
%C2837X_BLOCK_PROJECT_SESSION Persist a V2 project and track session state.

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
            validate_project(project);
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
            validate_project(project);
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
            instance = merge_changes(session.Project.instances(index), changes);
            validate_instance_operation(instance);
            validate_instance_conflicts(instance, session.Project.instances, index);
            project = session.Project;
            project.instances(index) = instance;
            session.updateProject(project);
        end

        function copyInstance(session, index, displayName, internalName, ...
                socketNumber, tcpPort)
            index = valid_instance_index(session.Project, index);
            source = session.Project.instances(index);
            instance = c2837x_block_create_default_instance();
            instance.display_name = displayName;
            instance.internal_name = internalName;
            instance.iodevice = source.iodevice;
            instance.iodevice.settings.socket_number = socketNumber;
            instance.iodevice.settings.tcp_port = tcpPort;
            instance.sample_time_sec = source.sample_time_sec;
            instance.max_payload_size_bytes = source.max_payload_size_bytes;
            instance.inputs = source.inputs;
            instance.outputs = source.outputs;
            instance.algorithm.mode = source.algorithm.mode;
            validate_instance_operation(instance);
            validate_instance_conflicts(instance, session.Project.instances, []);
            project = session.Project;
            project.instances(end + 1) = instance;
            session.updateProject(project);
        end

        function renameInstance(session, index, displayName, internalName)
            index = valid_instance_index(session.Project, index);
            oldName = session.Project.instances(index).internal_name;
            changes = struct('display_name', displayName, ...
                'internal_name', internalName);
            session.updateInstance(index, changes);
            if ~strcmp(oldName, char(string(internalName)))
                session.LegacyFileRisks(end + 1) = legacy_risk( ...
                    'rename', oldName, 'Internal name changed; old generated files may remain.');
            end
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
            elseif ismember('config', variables)
                data = load(filePath, 'config');
                project = c2837x_block_migrate_legacy_config(data.config);
                migrated = true;
            else
                error('C2837xBlock:Project:MissingProject', ...
                    'Project file does not contain a project or config variable.');
            end
            validate_project(project);

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
                session.Dirty = false;
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
    validate_instance(instance);
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
indices(indices == excludedIndex) = [];
if any(strcmpi(instance.internal_name, {instances(indices).internal_name}))
    instance_error('DuplicateName', 'Internal name must be unique within the project.');
end
for index = indices
    other = instances(index);
    if isequal(instance.iodevice.settings.socket_number, ...
            other.iodevice.settings.socket_number)
        instance_error('DuplicateSocket', 'Socket number is already used.');
    end
    if isequal(instance.iodevice.settings.tcp_port, ...
            other.iodevice.settings.tcp_port)
        instance_error('DuplicatePort', 'TCP port is already used.');
    end
end
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

function validate_project(project)
if ~isstruct(project) || ~isscalar(project)
    invalid_project('project must be a scalar struct.');
end
require_fields(project, {'format_version', 'common', 'instances', 'output'}, 'project');
validate_version(project.format_version, uint16(2), 'format_version');

common = project.common;
if ~isstruct(common) || ~isscalar(common)
    invalid_project('project.common must be a scalar struct.');
end
require_fields(common, {'dsp_model', 'protocol_version', 'abi', 'network'}, ...
    'project.common');
validate_version(common.protocol_version, uint16(1), 'protocol_version');
require_text(common.dsp_model, 'project.common.dsp_model');
require_text(common.abi, 'project.common.abi');

network = common.network;
if ~isstruct(network) || ~isscalar(network)
    invalid_project('project.common.network must be a scalar struct.');
end
require_fields(network, {'mac', 'ip', 'gateway', 'subnet'}, ...
    'project.common.network');
if ~isnumeric(network.mac) || ~isvector(network.mac)
    invalid_project('project.common.network.mac must be a numeric vector.');
end
require_text(network.ip, 'project.common.network.ip');
require_text(network.gateway, 'project.common.network.gateway');
require_text(network.subnet, 'project.common.network.subnet');

if ~isstruct(project.instances)
    invalid_project('project.instances must be a struct array.');
end
require_fields(project.instances, {'display_name', 'internal_name', ...
    'iodevice', 'sample_time_sec', 'max_payload_size_bytes', 'inputs', ...
    'outputs', 'algorithm', 'interface_hash'}, 'project.instances');
for index = 1:numel(project.instances)
    validate_instance(project.instances(index));
end

output = project.output;
if ~isstruct(output) || ~isscalar(output)
    invalid_project('project.output must be a scalar struct.');
end
require_fields(output, {'dsp_root', 'sfun_root'}, 'project.output');
require_text(output.dsp_root, 'project.output.dsp_root');
require_text(output.sfun_root, 'project.output.sfun_root');
end

function validate_instance(instance)
require_fields(instance, {'display_name', 'internal_name', 'iodevice', ...
    'sample_time_sec', 'max_payload_size_bytes', 'inputs', 'outputs', ...
    'algorithm', 'interface_hash'}, 'project.instances');
require_text(instance.display_name, 'instance.display_name');
require_text(instance.internal_name, 'instance.internal_name');
require_numeric_scalar(instance.sample_time_sec, 'instance.sample_time_sec');
require_numeric_scalar(instance.max_payload_size_bytes, ...
    'instance.max_payload_size_bytes');
require_numeric_scalar(instance.interface_hash, 'instance.interface_hash');

iodevice = instance.iodevice;
if ~isstruct(iodevice) || ~isscalar(iodevice)
    invalid_project('instance.iodevice must be a scalar struct.');
end
require_fields(iodevice, {'type', 'settings'}, 'instance.iodevice');
require_text(iodevice.type, 'instance.iodevice.type');
if ~isstruct(iodevice.settings) || ~isscalar(iodevice.settings)
    invalid_project('instance.iodevice.settings must be a scalar struct.');
end
require_fields(iodevice.settings, {'socket_number', 'tcp_port'}, ...
    'instance.iodevice.settings');
require_numeric_scalar(iodevice.settings.socket_number, ...
    'instance.iodevice.settings.socket_number');
require_numeric_scalar(iodevice.settings.tcp_port, ...
    'instance.iodevice.settings.tcp_port');

validate_variables(instance.inputs, 'instance.inputs');
validate_variables(instance.outputs, 'instance.outputs');
algorithm = instance.algorithm;
if ~isstruct(algorithm) || ~isscalar(algorithm)
    invalid_project('instance.algorithm must be a scalar struct.');
end
require_fields(algorithm, {'mode', 'source_path'}, 'instance.algorithm');
require_text(algorithm.mode, 'instance.algorithm.mode');
require_text(algorithm.source_path, 'instance.algorithm.source_path');
end

function validate_variables(variables, label)
if ~isstruct(variables)
    invalid_project('%s must be a struct array.', label);
end
require_fields(variables, {'name', 'type', 'dim'}, label);
for index = 1:numel(variables)
    require_text(variables(index).name, [label '.name']);
    require_text(variables(index).type, [label '.type']);
    if ~isnumeric(variables(index).dim) || isempty(variables(index).dim) || ...
            ~isvector(variables(index).dim)
        invalid_project('%s.dim must be a nonempty numeric vector.', label);
    end
end
end

function validate_version(value, supported, name)
if ~isa(value, 'uint16') || ~isscalar(value) || value == 0
    error('C2837xBlock:Project:InvalidVersion', ...
        '%s must be a nonzero uint16 scalar.', name);
end
if value > supported
    error('C2837xBlock:Project:UnsupportedVersion', ...
        '%s %g is newer than supported version %g.', name, value, supported);
end
if value ~= supported
    error('C2837xBlock:Project:InvalidVersion', ...
        '%s must equal supported version %g.', name, supported);
end
end

function require_fields(value, names, label)
missing = names(~isfield(value, names));
if ~isempty(missing)
    invalid_project('%s is missing field %s.', label, missing{1});
end
end

function require_text(value, label)
if ~(ischar(value) && (isrow(value) || isempty(value))) && ...
        ~(isstring(value) && isscalar(value))
    invalid_project('%s must be text.', label);
end
end

function require_numeric_scalar(value, label)
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ~isfinite(value)
    invalid_project('%s must be a finite numeric scalar.', label);
end
end

function invalid_project(message, varargin)
error('C2837xBlock:Project:InvalidStructure', message, varargin{:});
end
