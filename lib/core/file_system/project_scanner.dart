import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'project_scan.dart';

/// Small IO boundary, also allowing deterministic filesystem failure tests.
class ProjectFileSystem {
  const ProjectFileSystem();

  Future<String> resolveRoot(String root) =>
      Directory(root).resolveSymbolicLinks();
  Future<FileSystemEntityType> type(String path) =>
      FileSystemEntity.type(path, followLinks: false);
  Stream<FileSystemEntity> list(String path) =>
      Directory(path).list(followLinks: false);
  Future<String> resolveFile(String path) => File(path).resolveSymbolicLinks();

  Future<String> read(String path) => File(path).readAsString();

  /// Inspect a target without following any symlink along its path.
  Future<FileSystemEntityType> targetType(String path) async {
    final segments = p.split(p.normalize(p.absolute(path)));
    var current = segments.first;
    for (var index = 1; index < segments.length; index++) {
      current = p.join(current, segments[index]);
      final entryType = await type(current);
      if (entryType == FileSystemEntityType.link ||
          entryType == FileSystemEntityType.notFound) {
        return entryType;
      }
      if (index == segments.length - 1) return entryType;
      if (entryType != FileSystemEntityType.directory) {
        return FileSystemEntityType.notFound;
      }
    }
    return type(current);
  }
}

class ProjectScanner {
  const ProjectScanner({this.fileSystem = const ProjectFileSystem()});

  final ProjectFileSystem fileSystem;

  Future<ProjectScanResult> scan(String root) async {
    final diagnostics = <Diagnostic>[];
    final files = <SourceFile>[];
    ProjectInfo? project;
    void report(String? path, String message, [bool filesystem = true]) {
      diagnostics.add(
        Diagnostic(
          category: filesystem
              ? DiagnosticCategory.fileSystem
              : DiagnosticCategory.project,
          path: path,
          message: message,
        ),
      );
    }

    ProjectScanResult result() {
      files.sort((a, b) => a.id.compareTo(b.id));
      diagnostics.sort((a, b) {
        final pathOrder = (a.path ?? '').compareTo(b.path ?? '');
        return pathOrder != 0 ? pathOrder : a.message.compareTo(b.message);
      });
      return ProjectScanResult(
        project: project,
        files: files,
        diagnostics: diagnostics,
      );
    }

    late String resolvedRoot;
    try {
      resolvedRoot = p.normalize(
        p.absolute(await fileSystem.resolveRoot(root)),
      );
      if (await fileSystem.type(resolvedRoot) !=
          FileSystemEntityType.directory) {
        report(null, 'Project root is not a directory.');
        return result();
      }
    } on FileSystemException catch (error) {
      report(null, 'Cannot access project root: ${error.message}');
      return result();
    }

    const pubspecPath = 'pubspec.yaml';
    late String pubspec;
    try {
      final type = await fileSystem.type(p.join(resolvedRoot, pubspecPath));
      if (type != FileSystemEntityType.file) {
        report(pubspecPath, 'Expected a regular pubspec.yaml file.', false);
        return result();
      }
      pubspec = await fileSystem.read(p.join(resolvedRoot, pubspecPath));
    } on FileSystemException catch (error) {
      report(pubspecPath, 'Cannot read pubspec.yaml: ${error.message}');
      return result();
    } on FormatException catch (error) {
      report(pubspecPath, 'Cannot decode pubspec.yaml: ${error.message}');
      return result();
    }

    late String packageName;
    late ProjectKind kind;
    try {
      final yaml = loadYaml(pubspec);
      if (yaml is! Map ||
          yaml['name'] is! String ||
          !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(yaml['name'] as String)) {
        report(
          pubspecPath,
          'pubspec.yaml must contain a valid package name.',
          false,
        );
        return result();
      }
      packageName = yaml['name'] as String;
      final dependencies = yaml['dependencies'];
      final flutter = dependencies is Map ? dependencies['flutter'] : null;
      kind = flutter is Map && flutter['sdk'] == 'flutter'
          ? ProjectKind.flutter
          : ProjectKind.dart;
    } on YamlException catch (error) {
      report(pubspecPath, 'Malformed pubspec.yaml: ${error.message}', false);
      return result();
    }

    final scopes = <SourceScope>[];
    Future<void> walk(String directory, SourceScope scope) async {
      try {
        await for (final entity in fileSystem.list(directory)) {
          final relative = p.relative(entity.path, from: resolvedRoot);
          final id = p.split(relative).join('/');
          try {
            final type = await fileSystem.type(entity.path);
            if (type == FileSystemEntityType.directory) {
              await walk(entity.path, scope);
            } else if (type == FileSystemEntityType.file &&
                p.extension(entity.path) == '.dart') {
              String? content;
              try {
                content = await fileSystem.read(entity.path);
              } on FileSystemException catch (error) {
                report(id, 'Cannot read source: ${error.message}');
              } on FormatException catch (error) {
                report(id, 'Cannot decode source: ${error.message}');
              }
              files.add(
                SourceFile(
                  relativePath: id,
                  scope: scope,
                  isGenerated:
                      id.endsWith('.g.dart') || id.endsWith('.freezed.dart'),
                  readState: content == null
                      ? SourceReadState.unreadable
                      : SourceReadState.readable,
                  content: content,
                ),
              );
            }
            // Links are intentionally ignored, including links to source files.
          } on FileSystemException catch (error) {
            report(id, 'Cannot inspect entry: ${error.message}');
          }
        }
      } on FileSystemException catch (error) {
        report(
          p.split(p.relative(directory, from: resolvedRoot)).join('/'),
          'Cannot list directory: ${error.message}',
        );
      }
    }

    for (final scope in SourceScope.values) {
      final directory = p.join(resolvedRoot, scope.name);
      try {
        final type = await fileSystem.type(directory);
        if (type == FileSystemEntityType.directory) {
          scopes.add(scope);
          await walk(directory, scope);
        } else if (type != FileSystemEntityType.notFound) {
          report(scope.name, 'Source scope is not a regular directory.');
        }
      } on FileSystemException catch (error) {
        report(scope.name, 'Cannot access source scope: ${error.message}');
      }
    }
    project = ProjectInfo(
      root: resolvedRoot,
      packageName: packageName,
      kind: kind,
      sourceScopes: scopes,
    );
    return result();
  }
}
