function names = c2837x_block_build_instance_c_names(internalName)
%C2837X_BLOCK_BUILD_INSTANCE_C_NAMES Build instance-specific C names.

[valid, message] = c2837x_block_validate_name(internalName, {});
if ~valid
    error('C2837xBlock:DspInstance:InvalidInstanceName', '%s', message);
end
internalName = char(internalName);
parts = strsplit(internalName, '_');
typedPrefix = strjoin(cellfun( ...
    @(part) [upper(part(1)) part(2:end)], parts, 'UniformOutput', false), '');
names = struct('internal_name', internalName, ...
    'macro_prefix', upper(internalName), 'typed_prefix', typedPrefix);
end
