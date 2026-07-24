function [definitions, expected] = c2837x_block_stage1_candidate_fixture(root)
%C2837X_BLOCK_STAGE1_CANDIDATE_FIXTURE Create neutral stage-1 targets.

root = c2837x_block_normalize_absolute_path(root);
folder = fullfile(root, 'fixture');
mkdir(folder);
names = {'auto_missing.txt', 'auto_same.txt', 'auto_different.txt', ...
    'core_same.txt', 'core_different.txt', 'user_missing.txt', ...
    'user_same.txt', 'user_different.txt'};
categories = {'auto_generated', 'auto_generated', 'auto_generated', ...
    'core', 'core', 'user', 'user', 'user'};
states = {'missing', 'same', 'different', 'same', 'different', ...
    'missing', 'same', 'different'};
actions = {'create', 'skip', 'replace', 'skip', 'replace', ...
    'create', 'skip', 'keep'};
mandatory = [true, true, true, true, true, true, true, false];

prototype = struct('target_path', '', 'category', '', 'owner', '', ...
    'instance_index', 0, 'content_bytes', zeros(1, 0, 'uint8'));
definitions = repmat(prototype, 1, numel(names));
for index = 1:numel(names)
    bytes = fixture_bytes(categories{index}, names{index});
    definitions(index) = struct('target_path', fullfile(folder, names{index}), ...
        'category', categories{index}, 'owner', ['fixture:' names{index}], ...
        'instance_index', double(strcmp(categories{index}, 'user')), ...
        'content_bytes', bytes);
    if strcmp(states{index}, 'same')
        write_bytes(definitions(index).target_path, bytes);
    elseif strcmp(states{index}, 'different')
        write_bytes(definitions(index).target_path, ...
            uint8(unicode2native(sprintf('EXISTING TARGET\n%s\n', names{index}), 'UTF-8')));
    end
end
expected = struct('names', {names}, 'states', {states}, 'actions', {actions}, ...
    'mandatory', mandatory);
end

function bytes = fixture_bytes(category, name)
switch category
    case 'auto_generated'
        text = sprintf(['AUTO-GENERATED FILE\n' ...
            'Manual changes will be overwritten.\n%s\n'], name);
    case 'core'
        text = sprintf('DSP-SimBridge core source\n%s\n', name);
    otherwise
        text = sprintf('USER-EDITABLE FILE\n%s\n', name);
end
bytes = reshape(uint8(unicode2native(text, 'UTF-8')), 1, []);
end

function write_bytes(path, bytes)
fileID = fopen(path, 'wb');
assert(fileID >= 0, 'Fixture target could not be opened.');
cleanup = onCleanup(@() fclose(fileID));
fwrite(fileID, bytes, 'uint8');
clear cleanup
end
