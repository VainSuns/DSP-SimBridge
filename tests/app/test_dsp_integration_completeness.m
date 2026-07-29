classdef test_dsp_integration_completeness < matlab.unittest.TestCase
    properties
        WorkFolder
        RepositoryRoot
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.RepositoryRoot = fileparts(fileparts(fileparts( ...
                mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'app')));
        end
    end

    methods (TestMethodSetup)
        function makeWorkFolder(testCase)
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.WorkFolder = fixture.Folder;
        end
    end

    methods (Test)
        function testProjectAExactOutputTree(testCase)
            project = project_a(testCase.WorkFolder, 'project_a');
            run = generate_project(project);

            testCase.verifyEqual(run.result.status, 'completed');
            testCase.verifyEqual(run.result.phase, 'complete');
            testCase.verifyFalse(has_errors(run.provider_issues));
            testCase.verifyFalse(has_errors(run.snapshot_issues));
            testCase.verifyFalse(has_errors(run.commit_issues));
            testCase.verifyEqual(numel(run.candidates), 31);
            testCase.verifyEqual(tree_files(project.output.dsp_root), ...
                expected_a_files());
            testCase.verifyEqual(read_bytes(fullfile(project.output.dsp_root, ...
                'src', 'axis_b_algorithm.c')), ...
                read_bytes(project.instances(2).algorithm.source_path));
            testCase.verifyFalse(isfolder(project.output.sfun_root));
            testCase.verifyEqual(tree_directories(project.output.dsp_root), ...
                {'inc', 'src'});
            fprintf('S3_07_PROJECT_A candidates=%u files=%u created=%u\n', ...
                numel(run.candidates), numel(tree_files(project.output.dsp_root)), ...
                run.result.created_count);
        end

        function testProjectBExternalReferenceFileSet(testCase)
            project = project_b(testCase.WorkFolder, 'project_b');
            run = generate_project(project);

            testCase.verifyEqual(run.result.status, 'completed');
            testCase.verifyFalse(has_errors(run.provider_issues));
            testCase.verifyFalse(has_errors(run.snapshot_issues));
            testCase.verifyFalse(has_errors(run.commit_issues));
            testCase.verifyEqual(numel(run.candidates), 30);
            testCase.verifyEqual(tree_files(project.output.dsp_root), ...
                expected_b_files());
            testCase.verifyFalse(isfile(fullfile(project.output.dsp_root, ...
                'src', 'plant_algorithm.c')));
            testCase.verifyTrue(isfile(project.instances(2).algorithm.source_path));
            testCase.verifyFalse(isfolder(project.output.sfun_root));
            fprintf('S3_07_PROJECT_B candidates=%u files=%u created=%u\n', ...
                numel(run.candidates), numel(tree_files(project.output.dsp_root)), ...
                run.result.created_count);
        end

        function testQuotedIncludesResolveUniquely(testCase)
            project = project_a(testCase.WorkFolder, 'includes');
            generate_project(project);
            audit = include_audit(project.output.dsp_root);

            testCase.verifyEqual(audit.unresolved, 0, audit.details);
            testCase.verifyEqual(audit.multiple, 0, audit.details);
            testCase.verifyEqual(audit.c_includes, 0, audit.details);
            testCase.verifyEqual(audit.inc_to_src, 0, audit.details);
            testCase.verifyGreaterThan(audit.total, 0);
            testCase.verifyEqual(audit.total, ...
                audit.inc_resolved + audit.src_local + audit.src_inc + ...
                audit.allowed_external);
            fprintf(['S3_07_INCLUDES total=%u inc=%u src_local=%u src_inc=%u ' ...
                'allowed_external=%u unresolved=%u multiple=%u ' ...
                'inc_to_src=%u include_c=%u\n'], audit.total, ...
                audit.inc_resolved, audit.src_local, audit.src_inc, ...
                audit.allowed_external, audit.unresolved, audit.multiple, ...
                audit.inc_to_src, audit.c_includes);
        end

        function testCcsSourceListHasUniqueCompileUnits(testCase)
            projectA = project_a(testCase.WorkFolder, 'ccs_a');
            projectB = project_b(testCase.WorkFolder, 'ccs_b');
            generate_project(projectA);
            generate_project(projectB);
            listA = ccs_sources(projectA);
            listB = ccs_sources(projectB);
            resultA = compile_sources(testCase.RepositoryRoot, projectA, ...
                listA, fullfile(testCase.WorkFolder, 'objects_a'));
            resultB = compile_sources(testCase.RepositoryRoot, projectB, ...
                listB, fullfile(testCase.WorkFolder, 'objects_b'));

            testCase.verifyNumElements(listA.generated, 14);
            testCase.verifyEmpty(listA.external);
            testCase.verifyNumElements(listA.all, 14);
            testCase.verifyNumElements(listB.generated, 13);
            testCase.verifyNumElements(listB.external, 1);
            testCase.verifyNumElements(listB.all, 14);
            testCase.verifyEqual(folded_unique_count(listA.all), 14);
            testCase.verifyEqual(folded_unique_count(listB.all), 14);
            testCase.verifyEqual(resultA.statuses, zeros(1, 14), ...
                strjoin(resultA.outputs, newline));
            testCase.verifyEqual(resultB.statuses, zeros(1, 14), ...
                strjoin(resultB.outputs, newline));
            testCase.verifyTrue(compile_commands_are_inc_only(resultA, projectA));
            testCase.verifyTrue(compile_commands_are_inc_only(resultB, projectB));
            fprintf(['S3_07_CCS A_generated=%u A_external=%u A_total=%u ' ...
                'B_generated=%u B_external=%u B_total=%u\n'], ...
                numel(listA.generated), numel(listA.external), numel(listA.all), ...
                numel(listB.generated), numel(listB.external), numel(listB.all));
        end

        function testIncOnlyHeadersCompileAndInternalTypesStayPrivate(testCase)
            project = project_a(testCase.WorkFolder, 'header_probes');
            generate_project(project);
            result = compile_header_probes(testCase.RepositoryRoot, project, ...
                fullfile(testCase.WorkFolder, 'header_probe_build'));
            audit = internal_boundary_audit(project.output.dsp_root);

            testCase.verifyEqual(result.statuses, [0 0], ...
                strjoin(result.outputs, newline));
            testCase.verifyTrue(compile_commands_are_inc_only(result, project));
            testCase.verifyEqual(audit.inc_internal_include_count, 0);
            testCase.verifyEqual(audit.inc_config_type_count, 0);
            testCase.verifyEqual(audit.inc_adapter_type_count, 0);
            testCase.verifyTrue(audit.internal_headers_exist);
            testCase.verifyTrue(audit.internal_sources_use_types);
        end

        function testCoreApiVersionPositiveAndNegativeCheck(testCase)
            project = project_a(testCase.WorkFolder, 'api');
            generate_project(project);
            result = core_api_check(testCase.RepositoryRoot, project, ...
                testCase.WorkFolder);

            testCase.verifyEqual(result.expected, 1);
            testCase.verifyEqual(result.actual, 1);
            testCase.verifyEqual(result.positive_status, 0, ...
                result.positive_output);
            testCase.verifyNotEqual(result.negative_status, 0);
            testCase.verifySubstring(result.negative_output, ...
                'C2837xBlock Core API version mismatch');
        end

        function testPublicProjectHeaderExportsOpaqueInstancesOnly(testCase)
            project = project_a(testCase.WorkFolder, 'public_api');
            generate_project(project);
            projectHeader = fileread(fullfile(project.output.dsp_root, ...
                'inc', 'c2837x_block_project.h'));
            coreHeader = fileread(fullfile(project.output.dsp_root, ...
                'inc', 'c2837x_block.h'));

            testCase.verifyEqual(regexp(projectHeader, ...
                'extern C2837xBlock g_[a-z_]+;', 'match'), ...
                {'extern C2837xBlock g_axis_a;', ...
                 'extern C2837xBlock g_axis_b;'});
            testCase.verifyEmpty(regexp(projectHeader, ...
                'runtime|protocol_phase|Channel|Buffer|InputData|OutputData|Config|Adapter', ...
                'once'));
            testCase.verifyTrue(contains(coreHeader, ...
                'typedef struct C2837xBlock C2837xBlock;'));
            testCase.verifyNotEmpty(regexp(coreHeader, ...
                'C2837xBlock_Init\(C2837xBlock \*instance\)', 'once'));
            testCase.verifyNotEmpty(regexp(coreHeader, ...
                'C2837xBlock_Run\(C2837xBlock \*instance\)', 'once'));
            testCase.verifyEmpty(regexp(coreHeader, ...
                'C2837xBlock_(Init|Run)\(void\)|\bg_ctx\b', 'once'));
        end

        function testPerInstanceSymbolsAreIndependent(testCase)
            project = project_a(testCase.WorkFolder, 'symbols');
            generate_project(project);
            list = ccs_sources(project);
            compiled = compile_sources(testCase.RepositoryRoot, project, ...
                list, fullfile(testCase.WorkFolder, 'symbol_objects'));
            symbols = global_symbols(compiled.objects);
            expected = expected_instance_symbols({'axis_a', 'axis_b'});

            testCase.assertEqual(compiled.statuses, zeros(1, 14), ...
                strjoin(compiled.outputs, newline));
            testCase.verifyEqual(duplicate_symbols(symbols), cell(1, 0));
            testCase.verifyTrue(all(cellfun(@(name) ...
                sum(strcmp(symbols, name)) == 1, expected)), ...
                strjoin(setdiff(expected, symbols), ', '));
            fprintf('S3_07_SYMBOLS global=%u expected=%u duplicates=%u\n', ...
                numel(symbols), numel(expected), numel(duplicate_symbols(symbols)));
        end

        function testTemporaryMainUsesPublicApi(testCase)
            project = project_a(testCase.WorkFolder, 'main');
            generate_project(project);
            result = compile_temporary_main(testCase.RepositoryRoot, project, ...
                testCase.WorkFolder);

            testCase.verifyEqual(result.status, 0, result.output);
            testCase.verifyEqual(result.includes, ...
                {'c2837x_block_project.h'});
            testCase.verifyEqual(result.init_count, 2);
            testCase.verifyEqual(result.run_count, 2);
            testCase.verifyFalse(isfile(fullfile(project.output.dsp_root, ...
                'src', 'main.c')));
            testCase.verifyFalse(any(contains({result.candidates.target_path}, ...
                result.source_path)));
        end

        function testAbiNeutralityAndProjectWideSelection(testCase)
            eabi = project_a(testCase.WorkFolder, 'abi_eabi');
            coff = eabi;
            coff.common.abi = 'coffabi';
            coff.output.dsp_root = normalized(fullfile( ...
                testCase.WorkFolder, 'abi_coff', 'dsp'));
            coff.output.sfun_root = normalized(fullfile( ...
                testCase.WorkFolder, 'abi_coff', 'sfun'));
            [eabiCandidates, ~, eabiIssues] = ...
                c2837x_block_build_dsp_candidates(eabi);
            [coffCandidates, ~, coffIssues] = ...
                c2837x_block_build_dsp_candidates(coff);
            eabiLayout = c2837x_block_build_dsp_wire_layout(eabi);
            coffLayout = c2837x_block_build_dsp_wire_layout(coff);

            testCase.verifyFalse(has_errors(eabiIssues));
            testCase.verifyFalse(has_errors(coffIssues));
            testCase.verifyEqual(relative_targets(eabiCandidates, ...
                eabi.output.dsp_root), relative_targets(coffCandidates, ...
                coff.output.dsp_root));
            testCase.verifyEqual({eabiCandidates.content_bytes}, ...
                {coffCandidates.content_bytes});
            testCase.verifyEqual(eabiLayout, coffLayout);
            testCase.verifyEqual(interface_hashes(eabi), ...
                interface_hashes(coff));
            testCase.verifyFalse(any(arrayfun(@(instance) ...
                isfield(instance, 'abi'), eabi.instances)));
        end

        function testNoLegacyOrForbiddenArtifacts(testCase)
            project = project_a(testCase.WorkFolder, 'legacy');
            generate_project(project);
            audit = forbidden_audit(project.output.dsp_root);

            testCase.verifyEmpty(audit.files);
            testCase.verifyEmpty(audit.symbols);
            testCase.verifyEqual(audit.c_includes, 0);
            testCase.verifyEqual(sum(strcmp(tree_files(project.output.dsp_root), ...
                'src/c2837x_block.c')), 1);
        end

        function testWireAndMemoryReportConsistency(testCase)
            project = project_a(testCase.WorkFolder, 'wire');
            generate_project(project);
            layout = c2837x_block_build_dsp_wire_layout(project);
            [report, issues] = c2837x_block_build_project_report(project);
            audit = wire_audit(project, layout);

            testCase.verifyEmpty(issues);
            testCase.verifyEqual(report.total_protocol_buffer_words, ...
                layout.project_protocol_buffer_words);
            testCase.verifyEqual([report.instances.protocol_buffer_words], ...
                [layout.instances.protocol_buffer_words]);
            testCase.verifyTrue(audit.config_matches);
            testCase.verifyTrue(audit.assertions_present);
            testCase.verifyEqual(layout.project_protocol_buffer_words, ...
                sum([layout.instances.rx_frame_words]) + ...
                sum([layout.instances.tx_frame_words]));
            hashes = interface_hashes(project);
            for index = 1:numel(layout.instances)
                item = layout.instances(index);
                fprintf(['S3_07_WIRE %s input_data=%u output_data=%u ' ...
                    'input_payload=%u output_payload=%u rx=%u tx=%u ' ...
                    'protocol=%u hash=0x%08X\n'], item.internal_name, ...
                    item.input_data_octets, item.output_data_octets, ...
                    item.input_payload_octets, item.output_payload_octets, ...
                    item.rx_frame_words, item.tx_frame_words, ...
                    item.protocol_buffer_words, hashes(index));
            end
            fprintf('S3_07_WIRE project_protocol_words=%u\n', ...
                layout.project_protocol_buffer_words);
        end

        function testRepeatedGenerationIsDeterministic(testCase)
            project = project_a(testCase.WorkFolder, 'repeat_one');
            first = generate_project(project);
            firstBytes = candidate_bytes(first.candidates);
            firstTimes = target_times(first.candidates);
            [secondSnapshot, secondSnapshotIssues] = ...
                c2837x_block_create_preview_snapshot(project, ...
                first.candidates, first.dependencies);
            [secondResult, secondCommitIssues] = ...
                c2837x_block_commit_preview_snapshot(secondSnapshot, ...
                project, first.candidates, first.dependencies);
            secondTimes = target_times(first.candidates);
            rmdir(project.output.dsp_root, 's');
            repeated = project_a(testCase.WorkFolder, 'repeat_two');
            third = generate_project(repeated);

            testCase.verifyFalse(has_errors(secondSnapshotIssues));
            testCase.verifyFalse(has_errors(secondCommitIssues));
            testCase.verifyEqual(secondResult.skipped_count, 31);
            testCase.verifyEqual(secondTimes, firstTimes);
            testCase.verifyEqual(relative_targets(first.candidates, ...
                project.output.dsp_root), relative_targets(third.candidates, ...
                repeated.output.dsp_root));
            testCase.verifyEqual(candidate_bytes(third.candidates), firstBytes);
            testCase.verifyEqual(interface_hashes(project), ...
                interface_hashes(repeated));
            testCase.verifyEqual(read_bytes(fullfile(repeated.output.dsp_root, ...
                'src', 'axis_b_algorithm.c')), ...
                read_bytes(repeated.instances(2).algorithm.source_path));
        end
    end
