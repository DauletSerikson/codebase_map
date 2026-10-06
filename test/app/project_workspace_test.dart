import 'package:codebase_map/app/app.dart';
import 'package:codebase_map/app/project_controller.dart';
import 'package:codebase_map/core/analysis/analysis_snapshot.dart';
import 'package:codebase_map/core/analysis/directive.dart';
import 'package:codebase_map/core/analysis/source_location.dart';
import 'package:codebase_map/core/dependency_graph/dependency.dart';
import 'package:codebase_map/core/file_system/project_scan.dart';
import 'package:codebase_map/ui/file_inspector.dart';
import 'package:codebase_map/ui/project_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const location = SourceLocation(offset: 0, length: 1, line: 1, column: 1);
AnalysisSnapshot fixture({bool empty = false}) {
  AnalyzedSource file(String id, {bool unreadable = false}) => AnalyzedSource(
    file: SourceFile(
      relativePath: id,
      scope: id.startsWith('test/') ? SourceScope.test : SourceScope.lib,
      isGenerated: id.endsWith('.g.dart'),
      readState: unreadable
          ? SourceReadState.unreadable
          : SourceReadState.readable,
      content: unreadable ? null : '',
    ),
    lineCount: unreadable ? null : 12,
    directives: id == 'lib/a.dart'
        ? [
            for (var i = 0; i < 3; i++)
              Directive(
                type: DirectiveType.import,
                uri: 'b.dart',
                location: location,
              ),
          ]
        : [],
  );
  final files = [
    file('lib/a.dart'),
    file('lib/deep/Ж folder/b.g.dart', unreadable: true),
    file('test/a_test.dart'),
  ];
  return AnalysisSnapshot(
    project: ProjectInfo(
      root: '/sample',
      packageName: 'sample',
      kind: ProjectKind.dart,
      sourceScopes: [SourceScope.lib, SourceScope.test],
    ),
    files: empty ? {} : {for (final f in files) f.id: f},
    dependencies: empty
        ? []
        : [
            const Dependency(
              sourceId: 'lib/a.dart',
              targetId: 'lib/deep/Ж folder/b.g.dart',
              type: DependencyType.import,
              uri: 'deep/Ж folder/b.g.dart',
              location: location,
              status: ResolutionStatus.resolved,
            ),
            const Dependency(
              sourceId: 'lib/a.dart',
              type: DependencyType.import,
              uri: 'package:external/a.dart',
              location: location,
              status: ResolutionStatus.externalPackage,
            ),
            const Dependency(
              sourceId: 'lib/a.dart',
              type: DependencyType.import,
              uri: 'missing.dart',
              location: location,
              status: ResolutionStatus.unresolved,
            ),
          ],
    diagnostics: empty
        ? []
        : [
            const Diagnostic(
              category: DiagnosticCategory.fileSystem,
              path: 'lib/deep/Ж folder/b.g.dart',
              message: 'Read denied',
              location: location,
            ),
          ],
  );
}

