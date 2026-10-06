# Project recognition and scanner (Stage 1)

Pure-Dart API: `ProjectScanner().scan(root)` returns an immutable
`ProjectScanResult` containing nullable `ProjectInfo`, `SourceFile` records and
`Diagnostic` records. No Flutter or AST types are used.

- Root is resolved to an absolute native directory path (a root symlink is allowed).
- A regular, readable `pubspec.yaml` with a valid package name identifies a Dart
  project. `dependencies.flutter.sdk: flutter` identifies Flutter.
- Unrecognized/unreadable roots or pubspecs return a null project and diagnostics.
- Existing `lib` and `test` directories are available scopes, including empty
  directories. Missing scopes are normal; inaccessible or non-directory scopes
  produce diagnostics. Recognition still succeeds when scanning a scope fails.
- Only regular `.dart` files in those scopes are collected recursively.
  Nested symlinks, including file links and broken links, are never followed.
  A symlink at a scope or pubspec location is diagnosed rather than followed.
- IDs are case-preserving project-relative paths with `/` separators. Native
  path operations use `package:path`; absolute paths are not IDs.
- `*.g.dart` and `*.freezed.dart` are flagged and retained.
- Files are read as UTF-8. A failed read/decode retains the file with null content
  and `unreadable` state. Directory errors retain partial results and permit
  other scopes to continue. No filesystem error is intentionally hidden.
- Files sort lexicographically by ID; diagnostics sort by path then message.
- `ProjectFileSystem` is the small IO boundary for reproducible failure tests.

Line counts and Dart directives belong to Stage 2. No analysis snapshot, graph,
resolution, UI opening flow or filesystem watching is implemented here.

Traversal is a one-shot scan, not an atomic filesystem snapshot. Concurrent
filesystem changes can produce diagnostics or partial results. Cross-platform
runtime verification remains part of v0.1 acceptance; native symlink tests are
skipped on Windows because creating links may require elevated privileges.
