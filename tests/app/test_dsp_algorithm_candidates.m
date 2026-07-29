classdef test_dsp_algorithm_candidates < matlab.unittest.TestCase
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
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.RepositoryRoot, 'tests', 'app', 'fixtures')));
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
        function testTypedHeaderMapsTypesDimensionsAndOrder(testCase)
            project = base_project(testCase.WorkFolder, {'axis_x'});
            project.instances.inputs = variables( ...
                {'a','b','c','d','e','f'}, ...
                {'int16','uint16','int32','uint32','single','double'}, ...
                [1 2 1 3 1 4]);
            project.instances.outputs = variables( ...
                {'oa','ob','oc','od','oe','of'}, ...
                {'double','single','uint32','int32','uint16','int16'}, ...
                [1 2 1 3 1 4]);

            rendered = c2837x_block_render_dsp_algorithm_files(project);
            header = text_of(rendered.algorithm_header_bytes);

            testCase.verifyEqual(field_declarations(header, 'AxisX_InputData'), { ...
                'int16_t a;', 'uint16_t b[2];', 'int32_t c;', ...
                'uint32_t d[3];', 'float e;', 'long double f[4];'});
            testCase.verifyEqual(field_declarations(header, 'AxisX_OutputData'), { ...
                'long double oa;', 'float ob[2];', 'uint32_t oc;', ...
                'int32_t od[3];', 'uint16_t oe;', 'int16_t of[4];'});
            testCase.verifyTrue(contains(header, '#include <stdint.h>'));
            testCase.verifyTrue(contains(header, 'int16 AxisX_OnStart(void);'));
            testCase.verifyTrue(contains(header, 'const AxisX_InputData *input'));
            testCase.verifyTrue(contains(header, 'AxisX_OutputData *output'));
            testCase.verifyTrue(contains(header, 'void AxisX_OnStop(void);'));
            testCase.verifyFalse(any(contains(header, ...
                {'void *','step_index','protocol','w5300'}, 'IgnoreCase', true)));
        end

        function testNamesAreSharedAndInstanceSpecific(testCase)
            project = base_project(testCase.WorkFolder, ...
                {'axis_x','thermal_monitor'});

            algorithms = c2837x_block_render_dsp_algorithm_files(project);
            configs = c2837x_block_render_dsp_instance_config_files(project);

            testCase.verifyEqual(c2837x_block_build_instance_c_names('axis_x'), ...
                struct('internal_name','axis_x','macro_prefix','AXIS_X', ...
                'typed_prefix','AxisX'));
            testCase.verifyTrue(contains(text_of(algorithms(1).algorithm_header_bytes), ...
                'AxisX_InputData'));
            testCase.verifyTrue(contains(text_of(algorithms(2).algorithm_header_bytes), ...
                'ThermalMonitor_InputData'));
            testCase.verifyTrue(contains(text_of(configs(1).config_source_bytes), ...
                'AxisX_OnStep'));
            testCase.verifyTrue(contains(text_of(configs(2).config_source_bytes), ...
                'ThermalMonitor_OnStep'));
        end

        function testCandidateBuilderRejectsTypedPrefixCollisions(testCase)
            testCase.verifyError(@() build_conflicting_candidates( ...
                testCase.WorkFolder, 'axis_x', 'axisX'), ...
                'C2837xBlock:DspInstance:CNameConflict');
            testCase.verifyError(@() build_conflicting_candidates( ...
                testCase.WorkFolder, 'axis_x', 'AxisX'), ...
                'C2837xBlock:DspInstance:CNameConflict');
            testCase.verifyError(@() build_conflicting_candidates( ...
                testCase.WorkFolder, 'motor_ctrl', 'motorCtrl'), ...
                'C2837xBlock:DspInstance:CNameConflict');
        end

        function testHeaderChangeIsolationAndTextInputs(testCase)
            project = base_project(testCase.WorkFolder, {'axis_x'});
            first = c2837x_block_render_dsp_algorithm_files(project);
            ignored = project;
            ignored.instances.display_name = 'Changed';
            ignored.instances.sample_time_sec = 0.25;
            ignored.instances.max_payload_size_bytes = uint32(2048);
            ignored.instances.interface_hash = uint32(123);
            ignored.common.abi = 'coffabi';
            ignored.common.network.ip = '10.0.0.2';
            strings = project;
            strings.instances.internal_name = "axis_x";
            strings.instances.inputs.name = "command";
            strings.instances.outputs.name = "feedback";
            changed = project;
            changed.instances.inputs.dim = 2;

            ignoredHeader = c2837x_block_render_dsp_algorithm_files(ignored);
            stringHeader = c2837x_block_render_dsp_algorithm_files(strings);
            changedHeader = c2837x_block_render_dsp_algorithm_files(changed);

            testCase.verifyEqual(ignoredHeader.algorithm_header_bytes, ...
                first.algorithm_header_bytes);
            testCase.verifyEqual(stringHeader.algorithm_header_bytes, ...
                first.algorithm_header_bytes);
            testCase.verifyNotEqual(changedHeader.algorithm_header_bytes, ...
                first.algorithm_header_bytes);
        end

        function testConfigDefinesOnlyNonWireAdapters(testCase)
            project = base_project(testCase.WorkFolder, {'axis_x'});

            rendered = c2837x_block_render_dsp_instance_config_files(project);
            source = text_of(rendered.config_source_bytes);

            testCase.verifyTrue(contains(source, ...
                'static void c2837x_block_axis_x_reset_io('));
            testCase.verifyTrue(contains(source, ...
                'memset(input_object, 0, sizeof(AxisX_InputData));'));
            testCase.verifyTrue(contains(source, ...
                'memset(output_object, 0, sizeof(AxisX_OutputData));'));
            testCase.verifyTrue(contains(source, ...
                'static int16 c2837x_block_axis_x_on_start('));
            testCase.verifyTrue(contains(source, ...
                'static int16 c2837x_block_axis_x_on_step('));
            testCase.verifyTrue(contains(source, ...
                'static void c2837x_block_axis_x_on_stop('));
            testCase.verifyTrue(contains(source, ...
                'return AxisX_OnStep('));
            testCase.verifyTrue(contains(source, 'AxisX_OnStop();'));
            testCase.verifyTrue(contains(source, ...
                'extern int16 c2837x_block_axis_x_decode_input('));
            testCase.verifyTrue(contains(source, ...
                'extern int16 c2837x_block_axis_x_encode_output('));
            testCase.verifyEmpty(regexp(source, ...
                '(static|extern)\s+int16\s+c2837x_block_axis_x_decode_input\s*\([^;]*\)\s*\{', ...
                'once'));
            testCase.verifyEmpty(regexp(source, ...
                '^Uint16 c2837x_block_axis_x_rx_frame_words\[', ...
                'once', 'lineanchors'));
            testCase.verifyEmpty(regexp(source, ...
                '^C2837xW5300Channel\s+c2837x_block_axis_x_iodevice_channel\s*=', ...
                'once', 'lineanchors'));
        end

        function testGeneratedExampleAndUserProtection(testCase)
            project = base_project(testCase.WorkFolder, {'axis_x'});

            candidates = c2837x_block_build_dsp_candidates(project);
            algorithm = find_candidate(candidates, 'axis_x_algorithm.c');
            source = text_of(algorithm.content_bytes);
            mkdir(fileparts(algorithm.target_path));
            missing = c2837x_block_compare_candidate_files(algorithm);
            write_bytes(algorithm.target_path, algorithm.content_bytes);
            same = c2837x_block_compare_candidate_files(algorithm);
            write_bytes(algorithm.target_path, uint8('custom'));
            different = c2837x_block_compare_candidate_files(algorithm);

            testCase.verifyEqual(algorithm.category, 'user');
            testCase.verifyTrue(contains(source, 'USER-EDITABLE FILE'));
            testCase.verifyTrue(contains(source, 'AxisX_OnStart'));
            testCase.verifyTrue(contains(source, 'AxisX_OnStep'));
            testCase.verifyTrue(contains(source, 'AxisX_OnStop'));
            testCase.verifyFalse(any(contains(source, ...
                {'wire','protocol','w5300','void *'}, 'IgnoreCase', true)));
            testCase.verifyEqual({missing.default_action same.default_action ...
                different.default_action}, {'create','skip','keep'});
            different.selected_action = 'replace';
            testCase.verifyEmpty(c2837x_block_validate_candidate_actions(different));
        end

        function testExternalCopyPreservesRawByteMatrix(testCase)
            verify_raw_matrix(testCase, testCase.WorkFolder);
        end

        function testExternalCopyAcceptsReadonlyFileWhenSupported(testCase)
            sourcePath = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'readonly.c'));
            sourceBytes = uint8('readonly');
            write_bytes(sourcePath, sourceBytes);
            [changed, ~] = fileattrib(sourcePath, '-w');
            testCase.assumeTrue(changed, ...
                'Read-only source files cannot be created on this platform.');
            testCase.addTeardown(@() fileattrib(sourcePath, '+w'));
            project = base_project(testCase.WorkFolder, {'axis_x'});
            project.instances.algorithm.mode = 'external_copy';
            project.instances.algorithm.source_path = sourcePath;

            candidate = find_candidate( ...
                c2837x_block_build_dsp_candidates(project), ...
                'axis_x_algorithm.c');

            testCase.verifyEqual(candidate.content_bytes, sourceBytes);
        end

        function testExternalReferenceOmitsSourceAndSnapshotsBytes(testCase)
            sourcePath = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'reference.c'));
            write_bytes(sourcePath, uint8('void reference(void) {}'));
            project = base_project(testCase.WorkFolder, {'axis_x'});
            project.instances.algorithm.mode = 'external_reference';
            project.instances.algorithm.source_path = sourcePath;

            [candidates, dependencies] = c2837x_block_build_dsp_candidates(project);
            [snapshot, issues] = c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);

            testCase.verifyNumElements(candidates, 24);
            testCase.verifyFalse(any(endsWith({candidates.target_path}, ...
                'axis_x_algorithm.c')));
            testCase.verifyTrue(any(endsWith({candidates.target_path}, ...
                'axis_x_algorithm.h')));
            testCase.verifyTrue(any(strcmp({issues.code}, ...
                'EXTERNAL_REFERENCE_NOT_COPIED')));
            testCase.verifyNumElements(snapshot.external_sources, 1);
            testCase.verifyEqual(snapshot.external_sources.content_bytes, ...
                uint8('void reference(void) {}'));
            testCase.verifyFalse(any(strcmp({dependencies.role}, ...
                'external_source')));
        end

        function testMixedModeCandidateCountAndOrder(testCase)
            sourcePath = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'shared.c'));
            write_bytes(sourcePath, uint8('shared'));
            project = base_project(testCase.WorkFolder, ...
                {'generated','copied','referenced'});
            project.instances(2).algorithm.mode = 'external_copy';
            project.instances(2).algorithm.source_path = sourcePath;
            project.instances(3).algorithm.mode = 'external_reference';
            project.instances(3).algorithm.source_path = sourcePath;

            candidates = c2837x_block_build_dsp_candidates(project);
            model = c2837x_block_build_dsp_output_model(project);

            testCase.verifyNumElements(candidates, 36);
            testCase.verifyEqual({candidates.target_path}, ...
                {model.files([model.files.candidate_available]).target_path});
            testCase.verifyFalse(any(endsWith({candidates.target_path}, ...
                'referenced_algorithm.c')));
        end

        function testExternalSourceChangeInvalidatesSnapshot(testCase)
            sourcePath = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'copy.c'));
            write_bytes(sourcePath, uint8('first'));
            project = base_project(testCase.WorkFolder, {'axis_x'});
            project.instances.algorithm.mode = 'external_copy';
            project.instances.algorithm.source_path = sourcePath;
            [candidates, dependencies] = c2837x_block_build_dsp_candidates(project);
            [snapshot, issues] = c2837x_block_create_preview_snapshot( ...
                project, candidates, dependencies);
            testCase.assertFalse(any(strcmp({issues.severity}, 'Error')));
            write_bytes(sourcePath, uint8('second'));

            [isValid, changed] = c2837x_block_validate_preview_snapshot( ...
                snapshot, project, candidates, dependencies);

            testCase.verifyFalse(isValid);
            testCase.verifyTrue(any(strcmp({changed.code}, ...
                'SNAPSHOT_EXTERNAL_SOURCE_CHANGED')));
        end

        function testResolverRejectsMissingDirectoryAndWrongExtension(testCase)
            missing = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'missing.c'));
            directory = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'directory.c'));
            mkdir(directory);
            header = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'algorithm.h'));
            write_bytes(header, uint8(1));
            cpp = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'algorithm.cpp'));
            write_bytes(cpp, uint8(1));
            noExtension = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'algorithm'));
            write_bytes(noExtension, uint8(1));

            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(missing), ...
                'C2837xBlock:AlgorithmSource:Missing');
            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(directory), ...
                'C2837xBlock:AlgorithmSource:IsDirectory');
            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(header), ...
                'C2837xBlock:AlgorithmSource:ExtensionInvalid');
            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(cpp), ...
                'C2837xBlock:AlgorithmSource:ExtensionInvalid');
            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(noExtension), ...
                'C2837xBlock:AlgorithmSource:ExtensionInvalid');
        end

        function testCandidateBuilderRejectsMissingAndDuplicateAlgorithmRender(testCase)
            folder = fullfile(testCase.WorkFolder, 'shadow-algorithm-renderer');
            mkdir(folder);
            addpath(folder, '-begin');
            testCase.addTeardown(@() cleanup_shadow_renderer(folder));
            project = base_project(testCase.WorkFolder, {'axis_x'});
            write_shadow_algorithm_renderer(folder, 0);
            clear c2837x_block_render_dsp_algorithm_files
            rehash;

            testCase.verifyError( ...
                @() c2837x_block_build_dsp_candidates(project), ...
                'C2837xBlock:Generation:InstanceRenderMismatch');
            write_shadow_algorithm_renderer(folder, 2);
            clear c2837x_block_render_dsp_algorithm_files
            rehash;
            testCase.verifyError( ...
                @() c2837x_block_build_dsp_candidates(project), ...
                'C2837xBlock:Generation:InstanceRenderMismatch');
        end

        function testResolverRejectsSymbolicLinkWhenSupported(testCase)
            target = c2837x_block_normalize_absolute_path( ...
                fullfile(testCase.WorkFolder, 'target.c'));
            link = fullfile(testCase.WorkFolder, 'link.c');
            write_bytes(target, uint8('x'));
            created = create_symbolic_link(link, target);
            testCase.assumeTrue(created, ...
                'Symbolic-link creation is unavailable on this platform.');
            link = char(java.io.File(link).getAbsolutePath());

            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(link), ...
                'C2837xBlock:AlgorithmSource:SymbolicLink');
        end

        function testResolverRejectsBrokenSymbolicLinkWhenSupported(testCase)
            missingTarget = fullfile(testCase.WorkFolder, 'missing-target.c');
            link = fullfile(testCase.WorkFolder, 'broken.c');
            created = create_symbolic_link(link, missingTarget);
            testCase.assumeTrue(created, ...
                'Symbolic-link creation is unavailable on this platform.');
            link = char(java.io.File(link).getAbsolutePath());

            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(link), ...
                'C2837xBlock:AlgorithmSource:SymbolicLink');
        end

        function testResolverRejectsFifoOnUnix(testCase)
            testCase.assumeFalse(ispc, ...
                'Windows does not provide a portable FIFO fixture.');
            fifoPath = fullfile(testCase.WorkFolder, 'source.c');
            created = create_fifo(fifoPath);
            testCase.assumeTrue(created, 'mkfifo is unavailable.');

            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(fifoPath), ...
                'C2837xBlock:AlgorithmSource:NotRegularFile');
        end

        function testResolverRejectsUnreadableFileOnUnix(testCase)
            testCase.assumeFalse(ispc, ...
                'Windows current-account permissions do not reliably create an unreadable file.');
            sourcePath = fullfile(testCase.WorkFolder, 'unreadable.c');
            write_bytes(sourcePath, uint8('x'));
            [status, ~] = system(sprintf('chmod 000 "%s"', sourcePath));
            testCase.assumeEqual(status, 0, 'chmod is unavailable.');
            testCase.addTeardown(@() system(sprintf('chmod 600 "%s"', sourcePath)));
            readable = java.nio.file.Files.isReadable(java.io.File(sourcePath).toPath());
            testCase.assumeFalse(readable, ...
                'The current account can still read the permission fixture.');

            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(sourcePath), ...
                'C2837xBlock:AlgorithmSource:Unreadable');
        end

        function testResolverRejectsUppercaseCOnCaseSensitiveFilesystem(testCase)
            sourcePath = fullfile(testCase.WorkFolder, 'upper.C');
            write_bytes(sourcePath, uint8('x'));
            testCase.assumeFalse(isfile(fullfile(testCase.WorkFolder, 'upper.c')), ...
                'The current filesystem is case-insensitive.');

            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(sourcePath), ...
                'C2837xBlock:AlgorithmSource:ExtensionInvalid');
        end

        function testResolverRejectsDistinctUpperAndLowerFiles(testCase)
            upperPath = fullfile(testCase.WorkFolder, 'distinct.C');
            lowerPath = fullfile(testCase.WorkFolder, 'distinct.c');
            write_bytes(upperPath, uint8('upper'));
            write_bytes(lowerPath, uint8('lower'));
            testCase.assumeNotEqual(read_bytes(upperPath), read_bytes(lowerPath), ...
                'The current filesystem does not preserve distinct case variants.');

            testCase.verifyError( ...
                @() c2837x_block_resolve_external_algorithm_source(upperPath), ...
                'C2837xBlock:AlgorithmSource:ExtensionInvalid');
        end

        function testTemplateBytesAreDeterministicAndNormalized(testCase)
            project = base_project(testCase.WorkFolder, {'axis_x'});

            first = c2837x_block_render_dsp_algorithm_files(project);
            second = c2837x_block_render_dsp_algorithm_files(project);

            testCase.verifyEqual(second, first);
            verify_template_bytes(testCase, first.algorithm_header_bytes);
            verify_template_bytes(testCase, first.algorithm_source_bytes);
            testCase.verifyFalse(isfolder(project.output.dsp_root));
        end
    end
