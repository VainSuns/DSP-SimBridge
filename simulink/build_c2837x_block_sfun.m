function build_c2837x_block_sfun()
%BUILD_C2837X_BLOCK_SFUN Build C2837xBlock C MEX S-Function.
%
%   This script compiles the C MEX S-Function for C2837xBlock DSP
%   communication. It handles platform-specific dependencies (WinSock2
%   on Windows).
%
%   Usage:
%       >> build_c2837x_block_sfun
%
%   Output:
%       Creates c2837x_block_sfun.mexw64 (Windows) or
%       c2837x_block_sfun.mexa64 (Linux) in the current directory.
%
%   Prerequisites:
%       - MATLAB with Simulink
%       - Supported C compiler (MSVC on Windows, GCC on Linux)
%       - App-generated config files in simulink/ directory

% Get current directory (should be simulink/)
current_dir = pwd;
fprintf('Building C2837xBlock S-Function in: %s\n', current_dir);

% Source files
% Note: c2837x_block_pc_config.c is no longer needed because
% c2837x_block_sfun_io.c handles direct port-to-payload conversion.
src_files = {
    'c2837x_block_sfun.c'
    'c2837x_block_protocol.c'
    'c2837x_block_pc_socket.c'
    'c2837x_block_sfun_io.c'
};

% Check that all source files exist
for i = 1:length(src_files)
    if ~exist(src_files{i}, 'file')
        error('C2837xBlock:BuildError', ...
              'Source file not found: %s', src_files{i});
    end
end

% Include paths (current directory for project headers)
include_paths = {current_dir};

% Build mex command
mex_args = {};  % Let mex decide the API version

% Add verbose output
mex_args{end+1} = '-v';

% Add include paths
for i = 1:length(include_paths)
    mex_args{end+1} = ['-I' include_paths{i}];
end

% Add source files
for i = 1:length(src_files)
    mex_args{end+1} = src_files{i};
end

% Platform-specific libraries
if ispc
    % Windows: link with WinSock library
    % Detect compiler: MinGW uses -lws2_32, MSVC uses ws2_32.lib
    cc = mex.getCompilerConfigurations('C', 'Selected');
    if contains(cc.Name, 'MinGW', 'IgnoreCase', true)
        % For MinGW, specify library path and link ws2_32
        % The libws2_32.a is in x86_64-w64-mingw32/lib subdirectory
        mingw_path = getenv('MW_MINGW64_LOC');
        if isempty(mingw_path)
            error('C2837xBlock:BuildError', ...
                  'MW_MINGW64_LOC environment variable not set. Please set it to your MinGW installation path.');
        end
        if ~exist(mingw_path, 'dir')
            error('C2837xBlock:BuildError', ...
                  'MinGW path does not exist: %s', mingw_path);
        end
        % Add both lib paths where ws2_32 might be
        mex_args{end+1} = ['-L' fullfile(mingw_path, 'x86_64-w64-mingw32', 'lib')];
        mex_args{end+1} = ['-L' fullfile(mingw_path, 'lib')];
        mex_args{end+1} = '-lws2_32';
        fprintf('Platform: Windows/MinGW (linking -lws2_32)\n');
    else
        mex_args{end+1} = 'ws2_32.lib';
        fprintf('Platform: Windows/MSVC (linking ws2_32.lib)\n');
    end
elseif isunix
    % Linux/POSIX: no extra libraries needed
    fprintf('Platform: POSIX\n');
else
    error('C2837xBlock:BuildError', ...
          'Unsupported platform');
end

% Display build command
fprintf('MEX command: mex');
for i = 1:length(mex_args)
    fprintf(' %s', mex_args{i});
end
fprintf('\n\n');

% Start build timer
tic;

try
    % Run MEX compilation
    mex(mex_args{:});

    % Build succeeded
    elapsed = toc;
    fprintf('\nBuild successful! (%.2f seconds)\n', elapsed);

    % List generated MEX file
    if ispc
        mex_file = 'c2837x_block_sfun.mexw64';
    else
        mex_file = 'c2837x_block_sfun.mexa64';
    end

    if exist(mex_file, 'file')
        fprintf('Generated: %s\n', fullfile(current_dir, mex_file));
    end

catch e
    % Build failed
    elapsed = toc;
    fprintf('\nBuild FAILED! (%.2f seconds)\n', elapsed);
    fprintf('Error: %s\n', e.message);
    rethrow(e);
end

end