end

function project = project_a(root, name)
folder = fullfile(root, name);
copyPath = normalized(fullfile(folder, 'axis_b_external_copy.c'));
write_bytes(copyPath, external_algorithm_bytes('axis_b', 'AxisB', true));
project = base_project(folder, 'eabi');
first = instance('Axis A', 'axis_a', 1, 5101, ...
    'generated_example', '', variables('a', 2));
second = instance('Axis B', 'axis_b', 6, 5102, ...
    'external_copy', copyPath, variables('b', 3));
project.instances = [first second];
end

function project = project_b(root, name)
folder = fullfile(root, name);
referencePath = normalized(fullfile(folder, 'plant_external_reference.c'));
write_bytes(referencePath, external_algorithm_bytes('plant', 'Plant', false));
project = base_project(folder, 'coffabi');
first = instance('Control', 'control', 2, 5201, ...
    'generated_example', '', variables('c', 2));
second = instance('Plant', 'plant', 7, 5202, ...
    'external_reference', referencePath, variables('p', 1));
project.instances = [first second];
end

function project = base_project(folder, abi)
project = c2837x_block_create_default_project();
project.common.abi = abi;
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.10.20';
project.common.network.gateway = '0.0.0.0';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = normalized(fullfile(folder, 'dsp'));
project.output.sfun_root = normalized(fullfile(folder, 'sfun'));
end

