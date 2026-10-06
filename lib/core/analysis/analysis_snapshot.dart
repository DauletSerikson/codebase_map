import '../dependency_graph/dependency.dart';
import '../dependency_graph/dependency_graph.dart';
import '../file_system/project_scan.dart';
import 'directive.dart';

class AnalyzedSource {
  AnalyzedSource({
    required this.file,
    required this.lineCount,
    required Iterable<Directive> directives,
    this.libraryName,
  }) : directives = List.unmodifiable(directives);

  final SourceFile file;
  String get id => file.id;

  /// Null if source could not be read, rather than pretending it is empty.
  final int? lineCount;
  final String? libraryName;
  final List<Directive> directives;
}

class AnalysisSnapshot {
  AnalysisSnapshot({
    required this.project,
    required Map<String, AnalyzedSource> files,
    required Iterable<Dependency> dependencies,
    required Iterable<Diagnostic> diagnostics,
  }) : files = Map.unmodifiable(files),
       dependencies = List.unmodifiable(dependencies),
       diagnostics = List.unmodifiable(diagnostics),
       graph = DependencyGraph(nodeIds: files.keys, dependencies: dependencies);

  /// Null for an unrecognized project; scanner diagnostics explain the failure.
  final ProjectInfo? project;
  final Map<String, AnalyzedSource> files;
  final List<Dependency> dependencies;
  final List<Diagnostic> diagnostics;
  final DependencyGraph graph;
}
