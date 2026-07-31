classdef test_configurator_layout < matlab.unittest.TestCase
    properties
        App
    end

    properties (TestParameter)
        issueRoute = struct( ...
            'common', struct('code', 'COMMON', ...
                'field', 'project.common.network.ip', ...
                'main', 'Project', 'child', ''), ...
            'instance', struct('code', 'INSTANCE', ...
                'field', 'project.instances(1).display_name', ...
                'main', 'Instances', 'child', ''), ...
            'inputs', struct('code', 'INPUT', ...
                'field', 'project.instances(1).inputs(1).name', ...
                'main', 'Inputs / Outputs', 'child', 'Inputs'), ...
            'outputs', struct('code', 'OUTPUT', ...
                'field', 'project.instances(1).outputs(1).name', ...
                'main', 'Inputs / Outputs', 'child', 'Outputs'), ...
            'preview', struct('code', 'APP_PREVIEW_PROVIDER_UNAVAILABLE', ...
                'field', 'preview', 'main', 'Generation Preview', 'child', ''), ...
            'interface', struct('code', 'INTERFACE_HASH', ...
                'field', 'project.report', ...
                'main', 'Issues / Interface', ...
                'child', 'Interface Hash / Memory'))
    end

    methods (TestClassSetup)
        function addAppFolder(testCase)
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'app')));
        end
    end

    methods (TestMethodSetup)
        function createApp(testCase)
            testCase.App = create_hidden_app(testCase);
            testCase.addTeardown(@() delete(testCase.App));
        end
    end

    methods (Test)
        function testConstruction(testCase)
            testCase.verifyTrue(isvalid(testCase.App));
            testCase.verifyTrue(isvalid(testCase.App.UIFigure));
        end

        function testMainTabs(testCase)
            titles = direct_tab_titles(main_tab_group(testCase.App.UIFigure));
            expected = {'Generation Preview', 'Inputs / Outputs', ...
                'Instances', 'Issues / Interface', 'Project'};
            testCase.verifyEqual(sort(titles), sort(expected));
            testCase.verifyEqual(numel(unique(titles)), 5);
        end

        function testNestedTabs(testCase)
            testCase.verifyEqual(nested_tab_titles(testCase.App.UIFigure, ...
                'Inputs / Outputs'), sort({'Inputs', 'Outputs'}));
            testCase.verifyEqual(nested_tab_titles(testCase.App.UIFigure, ...
                'Issues / Interface'), ...
                sort({'Interface Hash / Memory', 'Issues'}));
            testCase.verifyEqual(nested_tab_titles(testCase.App.UIFigure, ...
                'Generation Preview'), ...
                sort({'Candidate Content', 'Generation Result'}));
        end

        function testRequiredButtons(testCase)
            testCase.verifyEqual(button_texts(testCase.App.UIFigure, 'Project'), ...
                sort({'Save', 'Load', 'Preview', 'Generate'}));
            testCase.verifyEqual(button_texts(testCase.App.UIFigure, 'Instances'), ...
                sort({'Add', 'Copy', 'Delete'}));
            testCase.verifyEqual(button_texts(testCase.App.UIFigure, 'Inputs'), ...
                sort({'Add', 'Remove', 'Move Up', 'Move Down'}));
            testCase.verifyEqual(button_texts(testCase.App.UIFigure, 'Outputs'), ...
                sort({'Add', 'Remove', 'Move Up', 'Move Down'}));
        end

        function testProjectPanelPlacement(testCase)
            layout = project_layout(testCase.App.UIFigure);
            testCase.verifyEqual(layout.panel.Layout.Row, 1);
            testCase.verifyEmpty(layout.secondRowChildren);
        end

        function testTableColumns(testCase)
            testCase.verifyEqual(numel(find_table(testCase.App.UIFigure, ...
                {'Display Name', 'Internal Name', 'IoDevice', 'Socket', ...
                'TCP Port', 'Sample Time'}).ColumnName), 6);
            candidateTable = find_table(testCase.App.UIFigure, ...
                {'Target Path', 'Category', 'Owner', 'Instance', 'State', ...
                'Selected Action', 'Mandatory', 'Existing Octets', ...
                'Candidate Octets'});
            testCase.verifyEqual(numel(candidateTable.ColumnName), 9);
            testCase.verifyEqual(candidateTable.ColumnFormat{6}, ...
                {'create', 'skip', 'replace', 'keep'});
        end

        function testInstanceContextLabels(testCase)
            expected = { ...
                'InputsOutputsInstanceContext', 'Current Instance: None'; ...
                'IssuesInstanceContext', ...
                'Current Instance: None | Scope: Entire Project'; ...
                'InterfaceInstanceContext', 'Current Instance: None'};
            for index = 1:size(expected, 1)
                label = find_one_by_tag(testCase, testCase.App.UIFigure, ...
                    expected{index, 1});
                testCase.verifyEqual(label.Text, expected{index, 2});
            end
        end

        function testMaxPayloadLabelAndTooltip(testCase)
            tooltip = ['Protocol safety limit only. RX/TX buffers ' ...
                'use actual legal message lengths.'];
            label = find_one_by_tag(testCase, testCase.App.UIFigure, ...
                'MaxPayloadLimitLabel');
            field = find_one_by_tag(testCase, testCase.App.UIFigure, ...
                'MaxPayloadLimitField');
            testCase.verifyEqual(label.Text, ...
                'Max Payload Limit (wire octets)');
            testCase.verifyEqual(label.Tooltip, tooltip);
            testCase.verifyEqual(field.Tooltip, tooltip);
        end

        function testConstructionPreservesEnvironment(testCase)
            originalFolder = pwd;
            originalPath = path;
            app = create_hidden_app(testCase);
            cleanup = onCleanup(@() delete(app));
            testCase.verifyEqual(pwd, originalFolder);
            testCase.verifyEqual(path, originalPath);
            clear cleanup
        end

        function testConstructionCreatesNoFiles(testCase)
            created = construction_artifacts(testCase);
            testCase.verifyEmpty(created);
        end

        function testIssueNavigation(testCase, issueRoute)
            [mainTitle, childTitle] = select_issue(testCase.App.UIFigure, issueRoute);
            testCase.verifyEqual(mainTitle, issueRoute.main);
            testCase.verifyEqual(childTitle, issueRoute.child);
        end
    end
