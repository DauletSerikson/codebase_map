# Dependency graph (Stage 3)

`Dependency` is one source declaration variant; `DependencyEdge` is a unique
(source ID, target ID, type) local connection. `DependencyGraph` stores sorted
node IDs and edges plus immutable incoming/outgoing indexes, including empty
entries for isolated files. Cycles and self-loops are ordinary connections.

Duplicate declarations and branches remain in the snapshot's dependencies but
share one edge when their endpoints and type match. Different types between the
same files remain distinct edges. Index entries reference the same edge objects.
Only resolved dependencies with both endpoints in the node set are accepted.
No Flutter/AST types or layout logic are present.


## Graph queries (Stage 4)

`GraphQueries(snapshot)` provides pure queries over an existing snapshot:

- `search(query)` searches filename/relative path by case-insensitive substring,
  trims surrounding query whitespace, and returns results sorted by stable ID.
  Empty query returns all files, including hidden/generated/unreadable files.
  Search uses Dart lowercase conversion, not locale-specific case folding.
- `visible(filters: ...)` returns an immutable `GraphView` of node IDs and typed
  local edges. `GraphFilters` controls lib, test, generated files and
  import/export/part edges. All defaults are enabled; UI chooses initial settings.
  Both endpoints must remain visible. Isolated nodes are retained.
- `focus(fileId, filters: ...)` uses the filtered graph and returns selected node
  plus its direct incoming/outgoing neighbours only, with all edges between those
  nodes. It does not expand transitively. Cycles/self-loops are supported. Unknown
  or filtered-out selection returns null; callers can reveal it via filters first.
  Exiting Focus requires only calling `visible` again, without reanalysis.
- `inspect(fileId)` returns full snapshot details, independent of filters: path,
  nullable line count, all declared outgoing dependency variants, incoming local
  typed edges and file diagnostics. Unknown ID returns null. Project diagnostics
  remain on the snapshot rather than being assigned to every file.

Inspector imports count is the number of import declarations (duplicates count;
conditional variants share one declaration). Imported-by count is the number of
unique local importing files (duplicates/variants count once; exports/parts do
not count; a self-import counts). `usedBy` includes all incoming dependency types.
External/unresolved dependencies remain available in Inspector without creating
visible graph nodes. Query results retain references to immutable snapshot records
and never mutate the snapshot or perform IO/analysis. UI integration is deferred.