end

function project = base_project(root, names)
project = c2837x_block_create_default_project();
project.common.network.mac = uint8([2 0 0 0 0 1]);
project.common.network.ip = '192.168.1.10';
project.common.network.gateway = '0.0.0.0';
project.common.network.subnet = '255.255.255.0';
project.output.dsp_root = c2837x_block_normalize_absolute_path(fullfile(root, 'dsp'));
project.output.sfun_root = c2837x_block_normalize_absolute_path(fullfile(root, 'sfun'));
template = c2837x_block_create_default_instance();
template.inputs = variables({'command'}, {'single'}, 1);
template.outputs = variables({'feedback'}, {'double'}, 1);
instances = repmat(template, 1, numel(names));
for index = 1:numel(names)
    instances(index).display_name = names{index};
    instances(index).internal_name = names{index};
    instances(index).iodevice.settings.socket_number = uint16(index - 1);
    instances(index).iodevice.settings.tcp_port = uint16(4999 + index);
end
project.instances = instances;
end

function build_conflicting_candidates(root, firstName, secondName)
project = base_project(root, {firstName, secondName});
c2837x_block_build_dsp_candidates(project);
end

function values = variables(names, types, dimensions)
values = repmat(struct('name','','type','','dim',1), 1, numel(names));
for index = 1:numel(names)
    values(index) = struct('name', names{index}, 'type', types{index}, ...
        'dim', dimensions(index));
