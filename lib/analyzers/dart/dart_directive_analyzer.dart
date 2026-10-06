import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/source/line_info.dart';

import '../../core/analysis/directive.dart';
import '../../core/analysis/source_location.dart';
import '../../core/file_system/project_scan.dart';

class DartDirectiveResult {
  DartDirectiveResult({
    required this.fileId,
    this.libraryName,
    required this.lineCount,
    required Iterable<Directive> directives,
    required Iterable<Diagnostic> diagnostics,
  }) : directives = List.unmodifiable(directives),
       diagnostics = List.unmodifiable(diagnostics);

  final String fileId;
  final String? libraryName;
  final int lineCount;
  final List<Directive> directives;
  final List<Diagnostic> diagnostics;
}

/// Parses one source string without IO, SDK resolution, or platform conditions.
class DartDirectiveAnalyzer {
  const DartDirectiveAnalyzer();

  DartDirectiveResult analyze({
    required String fileId,
    required String source,
  }) {
    final parsed = parseString(
      content: source,
      path: fileId,
      throwIfDiagnostics: false,
    );
    final lineInfo = LineInfo.fromContent(source);
    SourceLocation location(int offset, int length) {
      final start = lineInfo.getLocation(offset);
      return SourceLocation(
        offset: offset,
        length: length,
        line: start.lineNumber,
        column: start.columnNumber,
      );
    }

    final literalDiagnostics = <Diagnostic>[];
    String? decodedUri(ast.StringLiteral? literal) {
      if (literal == null) return null;
      final value = literal.stringValue;
      if (value == null) {
        literalDiagnostics.add(
          Diagnostic(
            category: DiagnosticCategory.syntax,
            path: fileId,
            message: 'A directive URI must be a constant string without interpolation.',
            code: 'invalid_directive_uri',
            location: location(literal.offset, literal.length),
          ),
        );
      }
      return value;
    }

    String? declaredLibraryName;
    final directives = <Directive>[];
    for (final node in parsed.unit.directives) {
      if (node is ast.LibraryDirective) {
        declaredLibraryName = node.name?.toSource();
        continue;
      }
      final DirectiveType type;
      ast.StringLiteral? uri;
      String? libraryName;
      if (node is ast.ImportDirective) {
        type = DirectiveType.import;
        uri = node.uri;
      } else if (node is ast.ExportDirective) {
        type = DirectiveType.export;
        uri = node.uri;
      } else if (node is ast.PartDirective) {
        type = DirectiveType.part;
        uri = node.uri;
      } else if (node is ast.PartOfDirective) {
        type = DirectiveType.partOf;
        uri = node.uri;
        libraryName = node.libraryName?.toSource();
      } else {
        continue;
      }
      directives.add(
        Directive(
          type: type,
          location: location(node.offset, node.length),
          uri: decodedUri(uri),
          uriLiteral: uri == null
              ? null
              : source.substring(uri.offset, uri.end),
          libraryName: libraryName,
          isDeferred:
              node is ast.ImportDirective && node.deferredKeyword != null,
          branches: node is ast.NamespaceDirective
              ? node.configurations.map(
                  (branch) => ConditionalBranch(
                    variable: branch.name.toSource(),
                    value: branch.value?.stringValue,
                    uri: decodedUri(branch.uri),
                    uriLiteral: source.substring(
                      branch.uri.offset,
                      branch.uri.end,
                    ),
                    location: location(branch.offset, branch.length),
                  ),
                )
              : const [],
        ),
      );
    }
    final diagnostics =
        [
          ...literalDiagnostics,
          ...parsed.errors.map(
            (error) => Diagnostic(
              category: DiagnosticCategory.syntax,
              path: fileId,
              message: error.message,
              code: error.diagnosticCode.lowerCaseName,
              location: location(error.offset, error.length),
            ),
          ),
        ]..sort((a, b) {
          final offsetOrder = a.location!.offset.compareTo(b.location!.offset);
          return offsetOrder != 0 ? offsetOrder : a.code!.compareTo(b.code!);
        });
    // Physical lines: an empty source has zero; a final newline terminates the
    // last line rather than adding another empty line. CRLF is one separator.
    final lineCount = source.isEmpty
        ? 0
        : lineInfo.lineCount -
              (source.endsWith('\n') || source.endsWith('\r') ? 1 : 0);
    return DartDirectiveResult(
      fileId: fileId,
      libraryName: declaredLibraryName,
      lineCount: lineCount,
      directives: directives,
      diagnostics: diagnostics,
    );
  }
}
