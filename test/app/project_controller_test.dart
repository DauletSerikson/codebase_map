import 'dart:async';
import 'dart:io';

import 'package:codebase_map/app/project_controller.dart';
import 'package:codebase_map/core/analysis/analysis_snapshot.dart';
import 'package:codebase_map/core/file_system/project_scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

AnalysisSnapshot snapshot(String name, {bool invalid = false}) =>
    AnalysisSnapshot(
      project: invalid
          ? null
          : ProjectInfo(
              root: '/$name',
              packageName: name,
              kind: ProjectKind.dart,
              sourceScopes: [],
            ),
      files: {},
      dependencies: [],
      diagnostics: invalid
          ? [
              const Diagnostic(
                category: DiagnosticCategory.project,
                path: 'pubspec.yaml',
                message: 'Invalid pubspec',
              ),
            ]
          : [],
    );

void main() {
  test('cancel does not invoke analysis or invent a project', () async {
    var calls = 0;
    final controller = ProjectController(
      pickDirectory: () async => null,
      analyze: (_) async {
        calls++;
        return snapshot('wrong');
      },
    );
    addTearDown(controller.dispose);
    await controller.openProject();
    expect(controller.state.phase, OpenProjectPhase.idle);
    expect(controller.state.snapshot, isNull);
    expect(calls, 0);
  });

  test(
    'selection/loading/ready transitions and reopening cancellation',
    () async {
      String? choice = 'first';
      final phases = <OpenProjectPhase>[];
      final controller = ProjectController(
        pickDirectory: () async => choice,
        analyze: (root) async => snapshot(root),
      );
      addTearDown(controller.dispose);
      controller.addListener(() => phases.add(controller.state.phase));
      await controller.openProject();
      expect(phases, [
        OpenProjectPhase.selecting,
        OpenProjectPhase.analyzing,
        OpenProjectPhase.ready,
      ]);
      final previous = controller.state.snapshot;
      choice = null;
      await controller.openProject();
      expect(controller.state.snapshot, same(previous));
      expect(controller.state.phase, OpenProjectPhase.ready);
      choice = 'second';
      await controller.openProject();
      expect(controller.state.snapshot!.project!.packageName, 'second');
    },
  );

  test(
    'invalid project and unexpected failures retain prior snapshot and recover',
    () async {
      var choice = 'first';
      final controller = ProjectController(
        pickDirectory: () async => choice,
        analyze: (root) async {
          if (root == 'throw') throw FileSystemException('access denied');
          return snapshot(root, invalid: root == 'invalid');
        },
      );
      addTearDown(controller.dispose);
      await controller.openProject();
      final previous = controller.state.snapshot;
      choice = 'invalid';
      await controller.openProject();
      expect(controller.state.phase, OpenProjectPhase.failure);
      expect(controller.state.snapshot, same(previous));
      expect(controller.state.diagnostics.single.message, 'Invalid pubspec');
      expect(
        () => controller.state.diagnostics.clear(),
        throwsUnsupportedError,
      );
      choice = 'throw';
      await controller.openProject();
      expect(controller.state.error, contains('access denied'));
      expect(controller.state.snapshot, same(previous));
      choice = 'recovered';
      await controller.openProject();
      expect(controller.state.phase, OpenProjectPhase.ready);
      expect(controller.state.error, isNull);
    },
  );

  test('picker error is reported and native dialogs cannot overlap', () async {
    final pick = Completer<String?>();
    var calls = 0;
    final controller = ProjectController(
      pickDirectory: () {
        calls++;
        return pick.future;
      },
    );
    addTearDown(controller.dispose);
    final opening = controller.openProject();
    await controller.openProject();
    expect(calls, 1);
    pick.completeError(StateError('picker unavailable'));
    await opening;
    expect(controller.state.phase, OpenProjectPhase.failure);
    expect(controller.state.error, contains('picker unavailable'));
  });

  for (final oldFails in [false, true]) {
    test(
      'late ${oldFails ? 'failure' : 'success'} cannot replace newer project',
      () async {
        var choice = 'old';
        final old = Completer<AnalysisSnapshot>();
        final controller = ProjectController(
          pickDirectory: () async => choice,
          analyze: (root) =>
              root == 'old' ? old.future : Future.value(snapshot(root)),
        );
        addTearDown(controller.dispose);
        final first = controller.openProject();
        await Future<void>.delayed(Duration.zero);
        choice = 'new';
        await controller.openProject();
        if (oldFails) {
          old.completeError(StateError('old failure'));
        } else {
          old.complete(snapshot('old'));
        }
        await first;
        expect(controller.state.snapshot!.project!.packageName, 'new');
        expect(controller.state.phase, OpenProjectPhase.ready);
        expect(controller.state.error, isNull);
      },
    );
  }

  test('cancel of newer request supersedes pending old analysis', () async {
    String? choice = 'old';
    final old = Completer<AnalysisSnapshot>();
    final controller = ProjectController(
      pickDirectory: () async => choice,
      analyze: (_) => old.future,
    );
    addTearDown(controller.dispose);
    final first = controller.openProject();
    await Future<void>.delayed(Duration.zero);
    choice = null;
    await controller.openProject();
    old.complete(snapshot('old'));
    await first;
    expect(controller.state.phase, OpenProjectPhase.idle);
    expect(controller.state.snapshot, isNull);
  });

  test(
    'dispose during selection and analysis suppresses late notifications',
    () async {
      for (final selecting in [true, false]) {
        final pick = Completer<String?>();
        final analysis = Completer<AnalysisSnapshot>();
        var notifications = 0;
        final controller = ProjectController(
          pickDirectory: () => pick.future,
          analyze: (_) => analysis.future,
        );
        controller.addListener(() => notifications++);
        final opening = controller.openProject();
        if (!selecting) {
          pick.complete('sample');
          await Future<void>.delayed(Duration.zero);
        }
        controller.dispose();
        final before = notifications;
        if (selecting) {
          pick.complete('sample');
        } else {
          analysis.complete(snapshot('sample'));
        }
        await opening;
        await controller.openProject();
        expect(notifications, before);
      }
    },
  );

  test(
    'background worker runs real pipeline for Unicode paths and failures',
    () async {
      final root = await Directory.systemTemp.createTemp('open Ж space ');
      addTearDown(() => root.delete(recursive: true));
      await File(p.join(root.path, 'pubspec.yaml'))
          .writeAsString('name: sample\n');
      await Directory(p.join(root.path, 'lib')).create();
      await File(p.join(root.path, 'lib/a.dart'))
          .writeAsString("import 'missing.dart';");
      final result = await analyzeProjectInBackground(root.path);
      expect(result.project!.packageName, 'sample');
      expect(result.files.keys, ['lib/a.dart']);
      expect(result.diagnostics.single.category, DiagnosticCategory.resolution);
      await File(p.join(root.path, 'pubspec.yaml')).delete();
      expect((await analyzeProjectInBackground(root.path)).project, isNull);
      expect(
        (await analyzeProjectInBackground(p.join(root.path, 'absent'))).project,
        isNull,
      );
    },
  );
}
