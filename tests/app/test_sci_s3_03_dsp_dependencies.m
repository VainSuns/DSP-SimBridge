classdef test_sci_s3_03_dsp_dependencies < matlab.unittest.TestCase
    properties
        WorkFolder
        RepositoryRoot
    end

    methods (TestClassSetup)
        function addAppPath(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.RepositoryRoot = root;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
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
        function testW5300OnlyUsesOnlyW5300Transport(testCase)
            project = make_project(testCase.WorkFolder, 'w5300');

            [candidates, dependencies, issues] = ...
                c2837x_block_build_dsp_candidates(project);
            model = c2837x_block_build_dsp_output_model(project);

            testCase.verifyEmpty(issues);
            testCase.verifyEqual(relative_paths(model), expected_paths('w5300'));
            testCase.verifyEqual(relative_candidate_paths(candidates), ...
                expected_paths('w5300'));
            verify_transport_dependencies(testCase, dependencies, ...
                'w5300', false, true);
            testCase.verifyEqual(numel(candidates), 25);
            testCase.verifyFalse(any(contains({candidates.target_path}, ...
                'c2837x_block_sci')));
        end

        function testSciOnlyUsesOnlySciTransport(testCase)
            project = make_project(testCase.WorkFolder, 'sci');

            [candidates, dependencies, issues] = ...
                c2837x_block_build_dsp_candidates(project);
            model = c2837x_block_build_dsp_output_model(project);

            testCase.verifyEmpty(issues);
            testCase.verifyEqual(relative_paths(model), expected_paths('sci'));
            testCase.verifyEqual(relative_candidate_paths(candidates), ...
                expected_paths('sci'));
            verify_transport_dependencies(testCase, dependencies, ...
                'sci', true, false);
            testCase.verifyEqual(numel(candidates), 20);
            verify_sci_binding(testCase, candidates);
        end

        function testMixedUsesBothTransportsAndIsDeterministic(testCase)
            project = make_project(testCase.WorkFolder, 'mixed');

            [firstCandidates, firstDependencies, firstIssues] = ...
                c2837x_block_build_dsp_candidates(project);
            [secondCandidates, secondDependencies, secondIssues] = ...
                c2837x_block_build_dsp_candidates(project);

            testCase.verifyEmpty(firstIssues);
            testCase.verifyEmpty(secondIssues);
            testCase.verifyEqual(firstCandidates, secondCandidates);
            testCase.verifyEqual(firstDependencies, secondDependencies);
            testCase.verifyEqual(relative_candidate_paths(firstCandidates), ...
                expected_paths('mixed'));
            verify_transport_dependencies(testCase, firstDependencies, ...
                'mixed', true, true);
            testCase.verifyEqual(numel(firstCandidates), 33);
        end

        function testGeneratedTreesHaveTransportCompileClosure(testCase)
            modes = {'w5300', 'sci', 'mixed'};
            for modeIndex = 1:numel(modes)
                mode = modes{modeIndex};
                project = make_project(testCase.WorkFolder, mode);
                project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
                    fullfile(testCase.WorkFolder, [mode '_compile_dsp']));
                project.output.sfun_root = c2837x_block_normalize_absolute_path( ...
                    fullfile(testCase.WorkFolder, [mode '_compile_sfun']));
                [candidates, dependencies, issues] = ...
                    c2837x_block_build_dsp_candidates(project);
                [snapshot, snapshotIssues] = ...
                    c2837x_block_create_preview_snapshot( ...
                    project, candidates, dependencies);
                [~, commitIssues] = c2837x_block_commit_preview_snapshot( ...
                    snapshot, project, candidates, dependencies);

                testCase.verifyEmpty(issues);
                testCase.verifyFalse(has_errors(snapshotIssues), ...
                    issue_text(snapshotIssues));
                testCase.verifyFalse(has_errors(commitIssues), ...
                    issue_text(commitIssues));
                verify_generated_closure(testCase, testCase.RepositoryRoot, ...
                    project, candidates, mode, testCase.WorkFolder);
            end
        end
    end
end

function project = make_project(root, mode)
project = c2837x_block_create_default_project();
project.output.dsp_root = c2837x_block_normalize_absolute_path( ...
    fullfile(root, [mode '_dsp']));

