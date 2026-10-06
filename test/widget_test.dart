import 'package:codebase_map/app/app.dart';
import 'package:codebase_map/main.dart' as entrypoint;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('entrypoint starts the application', (tester) async {
    entrypoint.main();
    await tester.pumpAndSettle();

    expect(find.byType(CodebaseMapApp), findsOneWidget);
    expect(find.text('Codebase Map'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('start screen renders at desktop and small window sizes', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;

    for (final size in [const Size(1280, 800), const Size(320, 240)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const CodebaseMapApp());
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Understand your project.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
