import 'source_location.dart';

/// These declarations describe source only; they are not resolved dependencies.
enum DirectiveType { import, export, part, partOf }

class ConditionalBranch {
  const ConditionalBranch({
    required this.variable,
    required this.value,
    required this.uri,
    required this.uriLiteral,
    required this.location,
  });

  final String variable;

  /// Null means a boolean condition without an explicit equality test.
  final String? value;

  /// Decoded URI, without normalization; null for an invalid literal.
  final String? uri;
  final String uriLiteral;
  final SourceLocation location;
}

class Directive {
  Directive({
    required this.type,
    required this.location,
    this.uri,
    this.uriLiteral,
    this.libraryName,
    this.isDeferred = false,
    Iterable<ConditionalBranch> branches = const [],
  }) : branches = List.unmodifiable(branches);

  final DirectiveType type;
  final SourceLocation location;

  /// Decoded primary URI, without resolution or normalization. Also null for
  /// named `part of` and parser-recovered invalid literals.
  final String? uri;

  /// Exact original URI literal, including quotes/escapes, when present.
  final String? uriLiteral;
  final String? libraryName;
  final bool isDeferred;
  final List<ConditionalBranch> branches;
}
