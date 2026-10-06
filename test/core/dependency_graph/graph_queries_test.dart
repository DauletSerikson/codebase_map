import 'package:codebase_map/core/analysis/analysis_snapshot.dart';
import 'package:codebase_map/core/analysis/directive.dart';
import 'package:codebase_map/core/analysis/source_location.dart';
import 'package:codebase_map/core/dependency_graph/dependency.dart';
import 'package:codebase_map/core/dependency_graph/graph_queries.dart';
import 'package:codebase_map/core/file_system/project_scan.dart';
import 'package:flutter_test/flutter_test.dart';

const location = SourceLocation(offset: 0, length: 1, line: 1, column: 1);

void main() {
  late AnalysisSnapshot snapshot;
  late GraphQueries queries;
  AnalyzedSource source(
    String id, {
    bool generated = false,
    bool unreadable = false,
    List<Directive> directives = const [],
  }) => AnalyzedSource(
    file: SourceFile(
      relativePath: id,
      scope: id.startsWith('test/') ? SourceScope.test : SourceScope.lib,
      isGenerated: generated,
      readState: unreadable
          ? SourceReadState.unreadable
          : SourceReadState.readable,
      content: unreadable ? null : '',
    ),
    lineCount: unreadable ? null : 5,
    directives: directives,
  );
  Dependency dependency(
    String from,
    String? to,
    DependencyType type, {
    ResolutionStatus status = ResolutionStatus.resolved,
    ConditionalBranch? branch,
  }) => Dependency(
    sourceId: from,
    targetId: to,
    uri: to ?? 'package:external/a.dart',
    type: type,
    status: status,
    location: location,
    branch: branch,
  );

  setUp(() {
    // Deliberately unordered files exercise search's deterministic ordering.
    final files = [
      source('test/auth_test.dart'),
      source('lib/isolated.dart'),
      source('lib/auth/state.g.dart', generated: true),
      source(
        'lib/auth/service.dart',
        directives: [
          Directive(
            type: DirectiveType.import,
            location: location,
            uri: 'a.dart',
          ),
          Directive(
            type: DirectiveType.import,
            location: location,
            uri: 'a.dart',
          ),
          Directive(
            type: DirectiveType.import,
            location: location,
            uri: 'base.dart',
            branches: [
              const ConditionalBranch(
                variable: 'flag',
                value: null,
                uri: 'alternate.dart',
                uriLiteral: "'alternate.dart'",
                location: location,
              ),
            ],
          ),
          Directive(
            type: DirectiveType.export,
            location: location,
            uri: 'b.dart',
          ),
        ],
      ),
      source('lib/a.dart'),
      source('lib/b.dart'),
      source('lib/Ж folder/Screen.dart'),
      source('lib/unreadable.dart', unreadable: true),
    ];
    snapshot = AnalysisSnapshot(
      project: null,
      files: {for (final file in files) file.id: file},
      dependencies: [
        dependency(
          'lib/auth/service.dart',
          'lib/a.dart',
          DependencyType.import,
        ),
        dependency(
          'lib/auth/service.dart',
          'lib/a.dart',
          DependencyType.import,
        ),
        dependency(
          'lib/auth/service.dart',
          'lib/b.dart',
          DependencyType.import,
          branch: const ConditionalBranch(
            variable: 'flag',
            value: null,
            uri: 'b.dart',
            uriLiteral: "'b.dart'",
            location: location,
          ),
        ),
        dependency(
          'lib/auth/service.dart',
          null,
          DependencyType.import,
          status: ResolutionStatus.externalPackage,
        ),
        dependency(
          'lib/auth/service.dart',
          null,
          DependencyType.export,
          status: ResolutionStatus.unresolved,
        ),
        dependency(
          'lib/auth/service.dart',
          'lib/auth/state.g.dart',
          DependencyType.part,
        ),
        dependency(
          'test/auth_test.dart',
          'lib/auth/service.dart',
          DependencyType.import,
        ),
        dependency(
          'lib/a.dart',
          'lib/auth/service.dart',
          DependencyType.import,
        ),
        dependency(
          'lib/a.dart',
          'lib/auth/service.dart',
          DependencyType.export,
        ),
        dependency('lib/b.dart', 'lib/a.dart', DependencyType.export),
        dependency(
          'lib/Ж folder/Screen.dart',
          'lib/b.dart',
          DependencyType.import,
        ),
        dependency('lib/a.dart', 'lib/a.dart', DependencyType.import),
      ],
      diagnostics: [
        const Diagnostic(
          category: DiagnosticCategory.resolution,
          path: 'lib/auth/service.dart',
          location: location,
          message: 'Missing target',
        ),
        const Diagnostic(
          category: DiagnosticCategory.fileSystem,
          path: 'lib/unreadable.dart',
          message: 'Read failure',
        ),
        const Diagnostic(
          category: DiagnosticCategory.project,
          message: 'Project diagnostic',
        ),
      ],
    );
    queries = GraphQueries(snapshot);
  });

  test(
    'search finds filenames and relative paths, ignores case and trims query',
    () {
      expect(queries.search('  SERVICE.DART ').map((f) => f.id), [
        'lib/auth/service.dart',
      ]);
      expect(queries.search('auth/').map((f) => f.id), [
        'lib/auth/service.dart',
        'lib/auth/state.g.dart',
      ]);
      expect(queries.search('auth').map((f) => f.id), [
        'lib/auth/service.dart',
        'lib/auth/state.g.dart',
        'test/auth_test.dart',
      ]);
      expect(queries.search('ж FOLDER/screen').map((f) => f.id), [
        'lib/Ж folder/Screen.dart',
      ]);
      expect(queries.search('no match'), isEmpty);
      expect(queries.search('  ').map((f) => f.id), snapshot.graph.nodeIds);
      expect(
        identical(
          queries.search('service').single,
          snapshot.files['lib/auth/service.dart'],
        ),
        isTrue,
      );
    },
  );

  test('default view is complete, including isolated and unreadable files', () {
    final view = queries.visible();
    expect(view.nodeIds, snapshot.graph.nodeIds);
    expect(view.edges, snapshot.graph.edges);
    expect(
      view.nodeIds,
      containsAll(['lib/isolated.dart', 'lib/unreadable.dart']),
    );
  });

  test('lib/test/generated filters remove edges with hidden endpoints', () {
    final lib = queries.visible(
      filters: const GraphFilters(includeTest: false),
    );
    expect(lib.nodeIds.any((id) => id.startsWith('test/')), isFalse);
    expect(lib.edges.any((e) => e.sourceId.startsWith('test/')), isFalse);
    final test = queries.visible(
      filters: const GraphFilters(includeLib: false),
    );
    expect(test.nodeIds, ['test/auth_test.dart']);
    expect(test.edges, isEmpty);
    final generated = queries.visible(
      filters: const GraphFilters(includeGenerated: false),
    );
    expect(generated.nodeIds, isNot(contains('lib/auth/state.g.dart')));
    expect(generated.edges.any((e) => e.type == DependencyType.part), isFalse);
    expect(
      queries
          .visible(
            filters: const GraphFilters(includeLib: false, includeTest: false),
          )
          .nodeIds,
      isEmpty,
    );
  });

  test(
    'each dependency type can be hidden without removing isolated nodes',
    () {
      for (final filters in [
        const GraphFilters(includeExports: false, includeParts: false),
        const GraphFilters(includeImports: false, includeParts: false),
        const GraphFilters(includeImports: false, includeExports: false),
      ]) {
        final view = queries.visible(filters: filters);
        expect(view.nodeIds, snapshot.graph.nodeIds);
        expect(view.edges, isNotEmpty);
        expect(view.edges.every((e) => filters.includesType(e.type)), isTrue);
      }
      final emptyEdges = queries.visible(
        filters: const GraphFilters(
          includeImports: false,
          includeExports: false,
          includeParts: false,
        ),
      );
      expect(emptyEdges.nodeIds, snapshot.graph.nodeIds);
      expect(emptyEdges.edges, isEmpty);
    },
  );

  test(
    'focus contains only selected and direct incoming/outgoing neighbours',
    () {
      final focus = queries.focus('lib/auth/service.dart')!;
      expect(focus.nodeIds, [
        'lib/a.dart',
        'lib/auth/service.dart',
        'lib/auth/state.g.dart',
        'lib/b.dart',
        'test/auth_test.dart',
      ]);
      expect(focus.nodeIds, isNot(contains('lib/Ж folder/Screen.dart')));
      expect(
        focus.edges.any(
          (e) => e.sourceId == 'lib/b.dart' && e.targetId == 'lib/a.dart',
        ),
        isTrue,
      );
      expect(focus.edges.any((e) => e.sourceId == e.targetId), isTrue);
      expect(
        focus.edges.every(
          (e) =>
              focus.nodeIds.contains(e.sourceId) &&
              focus.nodeIds.contains(e.targetId),
        ),
        isTrue,
      );
    },
  );

  test('focus respects combined filters and keeps isolated selected node', () {
    const filters = GraphFilters(
      includeTest: false,
      includeGenerated: false,
      includeImports: false,
      includeParts: false,
    );
    final focus = queries.focus('lib/auth/service.dart', filters: filters)!;
    expect(focus.nodeIds, ['lib/a.dart', 'lib/auth/service.dart']);
    expect(focus.edges.single.type, DependencyType.export);
    expect(queries.focus('lib/isolated.dart')!.nodeIds, ['lib/isolated.dart']);
    expect(queries.focus('lib/isolated.dart')!.edges, isEmpty);
    expect(queries.focus('unknown'), isNull);
    expect(queries.focus('test/auth_test.dart', filters: filters), isNull);
    expect(queries.focus('lib/auth/state.g.dart', filters: filters), isNull);
  });

  test(
    'inspector retains outgoing variants and full statistics across filters',
    () {
      final inspector = queries.inspect('lib/auth/service.dart')!;
      expect(inspector.path, 'lib/auth/service.dart');
      expect(inspector.lineCount, 5);
      expect(inspector.importsCount, 3);
      expect(inspector.importedByCount, 2);
      expect(inspector.dependencies, hasLength(6));
      expect(
        inspector.dependencies.where((d) => d.targetId == null),
        hasLength(2),
      );
      expect(
        inspector.dependencies.where((d) => d.branch != null),
        hasLength(1),
      );
      expect(inspector.usedBy, hasLength(3));
      expect(inspector.diagnostics.single.message, 'Missing target');
      queries.visible(filters: const GraphFilters(includeLib: false));
      expect(
        queries.inspect(inspector.path)!.dependencies,
        inspector.dependencies,
      );
      expect(queries.inspect(inspector.path)!.importedByCount, 2);
      expect(queries.search('state.g').single.id, 'lib/auth/state.g.dart');
      expect(queries.inspect('missing'), isNull);
      expect(
        queries.inspect('lib/a.dart')!.importedByCount,
        2,
      ); // service and self
    },
  );

  test(
    'inspector handles unreadable and isolated sources without inventing data',
    () {
      final unreadable = queries.inspect('lib/unreadable.dart')!;
      expect(unreadable.lineCount, isNull);
      expect(unreadable.importsCount, 0);
      expect(unreadable.importedByCount, 0);
      expect(unreadable.diagnostics.single.message, 'Read failure');
      final isolated = queries.inspect('lib/isolated.dart')!;
      expect(isolated.dependencies, isEmpty);
      expect(isolated.usedBy, isEmpty);
      expect(isolated.diagnostics, isEmpty);
    },
  );

  test(
    'derived collections are immutable and snapshot survives repeated queries',
    () {
      final view = queries.visible();
      final inspector = queries.inspect('lib/auth/service.dart')!;
      expect(() => view.nodeIds.clear(), throwsUnsupportedError);
      expect(() => view.edges.clear(), throwsUnsupportedError);
      expect(() => queries.search('').clear(), throwsUnsupportedError);
      expect(() => inspector.dependencies.clear(), throwsUnsupportedError);
      expect(() => inspector.usedBy.clear(), throwsUnsupportedError);
      expect(() => inspector.diagnostics.clear(), throwsUnsupportedError);
      expect(
        () => queries.focus('lib/a.dart')!.edges.clear(),
        throwsUnsupportedError,
      );
      for (var i = 0; i < 3; i++) {
        queries.visible(filters: const GraphFilters(includeGenerated: false));
        queries.focus('lib/a.dart');
        queries.inspect('lib/b.dart');
        queries.search('b');
      }
      expect(queries.visible().nodeIds, view.nodeIds);
      expect(queries.visible().edges, view.edges);
      expect(snapshot.files, hasLength(8));
      expect(snapshot.dependencies, hasLength(12));
      expect(snapshot.diagnostics, hasLength(3));
    },
  );

  test('empty snapshot queries have well-defined results', () {
    final empty = GraphQueries(
      AnalysisSnapshot(
        project: null,
        files: {},
        dependencies: [],
        diagnostics: [],
      ),
    );
    expect(empty.search(''), isEmpty);
    expect(empty.visible().nodeIds, isEmpty);
    expect(empty.visible().edges, isEmpty);
    expect(empty.focus('lib/a.dart'), isNull);
    expect(empty.inspect('lib/a.dart'), isNull);
  });
}