function value = instance(displayName, internalName, socket, port, mode, path, vars)
value = c2837x_block_create_default_instance();
value.display_name = displayName;
value.internal_name = internalName;
value.iodevice.settings.socket_number = uint16(socket);
value.iodevice.settings.tcp_port = uint16(port);
value.inputs = vars.inputs;
value.outputs = vars.outputs;
value.algorithm = struct('mode', mode, 'source_path', path);
end

function value = variables(prefix, arrayDim)
types = {'int16', 'uint16', 'int32', 'uint32', 'single', 'double'};
inputNames = cellfun(@(type) [prefix '_in_' type], types, ...
    'UniformOutput', false);
outputNames = cellfun(@(type) [prefix '_out_' type], types, ...
    'UniformOutput', false);
dims = {1, 1, arrayDim, 1, 1, 1};
value = struct( ...
    'inputs', struct('name', inputNames, 'type', types, 'dim', dims), ...
    'outputs', struct('name', outputNames, 'type', types, 'dim', dims));
end

function bytes = external_algorithm_bytes(name, typed, crlf)
lineEnd = newline;
if crlf
    lineEnd = [char(13) newline];
end
lines = {sprintf('#include "%s_algorithm.h"', name), '', ...
    sprintf('int16 %s_OnStart(void) { return 0; }', typed), ...
    sprintf(['int16 %s_OnStep(const %s_InputData *input, ' ...
    '%s_OutputData *output)'], typed, typed, typed), ...
    '{', '    (void)input;', '    (void)output;', '    return 0;', '}', ...
    sprintf('void %s_OnStop(void) {}', typed), ''};
