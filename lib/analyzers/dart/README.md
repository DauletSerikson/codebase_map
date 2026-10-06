# Dart Directive Analyzer (Stage 2)

`DartDirectiveAnalyzer().analyze(fileId: ..., source: ...)` synchronously parses
one decoded source string using `package:analyzer` AST (`parseString`, recovery
enabled). It performs no IO, URI resolution, dependency construction or project
orchestration. Public results contain only our own pure-Dart models.

`DartDirectiveResult` provides file ID, physical line count, immutable directives
and diagnostics. `Directive` / `ConditionalBranch` / `SourceLocation` live in
`core/analysis`. The existing shared `Diagnostic` gains optional location/code
and a syntax category; scanner callers retain their existing contract.

- import, export, part and part of are separate declaration types.
- URI values are decoded, without normalization, alongside exact original
  literals (quotes, raw prefixes and escapes included).
- Named part of retains its library name and has no URI. No reverse edge is built.
- Conditional import/export retains the primary URI and every conditional
  branch, in source order, without evaluating platform/environment conditions.
  A branch retains its variable and optional equality value (null for a bare
  boolean condition).
- Deferred imports retain a flag. Prefixes and show/hide do not change the URI
  declaration and are not used for symbol analysis.
- Duplicate declarations remain separate. Comments and expression strings are
  never interpreted as directives.
- Positions are zero-based UTF-16 offsets/lengths and one-based line/column,
  covering the whole declaration or conditional branch. Diagnostics also have
  spans, messages and codes; malformed source returns recovered declarations.
  Interpolated URI literals are diagnosed via AST validation, not resolution.
- Empty source has zero physical lines. LF, CRLF and CR are supported. A trailing
  newline terminates the last line, without counting a further empty line.

Parsing uses analyzer's default latest supported language features and honors
source language-version comments. No SDK/package language-version resolution is
performed. Diagnostics are lexical/syntactic, not semantic or type checking.

## URI resolution (Stage 3)

`DartUriResolver` handles relative URIs, current `package:` URIs mapped to `lib`,
SDK `dart:` and external packages. URI normalization/percent decoding precedes
native filesystem operations. Parser results also retain the declared `library`
name for named part ownership validation.

Existing regular files outside the scanned set (including outside project root)
and skipped symlinks are `outOfScope`; missing files and directory targets are
`unresolved`. Probing does not follow symlink path components. Case-insensitive
filesystem spelling is canonicalized back to scanner IDs when needed.
Filesystem failures have their own status and diagnostic, not `unresolved`.
Unsupported schemes, absolute URI paths, queries/fragments, authority and encoded
path separators/NUL receive `invalidUri`. All conditional alternatives resolve
independently; no platform branch is selected. No external SDK/package source
lookup or multi-package workspace resolution is performed.
