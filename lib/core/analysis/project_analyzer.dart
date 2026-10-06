import '../../analyzers/dart/dart_directive_analyzer.dart';
import '../../analyzers/dart/dart_uri_resolver.dart';
import '../dependency_graph/dependency.dart';
import '../file_system/project_scan.dart';
import '../file_system/project_scanner.dart';
import 'analysis_snapshot.dart';
import 'directive.dart';
import 'source_location.dart';

class ProjectAnalyzer {
  const ProjectAnalyzer({this.fileSystem = const ProjectFileSystem()});
  final ProjectFileSystem fileSystem;

  Future<AnalysisSnapshot> analyze(String root) async {
    final scan = await ProjectScanner(fileSystem: fileSystem).scan(root);
    final files = <String, AnalyzedSource>{};
    final dependencies = <Dependency>[];
    final diagnostics = [...scan.diagnostics];
    for (final file in scan.files) {
      final content = file.content;
      final parsed = content == null
          ? null
          : const DartDirectiveAnalyzer().analyze(
              fileId: file.id,
              source: content,
            );
      files[file.id] = AnalyzedSource(
        file: file,
        lineCount: parsed?.lineCount,
        directives: parsed?.directives ?? [],
        libraryName: parsed?.libraryName,
      );
      diagnostics.addAll(parsed?.diagnostics ?? []);
    }
    final project = scan.project;
    if (project != null) {
      final resolver = DartUriResolver(fileSystem: fileSystem);
      final fileIds = files.keys.toSet();
      void report(
        String id,
        SourceLocation location,
        String code,
        String message,
      ) {
        diagnostics.add(
          Diagnostic(
            category: DiagnosticCategory.resolution,
            path: id,
            location: location,
            code: code,
            message: message,
          ),
        );
      }

      Future<UriResolution> resolve(String id, String? uri) => resolver.resolve(
        project: project,
        fileIds: fileIds,
        sourceId: id,
        originalUri: uri,
      );
      for (final source in files.values) {
        for (final directive in source.directives) {
          if (directive.type == DirectiveType.partOf) continue;
          final type = switch (directive.type) {
            DirectiveType.import => DependencyType.import,
            DirectiveType.export => DependencyType.export,
            DirectiveType.part => DependencyType.part,
            DirectiveType.partOf => throw StateError('Not a dependency'),
          };
          Future<void> add(
            String? uri,
            SourceLocation location,
            ConditionalBranch? branch,
          ) async {
            final resolution = await resolve(source.id, uri);
            dependencies.add(
              Dependency(
                sourceId: source.id,
                type: type,
                uri: uri,
                location: location,
                status: resolution.status,
                targetId: resolution.targetId,
                branch: branch,
              ),
            );
            if (resolution.message != null) {
              report(
                source.id,
                location,
                resolution.status.name,
                resolution.message!,
              );
            }
          }

          await add(directive.uri, directive.location, null);
          for (final branch in directive.branches) {
            await add(branch.uri, branch.location, branch);
          }
        }
      }
      // Validate ownership using part declarations; never create part-of edges.
      final owners = <String, Set<String>>{};
      for (final dependency in dependencies) {
        if (dependency.type == DependencyType.part &&
            dependency.targetId != null) {
          owners
              .putIfAbsent(dependency.targetId!, () => {})
              .add(dependency.sourceId);
        }
      }
      for (final source in files.values) {
        final partOf = source.directives
            .where((d) => d.type == DirectiveType.partOf)
            .toList();
        final declaredOwners = owners[source.id] ?? <String>{};
        if (source.file.content == null) continue;
        if (declaredOwners.isNotEmpty && partOf.isEmpty) {
          for (final owner in declaredOwners) {
            final declaration = dependencies.firstWhere(
              (d) =>
                  d.sourceId == owner &&
                  d.type == DependencyType.part &&
                  d.targetId == source.id,
            );
            report(
              owner,
              declaration.location,
              'missing_part_of',
              'Part ${source.id} has no part of declaration.',
            );
          }
        }
        for (final directive in partOf) {
          if (declaredOwners.isEmpty) {
            report(
              source.id,
              directive.location,
              'orphan_part',
              'No scanned library declares this file as a part.',
            );
          }
          if (directive.uri != null) {
            final resolution = await resolve(source.id, directive.uri);
            if (resolution.status != ResolutionStatus.resolved) {
              report(
                source.id,
                directive.location,
                'part_of_${resolution.status.name}',
                resolution.message ??
                    'Part owner is outside the scanned sources.',
              );
            } else if (!declaredOwners.contains(resolution.targetId)) {
              report(
                source.id,
                directive.location,
                'part_of_mismatch',
                'The referenced library does not declare this file as a part.',
              );
            }
            for (final owner in declaredOwners) {
              if (owner != resolution.targetId) {
                report(
                  source.id,
                  directive.location,
                  'part_of_mismatch',
                  'Part declaration in $owner does not match part of.',
                );
              }
            }
          } else if (directive.libraryName != null) {
            for (final owner in declaredOwners) {
              if (files[owner]!.libraryName != directive.libraryName) {
                report(
                  source.id,
                  directive.location,
                  'part_of_mismatch',
                  'Named part of does not match library $owner.',
                );
              }
            }
          }
          if (declaredOwners.length > 1 || partOf.length > 1) {
            report(
              source.id,
              directive.location,
              'multiple_part_owners',
              'A part must belong to exactly one library.',
            );
          }
        }
      }
    }
    diagnostics.sort((a, b) {
      final path = (a.path ?? '').compareTo(b.path ?? '');
      if (path != 0) return path;
      final offset = (a.location?.offset ?? -1).compareTo(
        b.location?.offset ?? -1,
      );
      return offset != 0 ? offset : a.message.compareTo(b.message);
    });
    return AnalysisSnapshot(
      project: project,
      files: files,
      dependencies: dependencies,
      diagnostics: diagnostics,
    );
  }
}
