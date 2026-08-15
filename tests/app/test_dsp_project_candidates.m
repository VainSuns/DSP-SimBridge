classdef test_dsp_project_candidates < matlab.unittest.TestCase
    properties
        WorkFolder
        RepositoryRoot
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            testCase.RepositoryRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'app')));
        end
    end

    methods (TestMethodSetup)
        function createWorkFolder(testCase)
            testCase.WorkFolder = c2837x_block_normalize_absolute_path(tempname);
            mkdir(testCase.WorkFolder);
            testCase.addTeardown(@() rmdir(testCase.WorkFolder, 's'));
        end
    end

    methods (Test)
        function testUserInstancesDriveDeterministicProjectFiles(testCase)
            project = make_project(testCase.WorkFolder, ...
                {'motor_control', 'thermal_monitor'});

            [candidates, ~, issues] = c2837x_block_build_dsp_candidates(project);
            projectCandidates = candidates([candidates.instance_index] == 0 & ...
                strcmp({candidates.category}, 'auto_generated'));
            header = candidate_text(projectCandidates, 'c2837x_block_project.h');
            source = candidate_text(projectCandidates, 'c2837x_block_project.c');

            testCase.verifyEmpty(issues);
            testCase.verifyNumElements(candidates, 31);
            testCase.verifyNumElements(projectCandidates, 2);
            testCase.verifyEqual([projectCandidates.instance_index], [0 0]);
            verify_order(testCase, header, {'g_motor_control', 'g_thermal_monitor'});
            verify_order(testCase, source, { ...
                sprintf(['extern const C2837xBlock_Config\n' ...
                '    c2837x_block_motor_control_config;']), ...
                sprintf(['extern const C2837xBlock_Config\n' ...
                '    c2837x_block_thermal_monitor_config;']), ...
                'C2837xBlock g_motor_control', ...
                'C2837xBlock g_thermal_monitor'});
            testCase.verifyNotEmpty(strfind(source, ...
                '&c2837x_block_motor_control_config'));
            testCase.verifyNotEmpty(strfind(source, ...
                '&c2837x_block_thermal_monitor_config'));
            testCase.verifyNotEmpty(strfind(source, '0xC0A80164UL'));
            testCase.verifyNotEmpty(strfind(source, '0xFFFFFF00UL'));
            testCase.verifyEmpty(regexp([header source], ...
                '(current_loop|voltage_loop|InitAll|RunAll|GetInstance|Register|malloc|calloc|realloc|free)', 'once'));
            testCase.verifyEmpty(regexp(header, ...
                '(Config|Channel|Buffer|Adapter|Context|192\.168|0xC0A8)', 'once'));
            testCase.verifyEmpty(regexp(source, ...
                '#include\s+"[^"]+_config\.h"', 'once'));
            testCase.verifyEqual(numel(regexp(source, ...
                'extern\s+const\s+C2837xBlock_Config', 'match')), 2);
            testCase.verifyNotEmpty(strfind(source, ...
                '#include "c2837x_block_internal.h"'));
            verify_bytes(testCase, projectCandidates);
            testCase.verifyFalse(isfolder(project.output.dsp_root));
        end

        function testOnlyRelevantProjectInputsChangeBytes(testCase)
            project = make_project(testCase.WorkFolder, {'axis_x', 'axis_y', 'diagnostics'});
            first = project_bytes(project);
            repeated = project_bytes(project);
            testCase.verifyEqual(repeated, first);

            ignored = project;
            ignored.instances(1).display_name = 'Changed Display';
            ignored.instances(1).iodevice.settings.socket_number = 7;
            ignored.instances(1).iodevice.settings.tcp_port = 6000;
            ignored.instances(1).sample_time_sec = 0.25;
            ignored.instances(1).max_payload_size_bytes = uint32(2048);
            ignored.instances(1).interface_hash = uint32(99);
            ignored.instances(1).inputs.name = 'other_command';
            ignored.instances(1).outputs.dim = 3;
            ignored.instances(1).algorithm.mode = 'external_reference';
            ignored.selected_instance = 3;
            testCase.verifyEqual(project_bytes(ignored), first);

            network = project;
            network.common.network.ip = '10.1.2.3';
            changedNetwork = project_bytes(network);
            testCase.verifyEqual(changedNetwork.header, first.header);
            testCase.verifyNotEqual(changedNetwork.source, first.source);

            renamed = project;
            renamed.instances(2).internal_name = 'axis_z';
            testCase.verifyNotEqual(project_bytes(renamed), first);
            reordered = project;
            reordered.instances = reordered.instances([3 1 2]);
            testCase.verifyNotEqual(project_bytes(reordered), first);

            strings = project;
            strings.common.network.ip = string(strings.common.network.ip);
            strings.common.network.gateway = string(strings.common.network.gateway);
            strings.common.network.subnet = string(strings.common.network.subnet);
            for index = 1:numel(strings.instances)
                strings.instances(index).internal_name = ...
                    string(strings.instances(index).internal_name);
                strings.instances(index).iodevice.type = ...
                    string(strings.instances(index).iodevice.type);
            end
            testCase.verifyEqual(project_bytes(strings), first);
        end

        function testRootChangesTargetsNotContent(testCase)
            project = make_project(testCase.WorkFolder, {'motor_control', 'thermal_monitor'});
            first = c2837x_block_build_dsp_candidates(project);
            project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'other_dsp'));
            second = c2837x_block_build_dsp_candidates(project);

            testCase.verifyNotEqual({second.target_path}, {first.target_path});
            testCase.verifyEqual({second.content_bytes}, {first.content_bytes});
            testCase.verifyFalse(isfolder(project.output.dsp_root));
        end

        function testGeneratedProjectAndPublicMainCompileToObjects(testCase)
            project = make_project(testCase.WorkFolder, ...
                {'motor_control', 'thermal_monitor'});
            bytes = project_bytes(project);
            generatedInc = fullfile(testCase.WorkFolder, 'inc');
            generatedSrc = fullfile(testCase.WorkFolder, 'src');
            mkdir(generatedInc); mkdir(generatedSrc);
            write_bytes(fullfile(generatedInc, 'c2837x_block_project.h'), bytes.header);
            write_bytes(fullfile(generatedSrc, 'c2837x_block_project.c'), bytes.source);
            for name = {'c2837x_block_internal.h', ...
                    'c2837x_block_config_internal.h', ...
                    'c2837x_block_platform.h'}
                copyfile(fullfile(testCase.RepositoryRoot, 'dsp', 'src', name{1}), ...
                    fullfile(generatedSrc, name{1}));
            end
            mainPath = fullfile(testCase.WorkFolder, 'main.c');
            write_text(mainPath, sprintf([ ...
                '#include "c2837x_block_project.h"\n' ...
                'void use_project(void) {\n' ...
                '  (void)C2837xBlock_PlatformInit();\n' ...
                '  C2837xBlock_Init(&g_motor_control);\n' ...
                '  C2837xBlock_Run(&g_motor_control);\n' ...
                '}\n']));

            includeFlags = sprintf('-I"%s" -I"%s" -I"%s"', ...
                fullfile(testCase.RepositoryRoot, 'tests', 'dsp_host', 'include'), ...
                generatedInc, fullfile(testCase.RepositoryRoot, 'dsp', 'inc'));
            [sourceStatus, sourceOutput] = system(sprintf( ...
                'gcc -std=c11 -Wall -Wextra -Werror %s -c "%s" -o "%s" 2>&1', ...
                includeFlags, fullfile(generatedSrc, 'c2837x_block_project.c'), ...
                fullfile(testCase.WorkFolder, 'project.o')));
            [mainStatus, mainOutput] = system(sprintf( ...
                'gcc -std=c11 -Wall -Wextra -Werror %s -c "%s" -o "%s" 2>&1', ...
                includeFlags, mainPath, fullfile(testCase.WorkFolder, 'main.o')));
            testCase.verifyEqual(sourceStatus, 0, sourceOutput);
            testCase.verifyEqual(mainStatus, 0, mainOutput);
        end
    end