w5300 = c2837x_block_create_default_instance();
w5300.display_name = 'Network';
w5300.internal_name = 'network';
w5300.inputs = struct('name', 'command', 'type', 'single', 'dim', 1);
w5300.outputs = struct('name', 'feedback', 'type', 'single', 'dim', 1);

sci = c2837x_block_create_default_instance();
sci.display_name = 'Serial';
sci.internal_name = 'serial';
sci.inputs = w5300.inputs;
sci.outputs = w5300.outputs;
sci.iodevice = c2837x_block_create_iodevice('sci');
sci.iodevice.settings.module = 'SCI-B';
sci.iodevice.settings.baud = uint32(115200);
sci.iodevice.settings.rx_gpio = 'GPIO19';
sci.iodevice.settings.tx_gpio = 'GPIO14';
sci.iodevice.settings.rx_pin_type = 'Standard';
sci.iodevice.settings.rx_qualification = 'Sync';
sci.iodevice.settings.tx_pin_type = 'Pull-up';
sci.iodevice.settings.ctrl_gpio = 'None';
sci.iodevice.settings.ctrl_pin_type = 'Standard';
sci.iodevice.settings.ctrl_tx_active_level = 'Low';

switch mode
    case 'w5300'
        project.instances = w5300;
    case 'sci'
        project.instances = sci;
    case 'mixed'
        project.instances = [w5300 sci];
    otherwise
        error('test_sci_s3_03_dsp_dependencies:InvalidMode', ...
            'Unknown project mode.');
end
end

function paths = expected_paths(mode)
paths = [expected_core_paths(mode), {'inc/c2837x_block_project.h', ...
    'src/c2837x_block_project.c'}];
instanceNames = {'network'};
if strcmp(mode, 'sci')
    instanceNames = {'serial'};
elseif strcmp(mode, 'mixed')
    instanceNames = {'network', 'serial'};
end
for index = 1:numel(instanceNames)
    name = instanceNames{index};
    paths = [paths, {['inc/' name '_config.h'], ...
        ['inc/' name '_user_config.h'], ...
        ['inc/' name '_algorithm.h'], ['src/' name '_config.c'], ...
        ['src/' name '_io.c'], ['src/' name '_algorithm.c']}]; %#ok<AGROW>
end
end

function paths = expected_core_paths(mode)
common = {'inc/c2837x_block.h', 'inc/c2837x_block_protocol.h', ...
    'inc/c2837x_block_iodevice.h'};
w5300Headers = {'inc/c2837x_w5300_regs.h', ...
    'inc/c2837x_w5300_hal.h', 'inc/c2837x_w5300_socket.h', ...
    'inc/c2837x_w5300_channel.h'};
sciHeaders = {'inc/c2837x_block_sci.h'};
commonSources = {'src/c2837x_block.c', 'src/c2837x_block_protocol.c', ...
    'src/c2837x_block_internal.h', 'src/c2837x_block_config_internal.h', ...
    'src/c2837x_block_platform.h', 'src/c2837x_block_platform.c', ...
    'src/c2837x_block_timer2.c'};
w5300Sources = {'src/c2837x_w5300_hal.c', ...
    'src/c2837x_w5300_socket.c', 'src/c2837x_w5300_channel.c'};
sciSources = {'src/c2837x_block_sci.c'};

switch mode
    case 'w5300'
        paths = [common w5300Headers commonSources w5300Sources];
    case 'sci'
        paths = [common sciHeaders commonSources sciSources];
    case 'mixed'
        paths = [common w5300Headers sciHeaders commonSources ...
            w5300Sources sciSources];
    otherwise
        error('test_sci_s3_03_dsp_dependencies:InvalidMode', ...
            'Unknown project mode.');
end
end

function paths = relative_paths(model)
paths = {model.files.relative_path};
end

function paths = relative_candidate_paths(candidates)
paths = cell(1, numel(candidates));
for index = 1:numel(candidates)
    parts = strsplit(candidates(index).target_path, filesep);
    rootIndex = find(strcmp(parts, 'inc') | strcmp(parts, 'src'), 1);
    paths{index} = strjoin(parts(rootIndex:end), '/');
end
end

function verify_transport_dependencies(testCase, dependencies, mode, ...
        expectSci, expectW5300)
identities = {dependencies.identity};
coreIdentities = identities(strcmp({dependencies.role}, 'core_source'));

testCase.verifyEqual(coreIdentities, expected_core_identities(mode));
testCase.verifyEqual(any(contains(identities, 'sci-baud-service')), ...
    expectSci);
