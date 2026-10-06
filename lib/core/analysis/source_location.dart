/// A source span. Offsets/lengths and columns use UTF-16 code units, as Dart does.
class SourceLocation {
  const SourceLocation({
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
  });

  final int offset;
  final int length;

  /// One-based line and column of the span's start.
  final int line;
  final int column;
}