end

function value = find_one_by_tag(testCase, figure, tag)
values = findall(figure, 'Tag', tag);
testCase.assertNumElements(values, 1);
value = values(1);
end

function app = create_hidden_app(testCase)
try
    app = C2837xBlockConfigurator(struct( ...
        'visible', 'off', 'preview_provider', []));
catch cause
    testCase.assumeFail(sprintf('uifigure unavailable: %s', cause.message));
end
end

function group = main_tab_group(figure)
groups = findall(figure, 'Type', 'uitabgroup');
expected = sort({'Project', 'Instances', 'Inputs / Outputs', ...
    'Issues / Interface', 'Generation Preview'});
matches = arrayfun(@(value) isequal(sort(direct_tab_titles(value)), expected), groups);
group = groups(matches);
end

function titles = direct_tab_titles(group)
children = group.Children;
tabs = children(arrayfun(@(value) isa(value, 'matlab.ui.container.Tab'), children));
titles = {tabs.Title};
end

function titles = nested_tab_titles(figure, mainTitle)
mainTab = find_tab(figure, mainTitle);
groups = findall(mainTab, 'Type', 'uitabgroup');
titles = sort(direct_tab_titles(groups(1)));
end

function tab = find_tab(parent, title)
tabs = findall(parent, 'Type', 'uitab');
tab = tabs(strcmp({tabs.Title}, title));
end

function texts = button_texts(figure, context)
if strcmp(context, 'Project')
    buttons = findall(figure, 'Type', 'uibutton');
    wanted = {'Save', 'Load', 'Preview', 'Generate'};
    actual = {buttons.Text};
    texts = sort(actual(ismember(actual, wanted)));
else
    buttons = findall(find_tab(figure, context), 'Type', 'uibutton');
    wanted = {'Add', 'Copy', 'Delete', 'Remove', 'Move Up', 'Move Down'};
    actual = {buttons.Text};
    texts = sort(actual(ismember(actual, wanted)));
end
end

function layout = project_layout(figure)
main = main_tab_group(figure);
projectTab = find_tab(figure, 'Project');
main.SelectedTab = projectTab;
drawnow;
rootGrids = findall(projectTab, 'Type', 'uigridlayout');
root = rootGrids(arrayfun(@(value) value.Parent == projectTab, rootGrids));
panel = findall(projectTab, 'Type', 'uipanel', ...
    'Title', 'Project Common Configuration');
layout = struct('root', root, 'panel', panel, ...
    'secondRowChildren', root.Children(arrayfun( ...
    @(value) any(value.Layout.Row == 2), root.Children)));
end

function table = find_table(figure, columns)
tables = findall(figure, 'Type', 'uitable');
matches = arrayfun(@(value) isequal(string(value.ColumnName(:)), ...
    string(columns(:))), tables);
table = tables(matches);
end

function created = construction_artifacts(testCase)
folder = tempname;
mkdir(folder);
testCase.addTeardown(@() rmdir(folder, 's'));
originalFolder = pwd;
cleanupFolder = onCleanup(@() cd(originalFolder));
cd(folder);
before = {dir(folder).name};
app = create_hidden_app(testCase);
delete(app);
after = {dir(folder).name};
created = setdiff(after, before);
clear cleanupFolder
end

function [mainTitle, childTitle] = select_issue(figure, route)
issueTable = find_table(figure, ...
    {'Severity', 'Code', 'Instance', 'Field', 'File', 'Message'});
issueTable.Data = {'Error', route.code, 1, route.field, '', 'message'};
issueTable.CellSelectionCallback(issueTable, struct('Indices', [1 1]));
main = main_tab_group(figure);
mainTitle = main.SelectedTab.Title;
childTitle = '';
if ~isempty(route.child)
    nested = findall(main.SelectedTab, 'Type', 'uitabgroup');
    childTitle = nested(1).SelectedTab.Title;
end
end