bytes = reshape(uint8(unicode2native(strjoin(lines, lineEnd), ...
    'UTF-8')), 1, []);
end

function run = generate_project(project)
assert(~isfolder(project.output.dsp_root));
[candidates, dependencies, providerIssues] = ...
    c2837x_block_build_dsp_candidates(project);
[snapshot, snapshotIssues] = c2837x_block_create_preview_snapshot( ...
    project, candidates, dependencies);
[result, commitIssues] = c2837x_block_commit_preview_snapshot( ...
    snapshot, project, candidates, dependencies);
run = struct('candidates', candidates, 'dependencies', dependencies, ...
    'provider_issues', providerIssues, 'snapshot', snapshot, ...
    'snapshot_issues', snapshotIssues, 'result', result, ...
    'commit_issues', commitIssues);
end

function files = expected_a_files()
files = sort([common_files(), project_files(), ...
    instance_files('axis_a', true), instance_files('axis_b', true)]);
end

function files = expected_b_files()
files = sort([common_files(), project_files(), ...
    instance_files('control', true), instance_files('plant', false)]);
end

function files = common_files()
files = {'inc/c2837x_block.h', 'inc/c2837x_block_protocol.h', ...
    'inc/c2837x_block_iodevice.h', 'inc/c2837x_w5300_regs.h', ...
    'inc/c2837x_w5300_hal.h', 'inc/c2837x_w5300_socket.h', ...
    'inc/c2837x_w5300_channel.h', 'src/c2837x_block.c', ...
    'src/c2837x_block_protocol.c', 'src/c2837x_block_internal.h', ...
    'src/c2837x_block_config_internal.h', 'src/c2837x_block_platform.h', ...
    'src/c2837x_block_platform.c', 'src/c2837x_block_timer2.c', ...
    'src/c2837x_w5300_hal.c', 'src/c2837x_w5300_socket.c', ...
    'src/c2837x_w5300_channel.c'};