testCase.verifyEqual(any(contains(identities, 'sci-clock-service')), ...
    expectSci);
testCase.verifyEqual(any(contains(identities, 'sci-capability-loader')), ...
    expectSci);
testCase.verifyEqual(any(contains(identities, 'sci-capability-data')), ...
    expectSci);
testCase.verifyEqual(any(contains(identities, ...
    'iodevice-definition:sci')), expectSci);
testCase.verifyEqual(any(contains(identities, ...
    'iodevice-definition:w5300_tcp')), expectW5300);
if expectSci
    testCase.verifyTrue(any(contains(coreIdentities, ...
        'c2837x_block_sci')));
else
    testCase.verifyFalse(any(contains(coreIdentities, ...
        'c2837x_block_sci')));
end
if expectW5300
    testCase.verifyTrue(any(contains(coreIdentities, ...
        'c2837x_w5300')));
else
    testCase.verifyFalse(any(contains(coreIdentities, ...
        'c2837x_w5300')));
end
testCase.verifyEqual(numel(unique(identities)), numel(identities));
end

function identities = expected_core_identities(mode)
paths = expected_core_paths(mode);
identities = cellfun(@(path) ['dsp-core-source:' path], paths, ...
    'UniformOutput', false);
end

function verify_sci_binding(testCase, candidates)
config = candidate_text(candidates, 'serial_config.c');
io = candidate_text(candidates, 'serial_io.c');
testCase.verifyTrue(contains(config, 'c2837x_block_sci_iodevice_ops'));
testCase.verifyTrue(contains(config, 'c2837x_block_serial_sci_descriptor'));
testCase.verifyTrue(contains(io, 'C2837X_BLOCK_SCI_CHANNEL_INITIALIZER'));
end

function text = candidate_text(candidates, suffix)
index = find(endsWith({candidates.target_path}, suffix), 1);
assert(~isempty(index));
text = native2unicode(candidates(index).content_bytes, 'UTF-8');
end

function verify_generated_closure(testCase, repositoryRoot, project, ...
        candidates, mode, workFolder)
root = project.output.dsp_root;
candidatePaths = relative_candidate_paths(candidates);
candidateSources = sort(candidatePaths(startsWith(candidatePaths, 'src/') & ...
    endsWith(candidatePaths, '.c')));
sourceFiles = dir(fullfile(root, 'src', '*.c'));
sourcePaths = sort(fullfile({sourceFiles.folder}, {sourceFiles.name}));
sourceRelative = sort(cellfun(@(path) slash(path(numel(root) + 2:end)), ...
    sourcePaths, 'UniformOutput', false));

testCase.verifyEqual(sourceRelative, candidateSources);
audit = include_audit(root);
testCase.verifyEqual(audit.unresolved, 0, audit.details);
testCase.verifyEqual(audit.multiple, 0, audit.details);
testCase.verifyEqual(audit.c_includes, 0, audit.details);
testCase.verifyEqual(audit.total, ...
    audit.inc_resolved + audit.src_local + audit.src_inc + ...
    audit.allowed_external);

hasW5300 = any(strcmp(mode, {'w5300', 'mixed'}));
hasSci = any(strcmp(mode, {'sci', 'mixed'}));
testCase.verifyEqual(any(contains(candidatePaths, 'c2837x_w5300_')), ...
    hasW5300);
testCase.verifyEqual(any(contains(candidatePaths, 'c2837x_block_sci')), ...
    hasSci);
testCase.verifyEqual(isfile(fullfile(root, 'inc', ...
    'c2837x_w5300_hal.h')), hasW5300);
testCase.verifyEqual(isfile(fullfile(root, 'inc', ...
    'c2837x_block_sci.h')), hasSci);
testCase.verifyEqual(isfile(fullfile(root, 'src', ...
    'c2837x_w5300_hal.c')), hasW5300);
testCase.verifyEqual(isfile(fullfile(root, 'src', ...
    'c2837x_block_sci.c')), hasSci);

projectHeader = fileread(fullfile(root, 'inc', ...
    'c2837x_block_project.h'));
coreHeader = fileread(fullfile(root, 'inc', 'c2837x_block.h'));
testCase.verifyTrue(contains(projectHeader, sprintf( ...
    '#define C2837X_BLOCK_PLATFORM_HAS_W5300  %uu', double(hasW5300))));
