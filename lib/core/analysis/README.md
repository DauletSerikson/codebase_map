# Full project analysis (Stage 3)

`ProjectAnalyzer().analyze(root)` runs recognition/scanning, AST directive parsing,
Dart URI resolution, part ownership validation, and returns `AnalysisSnapshot`.
The result and all collections are immutable and use our pure-Dart domain types.

- `project` is null on recognition failure, with scanner diagnostics retained.
- `files` maps stable relative IDs to `AnalyzedSource` (scanner record, directives,
  declared library name, nullable line count). Unreadable and isolated files remain
  nodes. An unreadable source has null line count and no parsed directives.
- `dependencies` retains every import/export/part URI variant and duplicate,
  with location, type, conditional branch and resolution status. A `targetId`
  exists only when a target belongs to the scanned file set.
- `graph` indexes unique typed local edges. External, missing, out-of-scope and
  invalid targets never become nodes. Exports remain direct, not transitive.
- URI and named `part of` validate owners declared via `part`. Missing, mismatched,
  orphan and multiple ownership receive resolution diagnostics. No reverse edge
  is created. Unreadable parts cannot be validated; their IO diagnostic remains.
- Diagnostics combine scanner, syntax and resolution issues and sort by path,
  position and message. Files/dependencies follow sorted files and source order.

Graph queries, filtering, focus and Inspector are provided separately by
`core/dependency_graph/graph_queries.dart` (Stage 4). No UI, persistence or
incremental analysis is implemented. Scanning/probing is not atomic; concurrent filesystem edits may
produce partial results. Native Windows/Linux execution remains to be verified.
