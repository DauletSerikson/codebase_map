import 'dependency.dart';

class DependencyGraph {
  factory DependencyGraph({
    required Iterable<String> nodeIds,
    required Iterable<Dependency> dependencies,
  }) {
    final nodes = nodeIds.toSet().toList()..sort();
    final nodeSet = nodes.toSet();
    final unique = <(String, String, DependencyType), DependencyEdge>{};
    for (final dependency in dependencies) {
      if (dependency.status != ResolutionStatus.resolved) continue;
      final target = dependency.targetId;
      if (target == null ||
          !nodeSet.contains(dependency.sourceId) ||
          !nodeSet.contains(target)) {
        throw ArgumentError(
          'Resolved dependency endpoints must be graph nodes.',
        );
      }
      final key = (dependency.sourceId, target, dependency.type);
      unique.putIfAbsent(
        key,
        () => DependencyEdge(
          sourceId: dependency.sourceId,
          targetId: target,
          type: dependency.type,
        ),
      );
    }
    final edges = unique.values.toList()
      ..sort((a, b) {
        final source = a.sourceId.compareTo(b.sourceId);
        if (source != 0) return source;
        final target = a.targetId.compareTo(b.targetId);
        return target != 0 ? target : a.type.index.compareTo(b.type.index);
      });
    final incoming = {for (final id in nodes) id: <DependencyEdge>[]};
    final outgoing = {for (final id in nodes) id: <DependencyEdge>[]};
    for (final edge in edges) {
      incoming[edge.targetId]!.add(edge);
      outgoing[edge.sourceId]!.add(edge);
    }
    return DependencyGraph._(
      List.unmodifiable(nodes),
      List.unmodifiable(edges),
      Map.unmodifiable(
        incoming.map(
          (id, list) => MapEntry(id, List<DependencyEdge>.unmodifiable(list)),
        ),
      ),
      Map.unmodifiable(
        outgoing.map(
          (id, list) => MapEntry(id, List<DependencyEdge>.unmodifiable(list)),
        ),
      ),
    );
  }

  const DependencyGraph._(
    this.nodeIds,
    this.edges,
    this.incoming,
    this.outgoing,
  );
  final List<String> nodeIds;
  final List<DependencyEdge> edges;
  final Map<String, List<DependencyEdge>> incoming;
  final Map<String, List<DependencyEdge>> outgoing;
}