testCase.verifyTrue(contains(projectHeader, sprintf( ...
    '#define C2837X_BLOCK_PLATFORM_HAS_SCI    %uu', double(hasSci))));
testCase.verifyTrue(contains(projectHeader, ...
    '#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION  2u'));
testCase.verifyTrue(contains(coreHeader, ...
    '#define C2837X_BLOCK_CORE_API_VERSION  2u'));

compile = compile_sources(repositoryRoot, project, sourcePaths, ...
    fullfile(workFolder, [mode '_objects']));
testCase.verifyEqual(compile.statuses, zeros(1, numel(sourcePaths)), ...
    strjoin(compile.outputs, newline));
fprintf(['S3_03_CLOSURE mode=%s sources=%u includes=%u ' ...
    'w5300=%u sci=%u compile=PASS\n'], mode, numel(sourcePaths), ...
    audit.total, hasW5300, hasSci);
end

function result = compile_sources(repositoryRoot, project, sourcePaths, ...
        objectRoot)
mkdir(objectRoot);
flags = sprintf([ ...
    '-std=c11 -Wall -Wextra -Werror -Wno-unknown-pragmas ' ...
    '-Wno-error=int-to-pointer-cast -mlong-double-64 ' ...
    '-fstrict-aliasing -Wstrict-aliasing=2 ' ...
    '-I"%s" -I"%s"'], ...
    fullfile(project.output.dsp_root, 'inc'), ...
    fullfile(repositoryRoot, 'tests', 'dsp_host', 'include'));
statuses = zeros(1, numel(sourcePaths));
outputs = cell(1, numel(sourcePaths));
for index = 1:numel(sourcePaths)
    [~, name] = fileparts(sourcePaths{index});
    object = fullfile(objectRoot, sprintf('%02u_%s.o', index, name));
    command = sprintf( ...
        'cd /d "%s" && gcc %s -c "%s" -o "%s" 2>&1', ...
        objectRoot, flags, sourcePaths{index}, object);
    [statuses(index), outputs{index}] = system(command);
end
result = struct('statuses', statuses, 'outputs', {outputs}, ...
    'flags', flags);
end

function audit = include_audit(root)
files = [dir(fullfile(root, '**', '*.c')); dir(fullfile(root, '**', '*.h'))];
allowed = {'F28x_Project.h', 'stdint.h', 'limits.h', 'float.h', 'string.h'};
facts = transport_facts(root);
total = 0; incResolved = 0; srcLocal = 0; srcInc = 0;
external = 0; unresolved = 0; multiple = 0; incToSrc = 0;
cIncludes = 0; details = {};
for index = 1:numel(files)
    sourcePath = fullfile(files(index).folder, files(index).name);
    inInc = paths_equal(files(index).folder, fullfile(root, 'inc'));
    includes = regexp(fileread(sourcePath), ...
        '^\s*#include\s+"([^"]+)"', 'tokens', 'lineanchors');
    for include = includes
        name = include{1}{1};
        if inactive_transport_include(name, facts)
            continue;
        end
        total = total + 1;
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
    'c_includes', cIncludes, 'details', strjoin(details, newline));
end

function facts = transport_facts(root)
header = fileread(fullfile(root, 'inc', 'c2837x_block_project.h'));
facts = struct( ...
    'has_w5300', ~isempty(regexp(header, ...
    '#define\s+C2837X_BLOCK_PLATFORM_HAS_W5300\s+1u', 'once')), ...
    'has_sci', ~isempty(regexp(header, ...
    '#define\s+C2837X_BLOCK_PLATFORM_HAS_SCI\s+1u', 'once')));
end

function tf = inactive_transport_include(name, facts)
tf = (~facts.has_sci && strcmp(name, 'c2837x_block_sci.h')) || ...
    (~facts.has_w5300 && startsWith(name, 'c2837x_w5300_'));
end

function tf = paths_equal(first, second)
if ispc
    tf = strcmpi(first, second);
else
    tf = strcmp(first, second);
end
end

function tf = has_errors(issues)
tf = any(strcmp({issues.severity}, 'Error'));
end

function text = issue_text(issues)
if isempty(issues)
    text = '';
else
    text = strjoin({issues.message}, newline);
end
end

function value = slash(value)
value = strrep(value, '\', '/');
end
