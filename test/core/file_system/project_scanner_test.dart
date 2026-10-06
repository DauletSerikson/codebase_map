import 'dart:io';

import 'package:codebase_map/core/file_system/project_scan.dart';
import 'package:codebase_map/core/file_system/project_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class FailingFileSystem extends ProjectFileSystem {
  const FailingFileSystem(this.operation, this.basename);
  final String operation;
  final String basename;

  void fail(String path, String expected) {
    if (operation == expected && p.basename(path) == basename) {
      throw FileSystemException('Injected access failure', path);
    }
  }

  @override
  Future<String> read(String path) async {
    fail(path, 'read');
    return super.read(path);
  }

  @override
  Future<FileSystemEntityType> type(String path) async {
    fail(path, 'type');
    return super.type(path);
  }

  @override
  Stream<FileSystemEntity> list(String path) async* {
    // Emit an entry before failure to verify partial results are retained.
    await for (final entry in super.list(path)) {
      yield entry;
    }
    fail(path, 'list');
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
    root = await Directory.systemTemp.createTemp('scanner Unicode Ж space ');
    await write('pubspec.yaml', 'name: sample_project\n');
  });
  tearDown(() => root.delete(recursive: true));

  test('recognizes Dart with missing and empty lib', () async {
    var result = await const ProjectScanner().scan(root.path);
    expect(result.project!.kind, ProjectKind.dart);
    expect(result.project!.packageName, 'sample_project');
    expect(result.project!.sourceScopes, isEmpty);
    expect(result.files, isEmpty);
    expect(result.diagnostics, isEmpty);
    await Directory(p.join(root.path, 'lib')).create();
    result = await const ProjectScanner().scan(root.path);
    expect(result.project!.sourceScopes, [SourceScope.lib]);
    expect(result.files, isEmpty);
  });

  test('recognizes Flutter SDK dependency', () async {
    await write(
      'pubspec.yaml',
      'name: sample\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    expect(
      (await const ProjectScanner().scan(root.path)).project!.kind,
      ProjectKind.flutter,
    );
    await write(
      'pubspec.yaml',
      'name: sample\ndependencies:\n  flutter: any\n',
    );
    expect(
      (await const ProjectScanner().scan(root.path)).project!.kind,
      ProjectKind.dart,
    );
  });

  test(
    'rejects missing, malformed and invalid pubspec without throwing',
    () async {
      await File(p.join(root.path, 'pubspec.yaml')).delete();
      expect((await const ProjectScanner().scan(root.path)).project, isNull);
      for (final source in [
        'name: [',
        '',
        '[]',
        'name: 12',
        'name: bad-name',
      ]) {
        await write('pubspec.yaml', source);
        final result = await const ProjectScanner().scan(root.path);
        expect(result.project, isNull);
        expect(result.diagnostics, hasLength(1));
        expect(result.diagnostics.single.category, DiagnosticCategory.project);
      }
    },
  );

  test('invalid and file roots return diagnostics', () async {
    for (final path in [
      p.join(root.path, 'missing'),
      p.join(root.path, 'pubspec.yaml'),
    ]) {
      final result = await const ProjectScanner().scan(path);
      expect(result.project, isNull);
      expect(result.diagnostics, isNotEmpty);
    }
  });

  test(
    'scans both scopes, generated files and Unicode with stable sorted IDs',
    () async {
      for (final path in [
        'test/z.dart',
        'lib/Ж folder/a.dart',
        'lib/z.freezed.dart',
        'lib/a.g.dart',
        'lib/regular.dart',
        'bin/ignored.dart',
        'lib/no.txt',
      ]) {
        await write(path, '// $path');
      }
      final result = await const ProjectScanner().scan(
        p.join(root.path, '.', 'lib', '..'),
      );
      expect(result.project!.sourceScopes, SourceScope.values);
      expect(result.files.map((f) => f.id), [
        'lib/a.g.dart',
        'lib/regular.dart',
        'lib/z.freezed.dart',
        'lib/Ж folder/a.dart',
        'test/z.dart',
      ]);
      expect(result.files.where((f) => f.isGenerated), hasLength(2));
      expect(result.files.last.scope, SourceScope.test);
      expect(
        result.files.every(
          (f) => f.content != null && f.readState == SourceReadState.readable,
        ),
        isTrue,
      );
      expect(() => result.files.clear(), throwsUnsupportedError);
      expect(
        () => result.project!.sourceScopes.clear(),
        throwsUnsupportedError,
      );
      expect(() => result.diagnostics.clear(), throwsUnsupportedError);
      final again = await const ProjectScanner().scan(root.path);
      expect(again.files.map((f) => f.id), result.files.map((f) => f.id));
    },
  );

  test(
    'read failure retains unreadable source and readable siblings',
    () async {
      await write('lib/bad.dart', '');
      await write('lib/good.dart', 'void main() {}');
      final result = await const ProjectScanner(
        fileSystem: FailingFileSystem('read', 'bad.dart'),
      ).scan(root.path);
      expect(result.files.first.readState, SourceReadState.unreadable);
      expect(result.files.first.content, isNull);
      expect(result.files.last.readState, SourceReadState.readable);
      expect(result.diagnostics.single.path, 'lib/bad.dart');
    },
  );

  test('invalid UTF-8 is diagnosed for sources and pubspec', () async {
    await write('lib/bad.dart', '');
    await File(p.join(root.path, 'lib/bad.dart')).writeAsBytes([0xff]);
    var result = await const ProjectScanner().scan(root.path);
    expect(result.files.single.readState, SourceReadState.unreadable);
    await File(p.join(root.path, 'pubspec.yaml')).writeAsBytes([0xff]);
    result = await const ProjectScanner().scan(root.path);
    expect(result.project, isNull);
    expect(result.diagnostics.single.path, 'pubspec.yaml');
  });

  test(
    'pubspec read, entry inspection and partial listing errors are contained',
    () async {
      await write('lib/a.dart', '');
      await write('test/b.dart', '');
      for (final failure in [
        const FailingFileSystem('read', 'pubspec.yaml'),
        const FailingFileSystem('type', 'a.dart'),
        const FailingFileSystem('type', 'lib'),
        const FailingFileSystem('list', 'lib'),
      ]) {
        final result = await ProjectScanner(fileSystem: failure)
            .scan(root.path);
        expect(result.diagnostics, hasLength(1));
        if (failure.operation != 'read') {
          expect(result.files.map((f) => f.id), contains('test/b.dart'));
        } else {
          expect(result.project, isNull);
        }
        if (failure.operation == 'list') {
          expect(result.files.map((f) => f.id), contains('lib/a.dart'));
        }
      }
    },
  );

  test(
    'nested directory, file, broken and recursive symlinks are ignored',
    () async {
      await write('lib/a.dart', '');
      await Link(p.join(root.path, 'lib/loop')).create(root.path);
      await Link(p.join(root.path, 'lib/alias.dart'))
          .create(p.join(root.path, 'lib/a.dart'));
      await Link(p.join(root.path, 'lib/broken.dart'))
          .create(p.join(root.path, 'absent'));
      final alias = Link(
        p.join(root.parent.path, '${p.basename(root.path)} alias'),
      );
      await alias.create(root.path);
      addTearDown(alias.delete);
      final result = await const ProjectScanner().scan(alias.path);
      expect(result.files.map((f) => f.id), ['lib/a.dart']);
      expect(result.project!.root, await root.resolveSymbolicLinks());
      expect(result.diagnostics, isEmpty);
    },
    skip: Platform.isWindows
        ? 'Creating symlinks requires Windows privileges.'
        : false,
  );

  test(
    'non-directory scopes are diagnosed and results remain deterministic',
    () async {
      await write('test', '');
      await write('lib', '');
      final result = await const ProjectScanner().scan(root.path);
      expect(result.project, isNotNull);
      expect(result.diagnostics.map((d) => d.path), ['lib', 'test']);
    },
  );
}