end

function project = make_project(root, names)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([0 8 220 1 2 3]);
project.common.network.ip = '192.168.1.100';
project.common.network.gateway = '192.168.1.1';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
template = c2837x_block_create_default_instance();
template.inputs = struct('name', 'command', 'type', 'single', 'dim', 1);
template.outputs = struct('name', 'feedback', 'type', 'single', 'dim', 1);
instances = repmat(template, 1, numel(names));
for index = 1:numel(names)
    instances(index).display_name = strrep(names{index}, '_', ' ');
    instances(index).internal_name = names{index};
    instances(index).iodevice.settings.socket_number = uint16(index - 1);
    instances(index).iodevice.settings.tcp_port = uint16(4999 + index);
end
project.instances = instances;
end

function bytes = project_bytes(project)
rendered = c2837x_block_render_dsp_project_files(project);
bytes = struct('header', rendered.header_bytes, ...
    'source', rendered.source_bytes);
end

function text = candidate_text(candidates, name)
text = native2unicode(candidate_bytes(candidates, name), 'UTF-8');
end

function bytes = candidate_bytes(candidates, name)
index = find(endsWith({candidates.target_path}, name), 1);
assert(~isempty(index));
bytes = candidates(index).content_bytes;
end

function verify_bytes(testCase, candidates)
for index = 1:numel(candidates)
    bytes = candidates(index).content_bytes;
    testCase.verifyFalse(numel(bytes) >= 3 && ...
        isequal(bytes(1:3), uint8([239 187 191])));
    testCase.verifyFalse(any(bytes == 13));
    testCase.verifyEqual(bytes(end), uint8(10));
    testCase.verifyTrue(isscalar(bytes) || bytes(end - 1) ~= uint8(10));
end
end

function verify_order(testCase, text, values)
positions = cellfun(@(value) strfind(text, value), values, 'UniformOutput', false);
testCase.verifyTrue(all(cellfun(@isscalar, positions)));
testCase.verifyTrue(issorted(cellfun(@(value) value(1), positions)));
end

function write_bytes(path, bytes)
fileID = fopen(path, 'wb'); assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fwrite(fileID, bytes, 'uint8');
clear cleanup
end

function write_text(path, text)
write_bytes(path, reshape(uint8(unicode2native(text, 'UTF-8')), 1, []));
end