void main() {
  Future<ProjectController> mount(
    WidgetTester tester, {
    bool empty = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    final controller = ProjectController(
      pickDirectory: () async => '/sample',
      analyze: (_) async => fixture(empty: empty),
    );
    addTearDown(controller.dispose);
    await controller.openProject();
    await tester.pumpWidget(CodebaseMapApp(controller: controller));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
    'tree selection populates Inspector and local links select and reveal target',
    (tester) async {
      final controller = await mount(tester);
      expect(find.text('Select a file to inspect.'), findsOneWidget);
      expect(find.text('PROJECT'), findsOneWidget);
      expect(find.text('INSPECTOR'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tree:lib/a.dart')));
      await tester.pumpAndSettle();
      expect(controller.state.selectedFileId, 'lib/a.dart');
      expect(find.text('Imports: 3'), findsOneWidget);
      expect(find.text('Lines: 12'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('tree:lib/a.dart')))
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('tree:lib/deep')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tree:lib/deep/Ж folder/b.g.dart')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('dependency:0')));
      await tester.pumpAndSettle();
      expect(controller.state.selectedFileId, 'lib/deep/Ж folder/b.g.dart');
      expect(find.text('Generated file'), findsOneWidget);
      expect(find.text('Source could not be read.'), findsOneWidget);
      expect(find.text('Lines: unavailable'), findsOneWidget);
      expect(find.text('Imported by: 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tree:lib/deep/Ж folder/b.g.dart')),
        findsOneWidget,
      );
      final incoming = find.byKey(const ValueKey('usedBy:0'));
      await tester.ensureVisible(incoming);
      await tester.tap(incoming);
      await tester.pumpAndSettle();
      expect(controller.state.selectedFileId, 'lib/a.dart');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'external and unresolved dependencies are labelled and cannot navigate',
    (tester) async {
      final controller = await mount(tester);
      controller.selectFile('lib/a.dart');
      await tester.pumpAndSettle();
      for (final index in [1, 2]) {
        final tile = find.byKey(ValueKey('dependency:$index'));
        await tester.ensureVisible(tile);
        expect(tester.widget<ListTile>(tile).onTap, isNull);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(controller.state.selectedFileId, 'lib/a.dart');
      }
      expect(find.text('import · unresolved'), findsOneWidget);
      expect(find.text('import · external package'), findsOneWidget);
    },
  );

  testWidgets(
    'Inspector shows file diagnostics and scope folders in empty project',
    (tester) async {
      final controller = await mount(tester);
      controller.selectFile('lib/deep/Ж folder/b.g.dart');
      await tester.pumpAndSettle();
      final diagnostic = find.descendant(
        of: find.byType(FileInspectorPanel),
        matching: find.text('Read denied'),
      );
      await tester.ensureVisible(diagnostic);
      expect(diagnostic, findsOneWidget);
      expect(find.text('Line 1, column 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      final empty = ProjectController(
        pickDirectory: () async => '/empty',
        analyze: (_) async => fixture(empty: true),
      );
      addTearDown(empty.dispose);
      await empty.openProject();
      await tester.pumpWidget(CodebaseMapApp(controller: empty));
      await tester.pumpAndSettle();
      expect(find.text('lib/'), findsOneWidget);
      expect(find.text('test/'), findsOneWidget);
      expect(
        find.text('No Dart source files found in lib/ or test/.'),
        findsOneWidget,
      );
      expect(find.text('Select a file to inspect.'), findsOneWidget);
    },
  );

  testWidgets(
    'narrow workspace supports Inspector selection without overflow',
    (tester) async {
      final controller = await mount(tester);
      tester.view.physicalSize = const Size(320, 240);
      controller.selectFile('lib/a.dart');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final inspectorPath = find.byKey(const ValueKey('inspector:path'));
      await tester.ensureVisible(inspectorPath);
      await tester.pumpAndSettle();
      expect(find.text('Imports: 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('tree reveals distant selection and tolerates deep Unicode paths', (
    tester,
  ) async {
    final target =
        'lib/z/${List.generate(12, (i) => 'Ж long folder $i').join('/')}/screen.dart';
    final ids = [
      for (var i = 0; i < 40; i++)
        'lib/file${i.toString().padLeft(2, '0')}.dart',
      target,
    ];
    final base = fixture();
    final snapshot = AnalysisSnapshot(
      project: base.project,
      files: {
        for (final id in ids)
          id: AnalyzedSource(
            file: SourceFile(
              relativePath: id,
              scope: SourceScope.lib,
              isGenerated: false,
              readState: SourceReadState.readable,
              content: '',
            ),
            lineCount: 0,
            directives: [],
          ),
      },
      dependencies: [],
      diagnostics: [],
    );
    Widget tree(String? selected) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 260,
          height: 300,
          child: ProjectTree(
            snapshot: snapshot,
            selectedFileId: selected,
            onSelectFile: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(tree(null));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('tree:$target')), findsNothing);
    await tester.pumpWidget(tree(target));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('tree:$target')).hitTestable(), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.byKey(ValueKey('tree:$target'))).selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
