import 'dart:io';

import 'package:codebase_map/core/analysis/project_analyzer.dart';
import 'package:codebase_map/core/dependency_graph/dependency.dart';
import 'package:codebase_map/core/file_system/project_scan.dart';
import 'package:codebase_map/core/file_system/project_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class FailedIO extends ProjectFileSystem {
  const FailedIO();
  @override
  Future<String> read(String path) async {
    if (p.basename(path) == 'unreadable.dart') {
      throw FileSystemException('Injected read failure', path);
    }
    return super.read(path);
  }

  @override
  Future<FileSystemEntityType> targetType(String path) async {
    if (p.basename(path) == 'denied.dart') {
      throw FileSystemException('Injected probe failure', path);
    }
    return super.targetType(path);
  }
}

void main() {
  late Directory root;
  Future<void> write(String relative, String content) async {
    final file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('analysis Ж space ');
    await write('pubspec.yaml', 'name: sample\n');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'relative, current package, scopes, URI encoding and direct exports',
    () async {
      await write(
        'lib/nested/a.dart',
        "import '../b.dart';\nimport 'package:sample/b.dart';\nexport '../b.dart';\nimport '../Ж%20file.dart';",
      );
      await write('lib/b.dart', "export 'c.dart';");
      await write('lib/c.dart', '');
      await write('lib/Ж file.dart', '');
      await write('test/a_test.dart', "import '../lib/nested/a.dart';");
      final snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(
        snapshot.dependencies.every(
          (d) => d.status == ResolutionStatus.resolved,
        ),
        isTrue,
      );
      expect(snapshot.graph.nodeIds, hasLength(5));
      expect(snapshot.graph.outgoing['lib/nested/a.dart'], hasLength(3));
      expect(
        snapshot.graph.outgoing['lib/nested/a.dart']!.any(
          (e) => e.targetId == 'lib/c.dart',
        ),
        isFalse,
      );
      expect(snapshot.diagnostics, isEmpty);
      expect(snapshot.files['lib/nested/a.dart']!.lineCount, 4);
    },
  );

  test('SDK and external packages never become graph nodes', () async {
    await write(
      'lib/a.dart',
      "import 'dart:io';\nimport 'package:flutter/material.dart';\nexport 'package:other/other.dart';",
    );
    final snapshot = await const ProjectAnalyzer().analyze(root.path);
    expect(snapshot.dependencies.map((d) => d.status), [
      ResolutionStatus.sdk,
      ResolutionStatus.externalPackage,
      ResolutionStatus.externalPackage,
    ]);
    expect(snapshot.graph.nodeIds, ['lib/a.dart']);
    expect(snapshot.graph.edges, isEmpty);
    expect(snapshot.diagnostics, isEmpty);
  });

  test(
    'missing, existing outside scopes and directory targets differ',
    () async {
      await write(
        'lib/a.dart',
        "import 'missing.dart';\nimport '../bin/a.dart';\nimport 'folder';",
      );
      await write('bin/a.dart', '');
      await Directory(p.join(root.path, 'lib/folder')).create();
      final snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(snapshot.dependencies.map((d) => d.status), [
        ResolutionStatus.unresolved,
        ResolutionStatus.outOfScope,
        ResolutionStatus.unresolved,
      ]);
      expect(snapshot.dependencies.every((d) => d.targetId == null), isTrue);
      expect(snapshot.diagnostics, hasLength(2));
      expect(snapshot.diagnostics.first.location!.line, 1);
    },
  );

  test(
    'conditional variants retained including duplicates and missing targets',
    () async {
      await write(
        'lib/a.dart',
        "import 'b.dart' if (dart.library.io) 'c.dart' if (dart.library.html) 'missing.dart';\nexport 'b.dart' if (flag == 'yes') 'c.dart';",
      );
      await write('lib/b.dart', '');
      await write('lib/c.dart', '');
      final snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(snapshot.dependencies.map((d) => d.uri), [
        'b.dart',
        'c.dart',
        'missing.dart',
        'b.dart',
        'c.dart',
      ]);
      expect(snapshot.dependencies[1].branch!.variable, 'dart.library.io');
      expect(snapshot.dependencies.last.branch!.value, 'yes');
      expect(snapshot.graph.edges, hasLength(4));
      expect(snapshot.dependencies[2].status, ResolutionStatus.unresolved);
    },
  );

  test('duplicates, cycles, self-loop, isolated nodes and graph indexes', () async {
    await write(
      'lib/a.dart',
      "import 'b.dart';\nimport 'b.dart';\nexport 'b.dart';\nimport 'a.dart';",
    );
    await write('lib/b.dart', "import 'a.dart';");
    await write('lib/isolated.dart', '');
    final snapshot = await const ProjectAnalyzer().analyze(root.path);
    expect(snapshot.dependencies, hasLength(5));
    expect(snapshot.graph.edges, hasLength(4));
    expect(snapshot.graph.incoming['lib/isolated.dart'], isEmpty);
    expect(snapshot.graph.outgoing['lib/isolated.dart'], isEmpty);
    for (final edge in snapshot.graph.edges) {
      expect(snapshot.graph.incoming[edge.targetId], contains(same(edge)));
      expect(snapshot.graph.outgoing[edge.sourceId], contains(same(edge)));
    }
    expect(snapshot.graph.incoming.values.expand((e) => e), hasLength(4));
    expect(snapshot.graph.outgoing.values.expand((e) => e), hasLength(4));
    expect(() => snapshot.files.clear(), throwsUnsupportedError);
    expect(() => snapshot.dependencies.clear(), throwsUnsupportedError);
    expect(() => snapshot.diagnostics.clear(), throwsUnsupportedError);
    expect(() => snapshot.graph.nodeIds.clear(), throwsUnsupportedError);
    expect(() => snapshot.graph.edges.clear(), throwsUnsupportedError);
    expect(() => snapshot.graph.incoming.clear(), throwsUnsupportedError);
    expect(
      () => snapshot.graph.outgoing['lib/a.dart']!.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.files['lib/a.dart']!.directives.clear(),
      throwsUnsupportedError,
    );
    final again = await const ProjectAnalyzer().analyze(root.path);
    expect(
      again.graph.edges.map((e) => '${e.sourceId}:${e.targetId}:${e.type}'),
      snapshot.graph.edges.map((e) => '${e.sourceId}:${e.targetId}:${e.type}'),
    );
  });

  test(
    'generated part and URI part of give only library-to-part edge',
    () async {
      await write('lib/a.dart', "part 'a.g.dart';");
      await write('lib/a.g.dart', "part of 'a.dart';");
      final snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(snapshot.dependencies, hasLength(1));
      expect(snapshot.dependencies.single.type, DependencyType.part);
      expect(snapshot.graph.outgoing['lib/a.g.dart'], isEmpty);
      expect(snapshot.files['lib/a.g.dart']!.file.isGenerated, isTrue);
      expect(snapshot.diagnostics, isEmpty);
    },
  );

  test(
    'named part of validates library name without resolving it as URI',
    () async {
      await write('lib/a.dart', "library sample.library;\npart 'p.dart';");
      await write('lib/p.dart', 'part of sample.library;');
      var snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(snapshot.files['lib/a.dart']!.libraryName, 'sample.library');
      expect(snapshot.diagnostics, isEmpty);
      await write('lib/p.dart', 'part of wrong.library;');
      snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(snapshot.diagnostics.single.code, 'part_of_mismatch');
    },
  );

  test(
    'missing part of, orphan, mismatch and multiple ownership diagnosed',
    () async {
      await write('lib/a.dart', "part 'p.dart';");
      await write('lib/p.dart', '');
      var snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(snapshot.diagnostics.single.code, 'missing_part_of');
      await write('lib/p.dart', "part of 'b.dart';");
      await write('lib/b.dart', '');
      snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(
        snapshot.diagnostics.map((d) => d.code),
        contains('part_of_mismatch'),
      );
      await write('lib/a.dart', '');
      snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(snapshot.diagnostics.map((d) => d.code), contains('orphan_part'));
      await write('lib/a.dart', "part 'p.dart';");
      await write('lib/b.dart', "part 'p.dart';");
      snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(
        snapshot.diagnostics.map((d) => d.code),
        contains('multiple_part_owners'),
      );
    },
  );

  test(
    'unreadable source and probe failures retain useful partial snapshot',
    () async {
      await write(
        'lib/a.dart',
        "import 'unreadable.dart';\nimport '../bin/denied.dart';",
      );
      await write('lib/unreadable.dart', '');
      final snapshot = await const ProjectAnalyzer(fileSystem: FailedIO())
          .analyze(root.path);
      expect(snapshot.dependencies.first.status, ResolutionStatus.resolved);
      expect(
        snapshot.dependencies.last.status,
        ResolutionStatus.fileSystemError,
      );
      expect(snapshot.files['lib/unreadable.dart']!.lineCount, isNull);
      expect(
        snapshot.files['lib/unreadable.dart']!.file.readState,
        SourceReadState.unreadable,
      );
      expect(
        snapshot.diagnostics.map((d) => d.category),
        containsAll([
          DiagnosticCategory.fileSystem,
          DiagnosticCategory.resolution,
        ]),
      );
    },
  );

  test('malformed source and invalid URI do not break other sources', () async {
    await write(
      'lib/a.dart',
      "import 'http://example.com/a.dart';\nimport 'a.dart?x';\nvoid main( {",
    );
    await write('lib/b.dart', "import 'a.dart';");
    final snapshot = await const ProjectAnalyzer().analyze(root.path);
    expect(snapshot.dependencies.map((d) => d.status), [
      ResolutionStatus.invalidUri,
      ResolutionStatus.invalidUri,
      ResolutionStatus.resolved,
    ]);
    expect(
      snapshot.diagnostics.map((d) => d.category),
      contains(DiagnosticCategory.syntax),
    );
  });

  test(
    'non-project and empty project yield valid immutable snapshots',
    () async {
      var snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(snapshot.project, isNotNull);
      expect(snapshot.graph.nodeIds, isEmpty);
      await File(p.join(root.path, 'pubspec.yaml')).delete();
      snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(snapshot.project, isNull);
      expect(snapshot.files, isEmpty);
      expect(snapshot.diagnostics, isNotEmpty);
    },
  );

  test(
    'symlink targets remain out of scope, without traversing linked directories',
    () async {
      await write('lib/a.dart', "import 'alias.dart';\nimport 'link/p.dart';");
      await write('outside/p.dart', '');
      await Link(p.join(root.path, 'lib/alias.dart'))
          .create(p.join(root.path, 'outside/p.dart'));
      await Link(p.join(root.path, 'lib/link'))
          .create(p.join(root.path, 'outside'));
      final snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(
        snapshot.dependencies.every(
          (d) => d.status == ResolutionStatus.outOfScope,
        ),
        isTrue,
      );
      expect(snapshot.graph.nodeIds, ['lib/a.dart']);
    },
    skip: Platform.isWindows ? 'Symlink creation requires privileges.' : false,
  );
  test('dot segments normalize and existing targets outside root stay out of scope', () async {
    final sibling = File(
      p.join(root.parent.path, '${p.basename(root.path)} sibling.dart'),
    );
    await sibling.writeAsString('');
    addTearDown(sibling.delete);
    await write(
      'lib/a.dart',
      "import 'folder/../b.dart';\nimport '../../${p.basename(sibling.path)}';",
    );
    await write('lib/b.dart', '');
    final snapshot = await const ProjectAnalyzer().analyze(root.path);
    expect(snapshot.dependencies.first.targetId, 'lib/b.dart');
    expect(snapshot.dependencies.last.status, ResolutionStatus.outOfScope);
    expect(snapshot.dependencies.last.targetId, isNull);
  });

  test(
    'case-insensitive filesystem spelling maps back to scanned IDs',
    () async {
      await write('lib/Target.dart', '');
      await write('lib/a.dart', "import 'target.dart';");
      final caseInsensitive = await File(p.join(root.path, 'lib/target.dart'))
          .exists();
      final snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(
        snapshot.dependencies.single.status,
        caseInsensitive
            ? ResolutionStatus.resolved
            : ResolutionStatus.unresolved,
      );
      if (caseInsensitive) {
        expect(snapshot.dependencies.single.targetId, 'lib/Target.dart');
      }
    },
  );

  test(
    'missing part owner and invalid encoded URI return diagnostics',
    () async {
      await write('lib/p.dart', "part of 'missing.dart';");
      await write(
        'lib/a.dart',
        "import 'dart:';\nimport 'bad%00.dart';\nimport 'bad%5Cname.dart';",
      );
      final snapshot = await const ProjectAnalyzer().analyze(root.path);
      expect(
        snapshot.dependencies.every(
          (d) => d.status == ResolutionStatus.invalidUri,
        ),
        isTrue,
      );
      expect(
        snapshot.diagnostics.map((d) => d.code),
        contains('part_of_unresolved'),
      );
    },
  );
}