end
end

function fields = field_declarations(header, typeName)
endToken = ['} ' typeName ';'];
endPosition = strfind(header, endToken);
assert(isscalar(endPosition));
prefix = header(1:endPosition - 1);
startToken = ['typedef struct' newline '{' newline];
startPositions = strfind(prefix, startToken);
assert(~isempty(startPositions));
body = prefix(startPositions(end) + numel(startToken):end);
fields = strtrim(strsplit(strtrim(body), newline));
end

function candidate = find_candidate(candidates, filename)
matches = endsWith({candidates.target_path}, filename);
assert(sum(matches) == 1);
candidate = candidates(matches);
end

function verify_raw_matrix(testCase, root)
matrix = { ...
    uint8(sprintf('void a(void) {}\n')), ...
    uint8([239 187 191 double('void b(void) {}') 10]), ...
    uint8([double('void c(void) {}') 13 10]), ...
    uint8('void d(void) {}'), ...
    reshape(uint8(unicode2native('/* 中文 */', 'UTF-8')), 1, []), ...
    zeros(1, 0, 'uint8')};
for index = 1:numel(matrix)
    sourcePath = c2837x_block_normalize_absolute_path( ...
        fullfile(root, sprintf('external-%u.c', index)));
    write_bytes(sourcePath, matrix{index});
    project = base_project(root, {'axis_x'});
    project.instances.algorithm.mode = 'external_copy';
    project.instances.algorithm.source_path = sourcePath;
    candidates = c2837x_block_build_dsp_candidates(project);
    candidate = find_candidate(candidates, 'axis_x_algorithm.c');
    testCase.verifyEqual(candidate.content_bytes, matrix{index});
    testCase.verifyEqual(candidate.category, 'user');
