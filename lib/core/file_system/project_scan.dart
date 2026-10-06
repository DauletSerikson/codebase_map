import '../analysis/source_location.dart';

/// Project recognition and source discovery models, independent of Flutter.
enum ProjectKind { dart, flutter }

enum SourceScope { lib, test }

enum SourceReadState { readable, unreadable }

enum DiagnosticCategory { fileSystem, project, syntax, resolution }

class Diagnostic {
  const Diagnostic({
    required this.category,
    required this.message,
    this.path,
    this.location,
    this.code,
  });

  final DiagnosticCategory category;
  final String message;
  final SourceLocation? location;
  final String? code;

  /// Project-relative, slash-separated path; null denotes the project root.
  final String? path;
}

class ProjectInfo {
  ProjectInfo({
    required this.root,
    required this.packageName,
    required this.kind,
    required Iterable<SourceScope> sourceScopes,
  }) : sourceScopes = List.unmodifiable(sourceScopes);

  /// Absolute native path to the resolved project directory, never a file ID.
  final String root;
  final String packageName;
  final ProjectKind kind;
  final List<SourceScope> sourceScopes;
}

class SourceFile {
  const SourceFile({
    required this.relativePath,
    required this.scope,
    required this.isGenerated,
    required this.readState,
    required this.content,
  });

  String get id => relativePath;
  final String relativePath;
  final SourceScope scope;
  final bool isGenerated;
  final SourceReadState readState;

  /// Decoded source for the next pipeline stage; null if reading failed.
  final String? content;
}

class ProjectScanResult {
  ProjectScanResult({
    required this.project,
    required Iterable<SourceFile> files,
    required Iterable<Diagnostic> diagnostics,
  }) : files = List.unmodifiable(files),
       diagnostics = List.unmodifiable(diagnostics);

  /// Null when the root/pubspec cannot be read or recognized.
  final ProjectInfo? project;
  final List<SourceFile> files;
  final List<Diagnostic> diagnostics;
}
