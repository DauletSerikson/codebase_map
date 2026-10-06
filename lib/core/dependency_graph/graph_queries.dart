import '../analysis/analysis_snapshot.dart';
import '../analysis/directive.dart';
import '../file_system/project_scan.dart';
import 'dependency.dart';

/// All defaults show the full snapshot; UI chooses its initial filter settings.
class GraphFilters {
  const GraphFilters({
    this.includeLib = true,
    this.includeTest = true,
    this.includeGenerated = true,
    this.includeImports = true,
    this.includeExports = true,
    this.includeParts = true,
  });

  final bool includeLib;
  final bool includeTest;
  final bool includeGenerated;
  final bool includeImports;
  final bool includeExports;
  final bool includeParts;

  bool includesFile(SourceFile file) =>
      (file.scope == SourceScope.lib ? includeLib : includeTest) &&
      (includeGenerated || !file.isGenerated);

  bool includesType(DependencyType type) => switch (type) {
    DependencyType.import => includeImports,
    DependencyType.export => includeExports,
    DependencyType.part => includeParts,
  };
}

/// A derived view. File records and edges retain their snapshot identity.
class GraphView {
  GraphView({
    required Iterable<String> nodeIds,
    required Iterable<DependencyEdge> edges,
  }) : nodeIds = List.unmodifiable(nodeIds),
       edges = List.unmodifiable(edges);

  final List<String> nodeIds;
  final List<DependencyEdge> edges;
}

class FileInspector {
  FileInspector({
    required this.source,
    required Iterable<Dependency> dependencies,
    required Iterable<DependencyEdge> usedBy,
    required this.importsCount,
    required this.importedByCount,
    required Iterable<Diagnostic> diagnostics,
  }) : dependencies = List.unmodifiable(dependencies),
       usedBy = List.unmodifiable(usedBy),
       diagnostics = List.unmodifiable(diagnostics);

  final AnalyzedSource source;
  String get path => source.file.relativePath;
  int? get lineCount => source.lineCount;

  /// All declared outgoing variants, including unresolved/external ones.
  final List<Dependency> dependencies;

  /// Unique incoming local typed connections (imports, exports and parts).
  final List<DependencyEdge> usedBy;

  /// Number of import declarations, not conditional variants or unique targets.
  final int importsCount;

  /// Number of distinct local files importing this file; self-imports count.
  final int importedByCount;
  final List<Diagnostic> diagnostics;
}

/// Pure queries over a completed snapshot. No IO, parsing or mutable UI state.
class GraphQueries {
  const GraphQueries(this.snapshot);
  final AnalysisSnapshot snapshot;

  /// Case-insensitive substring search over stable relative paths (including
  /// filenames). Empty/whitespace-only query returns all files, sorted by ID.
  /// Search includes hidden files so a later UI can reveal a selected result.
  List<AnalyzedSource> search(String query) {
    final term = query.trim().toLowerCase();
    final ids =
        snapshot.files.keys
            .where((id) => id.toLowerCase().contains(term))
            .toList()
          ..sort();
    return List.unmodifiable(ids.map((id) => snapshot.files[id]!));
  }

  GraphView visible({GraphFilters filters = const GraphFilters()}) {
    final ids = snapshot.graph.nodeIds
        .where((id) => filters.includesFile(snapshot.files[id]!.file))
        .toList();
    final included = ids.toSet();
    return GraphView(
      nodeIds: ids,
      edges: snapshot.graph.edges.where(
        (edge) =>
            included.contains(edge.sourceId) &&
            included.contains(edge.targetId) &&
            filters.includesType(edge.type),
      ),
    );
  }

  /// Selected file plus one level of incoming/outgoing neighbours in the
  /// filtered graph. Null means an unknown or filtered-out selection.
  /// Edges are the induced subgraph on those nodes, including neighbour links.
  GraphView? focus(
    String fileId, {
    GraphFilters filters = const GraphFilters(),
  }) {
    final view = visible(filters: filters);
    if (!view.nodeIds.contains(fileId)) return null;
    final neighbours = <String>{fileId};
    for (final edge in view.edges) {
      if (edge.sourceId == fileId) neighbours.add(edge.targetId);
      if (edge.targetId == fileId) neighbours.add(edge.sourceId);
    }
    return GraphView(
      nodeIds: view.nodeIds.where(neighbours.contains),
      edges: view.edges.where(
        (edge) =>
            neighbours.contains(edge.sourceId) &&
            neighbours.contains(edge.targetId),
      ),
    );
  }

  /// Full snapshot details; visibility never changes statistics or diagnostics.
  FileInspector? inspect(String fileId) {
    final source = snapshot.files[fileId];
    if (source == null) return null;
    final usedBy = snapshot.graph.incoming[fileId]!;
    return FileInspector(
      source: source,
      dependencies: snapshot.dependencies.where((d) => d.sourceId == fileId),
      usedBy: usedBy,
      importsCount: source.directives
          .where((d) => d.type == DirectiveType.import)
          .length,
      importedByCount: usedBy
          .where((e) => e.type == DependencyType.import)
          .map((e) => e.sourceId)
          .toSet()
          .length,
      diagnostics: snapshot.diagnostics.where((d) => d.path == fileId),
    );
  }
}