end

function files = project_files()
files = {'inc/c2837x_block_project.h', 'src/c2837x_block_project.c'};
end

function files = instance_files(name, hasAlgorithm)
files = {['inc/' name '_config.h'], ['inc/' name '_user_config.h'], ...
    ['inc/' name '_algorithm.h'], ['src/' name '_config.c'], ...
    ['src/' name '_io.c']};
if hasAlgorithm
    files{end + 1} = ['src/' name '_algorithm.c'];
end
end

function files = tree_files(root)
values = dir(fullfile(root, '**', '*'));
values = values(~[values.isdir]);
files = cellfun(@(path) slash(path(numel(root) + 2:end)), ...
    fullfile({values.folder}, {values.name}), 'UniformOutput', false);
files = sort(files);
end

function directories = tree_directories(root)
values = dir(root);
values = values([values.isdir] & ~ismember({values.name}, {'.', '..'}));
directories = sort({values.name});
end

function audit = include_audit(root)
files = [dir(fullfile(root, '**', '*.c')); dir(fullfile(root, '**', '*.h'))];
allowed = {'F28x_Project.h', 'stdint.h', 'limits.h', 'float.h', 'string.h'};
total = 0; incResolved = 0; srcLocal = 0; srcInc = 0;
external = 0; unresolved = 0; multiple = 0; incToSrc = 0;
cIncludes = 0; details = {};
for index = 1:numel(files)
    sourcePath = fullfile(files(index).folder, files(index).name);
    inInc = paths_equal(files(index).folder, fullfile(root, 'inc'));
    includes = regexp(fileread(sourcePath), ...
        '^\s*#include\s+"([^"]+)"', 'tokens', 'lineanchors');
    for include = includes
        total = total + 1;
        name = include{1}{1};
        cIncludes = cIncludes + endsWith(lower(name), '.c');
        localTarget = fullfile(files(index).folder, name);
        incTarget = fullfile(root, 'inc', name);
        if inInc
            targets = {localTarget};
            incToSrc = incToSrc + isfile(fullfile(root, 'src', name));
        else
            targets = unique({localTarget, incTarget});
        end
        matches = targets(cellfun(@isfile, targets));
        if isscalar(matches)
            if inInc
                incResolved = incResolved + 1;
                status = 'inc';
            elseif paths_equal(fileparts(matches{1}), files(index).folder)
                srcLocal = srcLocal + 1;
                status = 'src local';
            else
                srcInc = srcInc + 1;
                status = 'src to inc';
            end
        elseif isempty(matches) && any(strcmp(name, allowed))
            external = external + 1;
            status = 'allowed external';
        elseif isempty(matches)
            unresolved = unresolved + 1;
            status = 'unresolved';
        else
            multiple = multiple + 1;
            status = 'multiple';
        end
        details{end + 1} = sprintf('%s | %s | %s | %s', ...
            slash(sourcePath), name, strjoin(cellfun(@slash, matches, ...
            'UniformOutput', false), ', '), status); %#ok<AGROW>
    end
end
audit = struct('total', total, 'inc_resolved', incResolved, ...
    'src_local', srcLocal, 'src_inc', srcInc, ...
    'allowed_external', external, 'unresolved', unresolved, ...
    'multiple', multiple, 'inc_to_src', incToSrc, ...
    'c_includes', cIncludes, ...
    'details', strjoin(details, newline));
end

function list = ccs_sources(project)
generated = dir(fullfile(project.output.dsp_root, 'src', '*.c'));
generated = sort(fullfile({generated.folder}, {generated.name}));
external = {};
for index = 1:numel(project.instances)
    if strcmp(project.instances(index).algorithm.mode, 'external_reference')
        external{end + 1} = project.instances(index).algorithm.source_path; %#ok<AGROW>
    end
end
list = struct('generated', {generated}, 'external', {external}, ...
    'all', {[generated external]});
