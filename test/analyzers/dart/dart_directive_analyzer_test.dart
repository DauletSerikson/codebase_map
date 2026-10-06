import 'package:codebase_map/analyzers/dart/dart_directive_analyzer.dart';
import 'package:codebase_map/core/analysis/directive.dart';
import 'package:codebase_map/core/file_system/project_scan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DartDirectiveResult analyze(String source) => const DartDirectiveAnalyzer()
      .analyze(fileId: 'lib/Ж folder/sample.dart', source: source);

  test('import, export and generated part preserve type, URI and order', () {
    final result = analyze(
      "import 'dart:io';\nexport '../foo.dart';\npart 'a.g.dart';",
    );
    expect(result.directives.map((d) => d.type), [
      DirectiveType.import,
      DirectiveType.export,
      DirectiveType.part,
    ]);
    expect(result.directives.map((d) => d.uri), [
      'dart:io',
      '../foo.dart',
      'a.g.dart',
    ]);
    expect(result.diagnostics, isEmpty);
  });

  test(
    'formatting, comments, deferred and show/hide preserve declarations',
    () {
      final result = analyze('''
import
  /* between tokens */ "package:sample/foo.dart"
  deferred as foo show A, B hide C;
export 'bar.dart' show X hide Y;
''');
      expect(result.directives.map((d) => d.uri), [
        'package:sample/foo.dart',
        'bar.dart',
      ]);
      expect(result.directives.first.isDeferred, isTrue);
      expect(result.directives.last.isDeferred, isFalse);
      expect(result.diagnostics, isEmpty);
    },
  );

  test('comments and ordinary strings cannot create directives', () {
    final result = analyze('''
// import 'fake.dart';
/* export 'fake.dart'; part 'fake.g.dart'; */
const text = "import 'fake.dart';";
const other = r"part of 'fake.dart';";
''');
    expect(result.directives, isEmpty);
    expect(result.diagnostics, isEmpty);
  });

  test('conditional import/export retain every branch without evaluating', () {
    final result = analyze('''
import 'default.dart'
  if (dart.library.io) 'io.dart'
  if (dart.library.html == 'true') 'web.dart';
export 'base.dart'
  if (custom.flag == 'enabled') 'other.dart';
''');
    expect(result.directives.map((d) => d.uri), ['default.dart', 'base.dart']);
    final branches = result.directives.first.branches;
    expect(branches.map((b) => b.variable), [
      'dart.library.io',
      'dart.library.html',
    ]);
    expect(branches.map((b) => b.value), [null, 'true']);
    expect(branches.map((b) => b.uri), ['io.dart', 'web.dart']);
    expect(branches.first.location.line, 2);
    expect(branches.first.location.column, 3);
    expect(result.directives.last.branches.single.value, 'enabled');
    expect(result.diagnostics, isEmpty);
    expect(() => branches.clear(), throwsUnsupportedError);
  });

  test('URI and named part of stay distinct from part', () {
    final uri = analyze("part of 'owner.dart';").directives.single;
    expect(uri.type, DirectiveType.partOf);
    expect(uri.uri, 'owner.dart');
    expect(uri.libraryName, isNull);
    final named = analyze('part of sample.library;').directives.single;
    expect(named.type, DirectiveType.partOf);
    expect(named.libraryName, 'sample.library');
    expect(named.uri, isNull);
    expect(named.uriLiteral, isNull);
  });

  test('decoded and exact original URI are both retained', () {
    final result = analyze(r'''import 'folder/\u0061.dart';
export r'folder\b.dart';
''');
    expect(result.directives.first.uri, 'folder/a.dart');
    expect(result.directives.first.uriLiteral, r"'folder/\u0061.dart'");
    expect(result.directives.last.uri, r'folder\b.dart');
    expect(result.diagnostics, isEmpty);
  });

  for (final newline in ['\n', '\r\n', '\r']) {
    test('positions and physical line counts for ${newline.codeUnits}', () {
      final prefix = '// Ж 😀$newline  ';
      const directive = "import 'a.dart';";
      final result = analyze('$prefix$directive$newline');
      final location = result.directives.single.location;
      expect(location.offset, prefix.length);
      expect(location.length, directive.length);
      expect(location.line, 2);
      expect(location.column, 3);
      expect(result.lineCount, 2);
      expect(analyze('$prefix$directive').lineCount, 2);
      expect(analyze(newline).lineCount, 1);
      expect(result.diagnostics, isEmpty);
    });
  }

  test('empty source, blank lines and no final newline', () {
    final result = analyze('');
    expect(result.lineCount, 0);
    expect(result.directives, isEmpty);
    expect(result.diagnostics, isEmpty);
    expect(analyze('void main() {}').lineCount, 1);
    expect(analyze('\n\n').lineCount, 2);
    expect(() => result.directives.clear(), throwsUnsupportedError);
    expect(() => result.diagnostics.clear(), throwsUnsupportedError);
  });

  test(
    'malformed source returns located diagnostics and recovered directives',
    () {
      final result = analyze(
        "import 'a.dart';\nexport 'b.dart';\nvoid main( {",
      );
      expect(result.directives.map((d) => d.uri), ['a.dart', 'b.dart']);
      expect(result.diagnostics, isNotEmpty);
      for (final diagnostic in result.diagnostics) {
        expect(diagnostic.category, DiagnosticCategory.syntax);
        expect(diagnostic.path, result.fileId);
        expect(diagnostic.code, isNotEmpty);
        expect(diagnostic.message, isNotEmpty);
        expect(diagnostic.location!.line, 3);
        expect(diagnostic.location!.offset, greaterThanOrEqualTo(0));
      }
      expect(analyze("import 'good.dart';").diagnostics, isEmpty);
    },
  );

  test('malformed URI and scanner errors do not throw', () {
    for (final source in [
      "import ;",
      "import 'unterminated",
      '/* unterminated',
      r"import '$dynamicUri';",
      "import 'a.dart' if (flag) ;",
    ]) {
      final result = analyze(source);
      expect(result.diagnostics, isNotEmpty, reason: source);
    }
  });

  test('duplicate declarations are retained in source order', () {
    final result = analyze("import 'a.dart';\nimport 'a.dart';");
    expect(result.directives, hasLength(2));
    expect(result.directives.first.location.offset, 0);
    expect(result.directives.last.location.line, 2);
  });
}
