import 'package:codebase_map/app/project_controller.dart';
import 'package:codebase_map/core/analysis/analysis_snapshot.dart';
import 'package:codebase_map/core/file_system/project_scan.dart';
import 'package:flutter_test/flutter_test.dart';

AnalysisSnapshot project(String name) => AnalysisSnapshot(
  project: ProjectInfo(
    root: '/$name',
    packageName: name,
    kind: ProjectKind.dart,
    sourceScopes: [SourceScope.lib],
  ),
  files: {
    'lib/a.dart': AnalyzedSource(
      file: const SourceFile(
        relativePath: 'lib/a.dart',
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

void main() {
  test(
    'selection validates IDs, clears explicitly, and resets for a new snapshot',
    () async {
      final controller = ProjectController(
        pickDirectory: () async => 'sample',
        analyze: (_) async => project('sample'),
      );
      addTearDown(controller.dispose);
      controller.selectFile('lib/a.dart');
      expect(controller.state.selectedFileId, isNull);
      await controller.openProject();
      controller.selectFile('lib/a.dart');
      expect(controller.state.selectedFileId, 'lib/a.dart');
      controller.selectFile('missing');
      expect(controller.state.selectedFileId, 'lib/a.dart');
      controller.selectFile(null);
      expect(controller.state.selectedFileId, isNull);
      controller.selectFile('lib/a.dart');
      await controller.openProject();
      expect(controller.state.selectedFileId, isNull);
    },
  );

  test(
    'selection survives cancelled or failed reopening with previous snapshot',
    () async {
      String? choice = 'sample';
      var fail = false;
      final controller = ProjectController(
        pickDirectory: () async => choice,
        analyze: (_) async {
          if (fail) throw StateError('failure');
          return project('sample');
        },
      );
      addTearDown(controller.dispose);
      await controller.openProject();
      controller.selectFile('lib/a.dart');
      choice = null;
      await controller.openProject();
      expect(controller.state.selectedFileId, 'lib/a.dart');
      choice = 'bad';
      fail = true;
      await controller.openProject();
      expect(controller.state.selectedFileId, 'lib/a.dart');
      expect(controller.state.phase, OpenProjectPhase.failure);
    },
  );
}