end

function result = compile_sources(repositoryRoot, project, list, objectRoot)
mkdir(objectRoot);
flags = compile_flags(repositoryRoot, project);
statuses = zeros(1, numel(list.all));
outputs = cell(1, numel(list.all));
objects = cell(1, numel(list.all));
commands = cell(1, numel(list.all));
for index = 1:numel(list.all)
    [~, name] = fileparts(list.all{index});
    objects{index} = fullfile(objectRoot, sprintf('%02u_%s.o', index, name));
    commands{index} = sprintf( ...
        'cd /d "%s" && gcc %s -c "%s" -o "%s" 2>&1', ...
        objectRoot, flags, list.all{index}, objects{index});
    [statuses(index), outputs{index}] = system(commands{index});
end
result = struct('statuses', statuses, 'outputs', {outputs}, ...
    'objects', {objects}, 'commands', {commands}, 'flags', flags);
end

function flags = compile_flags(repositoryRoot, project)
flags = sprintf([ ...
    '-std=c11 -Wall -Wextra -Werror -Wno-unknown-pragmas ' ...
    '-Wno-error=int-to-pointer-cast ' ...
    '-mlong-double-64 -fstrict-aliasing -Wstrict-aliasing=2 ' ...
    '-I"%s" -I"%s"'], ...
    fullfile(repositoryRoot, 'tests', 'dsp_host', 'include'), ...
    fullfile(project.output.dsp_root, 'inc'));
end

function result = compile_header_probes(repositoryRoot, project, buildRoot)
mkdir(buildRoot);
configSource = fullfile(buildRoot, 'config_header_probe.c');
projectSource = fullfile(buildRoot, 'project_header_probe.c');
write_text(configSource, sprintf([ ...
    '#define C2837X_BLOCK_AXIS_A_USE_USER_CONFIG\n' ...
    '#include "axis_a_config.h"\n\n' ...
    'int config_header_probe(void)\n{\n' ...
    '    return (int)AXIS_A_PROTOCOL_VERSION;\n}\n']));
write_text(projectSource, sprintf([ ...
    '#include "c2837x_block_project.h"\n\n' ...
    'int project_header_probe(void)\n{\n    return 0;\n}\n']));
flags = compile_flags(repositoryRoot, project);
sources = {configSource, projectSource};
statuses = zeros(1, 2); outputs = cell(1, 2); commands = cell(1, 2);
for index = 1:2
    object = fullfile(buildRoot, sprintf('probe_%u.o', index));
    commands{index} = sprintf( ...
        'cd /d "%s" && gcc %s -c "%s" -o "%s" 2>&1', ...
        buildRoot, flags, sources{index}, object);
    [statuses(index), outputs{index}] = system(commands{index});
end
result = struct('statuses', statuses, 'outputs', {outputs}, ...
    'commands', {commands}, 'flags', flags);
end

function tf = compile_commands_are_inc_only(result, project)
src = fullfile(project.output.dsp_root, 'src');
banned = {['-I"' src '"'], ['-iquote "' src '"'], ...
    ['-isystem "' src '"']};
tf = contains(result.flags, ['-I"' fullfile(project.output.dsp_root, ...
    'inc') '"']) && all(cellfun(@(value) ...
    ~any(cellfun(@(pattern) contains(value, pattern), banned)), ...
    result.commands));
end

function audit = internal_boundary_audit(root)
headers = dir(fullfile(root, 'inc', '*.h'));
text = strjoin(cellfun(@(folder, name) fileread(fullfile(folder, name)), ...
    {headers.folder}, {headers.name}, 'UniformOutput', false), newline);
axisConfig = fileread(fullfile(root, 'src', 'axis_a_config.c'));
projectSource = fileread(fullfile(root, 'src', 'c2837x_block_project.c'));
audit = struct( ...
    'inc_internal_include_count', numel(regexp(text, ...
    '#include\s+"c2837x_block_config_internal\.h"', 'match')), ...
    'inc_config_type_count', numel(regexp(text, '\bC2837xBlock_Config\b', 'match')), ...
    'inc_adapter_type_count', numel(regexp(text, ...
    '\bC2837xBlock_AlgorithmAdapter\b', 'match')), ...
    'internal_headers_exist', isfile(fullfile(root, 'src', ...
    'c2837x_block_config_internal.h')) && isfile(fullfile(root, 'src', ...
    'c2837x_block_internal.h')), ...
    'internal_sources_use_types', contains(axisConfig, ...
    '#include "c2837x_block_config_internal.h"') && contains(axisConfig, ...
    'C2837xBlock_Config') && contains(projectSource, ...
    'extern const C2837xBlock_Config'));
end

function tf = paths_equal(first, second)
if ispc
    tf = strcmpi(first, second);
else
    tf = strcmp(first, second);
end
end

function result = core_api_check(repositoryRoot, project, root)
projectHeader = fileread(fullfile(project.output.dsp_root, ...
    'inc', 'c2837x_block_project.h'));
