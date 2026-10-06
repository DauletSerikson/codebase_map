import '../analysis/directive.dart';
import '../analysis/source_location.dart';

enum DependencyType { import, export, part }

enum ResolutionStatus {
  resolved,
  sdk,
  externalPackage,
  outOfScope,
  unresolved,
  invalidUri,
  fileSystemError,
}

/// One declared URI variant, including duplicates and conditional alternatives.
class Dependency {
  const Dependency({
    required this.sourceId,
    required this.type,
    required this.uri,
    required this.location,
    required this.status,
    this.targetId,
    this.branch,
  });

  final String sourceId;
  final DependencyType type;
  final String? uri;
  final SourceLocation location;
  final ResolutionStatus status;

  /// Only set for a target present in the scanned file set.
  final String? targetId;
  final ConditionalBranch? branch;
}

/// A unique local connection, independent of declaration count.
class DependencyEdge {
  const DependencyEdge({
    required this.sourceId,
    required this.targetId,
    required this.type,
  });
  final String sourceId;
  final String targetId;
  final DependencyType type;
}