end
end

function created = create_symbolic_link(link, target)
created = false;
try
    linkPath = java.io.File(link).toPath();
    targetPath = java.io.File(target).toPath();
    java.nio.file.Files.createSymbolicLink(linkPath, targetPath, ...
        javaArray('java.nio.file.attribute.FileAttribute', 0));
    created = true;
catch
end
end

function created = create_fifo(path)
[status, ~] = system(sprintf('mkfifo "%s"', path));
created = status == 0;
end

function write_shadow_algorithm_renderer(folder, count)
text = sprintf([ ...
    'function r=c2837x_block_render_dsp_algorithm_files(~)\n' ...
    'p=struct(''instance_index'',1,''internal_name'',''axis_x'',...\n' ...
    '''algorithm_header_bytes'',uint8(10),...\n' ...
    '''algorithm_source_available'',true,...\n' ...
    '''algorithm_source_bytes'',uint8(10),...\n' ...
    '''algorithm_mode'',''generated_example'',...\n' ...
    '''external_source_path'','''');\n' ...
    'r=repmat(p,1,%u);\nend\n'], count);
fileID = fopen(fullfile(folder, ...
    'c2837x_block_render_dsp_algorithm_files.m'), 'w');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fprintf(fileID, '%s', text);
clear cleanup
end

function cleanup_shadow_renderer(folder)
rmpath(folder);
clear c2837x_block_render_dsp_algorithm_files
rehash;
end

function verify_template_bytes(testCase, bytes)
testCase.verifyClass(bytes, 'uint8');
testCase.verifyFalse(starts_with(bytes, uint8([239 187 191])));
testCase.verifyFalse(any(bytes == 13));
testCase.verifyEqual(bytes(end), uint8(10));
testCase.verifyNotEqual(bytes(end - 1), uint8(10));
testCase.verifyEmpty(regexp(text_of(bytes), '[ \t]+\n', 'once'));
end

function tf = starts_with(bytes, prefix)
tf = numel(bytes) >= numel(prefix) && isequal(bytes(1:numel(prefix)), prefix);
end

function text = text_of(bytes)
text = native2unicode(bytes, 'UTF-8');
end

function write_bytes(path, bytes)
fileID = fopen(path, 'wb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
fwrite(fileID, bytes, 'uint8');
clear cleanup
end


function bytes = read_bytes(path)
fileID = fopen(path, 'rb');
assert(fileID >= 0);
cleanup = onCleanup(@() fclose(fileID));
bytes = reshape(fread(fileID, Inf, '*uint8'), 1, []);
clear cleanup
end
