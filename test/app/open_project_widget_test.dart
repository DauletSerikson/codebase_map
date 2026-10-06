import 'dart:async';

import 'package:codebase_map/app/app.dart';
import 'package:codebase_map/app/project_controller.dart';
import 'package:codebase_map/core/analysis/analysis_snapshot.dart';
import 'package:codebase_map/core/file_system/project_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AnalysisSnapshot result({bool invalid = false}) => AnalysisSnapshot(
  project: invalid
      ? null
      : ProjectInfo(
          root: '/Ж folder/sample',
          packageName: 'sample',
          kind: ProjectKind.flutter,
          sourceScopes: [],
        ),
  files: {},
  dependencies: [],
  diagnostics: [
    const Diagnostic(
      category: DiagnosticCategory.fileSystem,
      path: 'lib/bad.dart',
      message: 'Read denied',
    ),
  ],
);

void main() {
  testWidgets('button drives picker, loading, workspace and diagnostics', (
    tester,
  ) async {
    final picker = Completer<String?>();
    final analysis = Completer<AnalysisSnapshot>();
    final controller = ProjectController(
      pickDirectory: () => picker.future,
      analyze: (_) => analysis.future,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(CodebaseMapApp(controller: controller));
    await tester.tap(find.text('Open Project'));
    await tester.pump();
    expect(find.text('Choose a project folder…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    picker.complete('/sample');
    await tester.pump();
    expect(find.text('Analyzing project…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    analysis.complete(result());
    await tester.pumpAndSettle();
    expect(find.text('sample'), findsOneWidget);
    expect(find.text('/Ж folder/sample'), findsOneWidget);
    expect(
      find.text('No Dart source files found in lib/ or test/.'),
      findsOneWidget,
    );
    expect(find.text('1 diagnostics'), findsOneWidget);
    await tester.ensureVisible(find.text('1 diagnostics'));
    await tester.tap(find.text('1 diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Read denied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel, invalid project and picker errors leave opening available',
    (tester) async {
      String? choice;
      var throws = false;
      final controller = ProjectController(
        pickDirectory: () async {
          if (throws) throw StateError('picker failed');
          return choice;
        },
        analyze: (_) async => result(invalid: true),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(CodebaseMapApp(controller: controller));
      await tester.tap(find.text('Open Project'));
      await tester.pumpAndSettle();
      expect(find.text('Understand your project.'), findsOneWidget);
      choice = '/invalid';
      await tester.tap(find.text('Open Project'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open this Dart/Flutter project.'),
        findsOneWidget,
      );
      throws = true;
      await tester.tap(find.text('Open Project'));
      await tester.pumpAndSettle();
      expect(find.textContaining('picker failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workspace remains usable at desktop and small sizes during reopen/failure',
    (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());
      tester.view.devicePixelRatio = 1;
      var fail = false;
      final controller = ProjectController(
        pickDirectory: () async => '/sample',
        analyze: (_) async => result(invalid: fail),
      );
      addTearDown(controller.dispose);
      for (final size in [const Size(1280, 800), const Size(320, 240)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(CodebaseMapApp(controller: controller));
        await controller.openProject();
        await tester.pumpAndSettle();
        expect(find.text('sample'), findsOneWidget);
        expect(tester.takeException(), isNull);
        fail = true;
      }
      expect(
        find.text('Could not open this Dart/Flutter project.'),
        findsOneWidget,
      );
      expect(find.text('sample'), findsOneWidget);
    },
  );
}