coreHeader = fileread(fullfile(project.output.dsp_root, ...
    'inc', 'c2837x_block.h'));
expected = str2double(regexp(projectHeader, ...
    'EXPECTED_CORE_API_VERSION\s+(\d+)u', 'tokens', 'once'));
actual = str2double(regexp(coreHeader, ...
    'CORE_API_VERSION\s+(\d+)u', 'tokens', 'once'));
source = fullfile(root, 'core_api_probe.c');
write_text(source, ['#include "c2837x_block_project.h"' newline ...
    'int main(void) { return 0; }' newline]);
positiveObject = fullfile(root, 'core_api_probe.o');
[positiveStatus, positiveOutput] = system(sprintf( ...
    'gcc -std=c11 -Wall -Wextra -Werror -I"%s" -I"%s" -c "%s" -o "%s" 2>&1', ...
    fullfile(repositoryRoot, 'tests', 'dsp_host', 'include'), ...
    fullfile(project.output.dsp_root, 'inc'), source, positiveObject));
copyRoot = fullfile(root, 'api_mismatch_copy');
copyfile(project.output.dsp_root, copyRoot);
copyHeader = fullfile(copyRoot, 'inc', 'c2837x_block.h');
changed = regexprep(fileread(copyHeader), ...
    '(#define C2837X_BLOCK_CORE_API_VERSION\s+)1u', '$12u', 'once');
write_text(copyHeader, changed);
negativeObject = fullfile(root, 'core_api_mismatch.o');
[negativeStatus, negativeOutput] = system(sprintf( ...
    'gcc -std=c11 -Wall -Wextra -Werror -I"%s" -I"%s" -c "%s" -o "%s" 2>&1', ...
    fullfile(repositoryRoot, 'tests', 'dsp_host', 'include'), ...
    fullfile(copyRoot, 'inc'), source, negativeObject));
result = struct('expected', expected, 'actual', actual, ...
    'positive_status', positiveStatus, 'positive_output', positiveOutput, ...
    'negative_status', negativeStatus, 'negative_output', negativeOutput);
end

function symbols = global_symbols(objects)
symbols = {};
for object = objects
    [status, output] = system(sprintf( ...
        'nm -g --defined-only "%s" 2>&1', object{1}));
    assert(status == 0, output);
    tokens = regexp(output, '^\S+\s+[A-Z]\s+(\S+)$', ...
        'tokens', 'lineanchors');
    symbols = [symbols cellfun(@(value) value{1}, tokens, ...
        'UniformOutput', false)]; %#ok<AGROW>
end
end

function names = expected_instance_symbols(instances)
names = {};
for value = instances
    name = value{1};
    typed = strjoin(cellfun(@(part) [upper(part(1)) part(2:end)], ...
        strsplit(name, '_'), 'UniformOutput', false), '');
    names = [names {['g_' name], ['c2837x_block_' name '_config'], ...
        ['c2837x_block_' name '_iodevice_channel'], ...
        ['c2837x_block_' name '_rx_frame_words'], ...
        ['c2837x_block_' name '_tx_frame_words'], ...
        ['c2837x_block_' name '_input_object'], ...
        ['c2837x_block_' name '_output_object'], ...
        ['c2837x_block_' name '_decode_input'], ...
        ['c2837x_block_' name '_encode_output'], [typed '_OnStart'], ...
        [typed '_OnStep'], [typed '_OnStop']}]; %#ok<AGROW>
end
end

function duplicates = duplicate_symbols(symbols)
values = unique(symbols);
duplicates = values(cellfun(@(name) sum(strcmp(symbols, name)) > 1, values));
end

function result = compile_temporary_main(repositoryRoot, project, root)
text = sprintf([ ...
    '#include "c2837x_block_project.h"\n\n' ...
    'int main(void)\n{\n' ...
    '    if (C2837xBlock_PlatformInit() != C2837X_BLOCK_PLATFORM_OK)\n' ...
    '    {\n        return 1;\n    }\n\n' ...
    '    C2837xBlock_Init(&g_axis_a);\n' ...
    '    C2837xBlock_Init(&g_axis_b);\n\n' ...
    '    for (;;)\n    {\n' ...
    '        C2837xBlock_Run(&g_axis_a);\n' ...
    '        C2837xBlock_Run(&g_axis_b);\n    }\n}\n']);
source = fullfile(root, 'temporary_main.c');
write_text(source, text);
object = fullfile(root, 'temporary_main.o');
[status, output] = system(sprintf( ...
    'gcc -std=c11 -Wall -Wextra -Werror -I"%s" -I"%s" -c "%s" -o "%s" 2>&1', ...
    fullfile(repositoryRoot, 'tests', 'dsp_host', 'include'), ...
    fullfile(project.output.dsp_root, 'inc'), source, object));
includes = regexp(text, '#include\s+"([^"]+)"', 'tokens');
includes = cellfun(@(value) value{1}, includes, 'UniformOutput', false);
candidates = c2837x_block_build_dsp_candidates(project);
result = struct('status', status, 'output', output, ...
    'includes', {includes}, 'init_count', numel(regexp(text, ...
    'C2837xBlock_Init\(&g_', 'match')), 'run_count', numel(regexp(text, ...
    'C2837xBlock_Run\(&g_', 'match')), 'source_path', source, ...
    'candidates', candidates);
end

function paths = relative_targets(candidates, root)
paths = cellfun(@(path) slash(path(numel(root) + 2:end)), ...
    {candidates.target_path}, 'UniformOutput', false);
end

function hashes = interface_hashes(project)
hashes = zeros(1, numel(project.instances), 'uint32');
for index = 1:numel(project.instances)
    [~, hashes(index)] = c2837x_block_build_interface_hash(project, index);
end
end

function audit = forbidden_audit(root)
files = tree_files(root);
filePattern = ['(^|/)(main\.[ch]|.*\.project|\.project|\.cproject|' ...
    '.*\.cmd|.*\.gel|startup.*|codestart.*|vector.*|interrupt_vector.*|' ...
    'manifest.*|.*\.slx|.*\.mex.*|.*_sfun\.[ch]|build_.*_sfun\.m|' ...
    'c2837x_block_(config|user_config|algorithm)\.[ch])$'];
badFiles = files(~cellfun(@isempty, regexp(files, filePattern, 'once')));
text = tree_text(root);
patterns = {'\bg_ctx\b', 'C2837xBlock_Init\s*\(\s*\)', ...
    'C2837xBlock_Run\s*\(\s*\)', '\bRunAll\b', '\bInitAll\b'};
badSymbols = patterns(~cellfun(@isempty, regexp(text, patterns, 'once')));
audit = struct('files', {badFiles}, 'symbols', {badSymbols}, ...
    'c_includes', numel(regexp(text, '#include\s+"[^"]+\.c"', 'match')));
end

function text = tree_text(root)
files = [dir(fullfile(root, '**', '*.c')); dir(fullfile(root, '**', '*.h'))];
parts = cellfun(@(folder, name) fileread(fullfile(folder, name)), ...
    {files.folder}, {files.name}, 'UniformOutput', false);
text = strjoin(parts, newline);
end

function audit = wire_audit(project, layout)
matches = true;
assertions = true;
for index = 1:numel(layout.instances)
    item = layout.instances(index);
    macro = upper(item.internal_name);
    config = fileread(fullfile(project.output.dsp_root, 'inc', ...
        [item.internal_name '_config.h']));
    io = fileread(fullfile(project.output.dsp_root, 'src', ...
        [item.internal_name '_io.c']));
    expected = {sprintf('#define %s_INPUT_DATA_OCTETS          %uu', ...
        macro, item.input_data_octets), ...
        sprintf('#define %s_OUTPUT_DATA_OCTETS         %uu', ...
        macro, item.output_data_octets), ...
        sprintf('#define %s_RX_FRAME_WORDS             %uu', ...
        macro, item.rx_frame_words), ...
        sprintf('#define %s_TX_FRAME_WORDS             %uu', ...
        macro, item.tx_frame_words)};
    matches = matches && all(cellfun(@(value) contains(config, value), expected));
    assertions = assertions && contains(io, ...
        'sizeof(float) * CHAR_BIT == 32') && contains(io, ...
        'sizeof(long double) * CHAR_BIT == 64') && contains(io, ...
        'RX_FRAME_WORDS * (Uint32)2u') && contains(io, ...
        'TX_FRAME_WORDS * (Uint32)2u');
end
audit = struct('config_matches', matches, ...
    'assertions_present', assertions);
end

function bytes = candidate_bytes(candidates)
bytes = {candidates.content_bytes};
end

function times = target_times(candidates)
times = zeros(1, numel(candidates));
for index = 1:numel(candidates)
    info = dir(candidates(index).target_path);
    times(index) = info.datenum;
end
end

function count = folded_unique_count(paths)
count = numel(unique(cellfun(@lower, paths, 'UniformOutput', false)));
end

function path = normalized(path)
parent = fileparts(path);
if ~isfolder(parent)
    mkdir(parent);
end
path = c2837x_block_normalize_absolute_path(path);
end

function write_bytes(path, bytes)
parent = fileparts(path);
if ~isfolder(parent)
    mkdir(parent);
end
fileID = fopen(path, 'wb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
assert(fwrite(fileID, bytes, 'uint8') == numel(bytes));
clear cleanup
end

function write_text(path, text)
write_bytes(path, reshape(uint8(unicode2native(text, 'UTF-8')), 1, []));
end

function bytes = read_bytes(path)
fileID = fopen(path, 'rb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
clear cleanup
end

function value = slash(value)
value = strrep(value, '\', '/');
end

function tf = has_errors(issues)
tf = any(strcmp({issues.severity}, 'Error'));
end
