# Project workspace (Stage 6)

`HomePage` passes controller snapshot/selection and a single selection callback to
`ProjectWorkspace`. Wide windows use Tree | Map placeholder | Inspector columns;
narrow windows stack the panels. Each panel scrolls independently, and the page
also scrolls for small viewports. No core models use Flutter UI types.

`ProjectTree` displays scanned lib/test paths, including generated/unreadable files
and available empty scope folders. Directories sort before files, then by stable
path. Branches initially expand and can be collapsed. Selection changes reveal
ancestor folders and scroll the selected row into view. Rows are lazily built,
long labels ellipsize with full-path tooltips, and deep indentation is capped.
A new snapshot resets directory collapse state.

`FileInspectorPanel` uses the existing `GraphQueries.inspect` result, showing
filename, path, declarations, incoming connections, import/imported-by/line counts
and file diagnostics. Unreadable line counts display as unavailable. Generated
and read states are explicit. Resolved local dependency and incoming links invoke
the same controller selection callback; external/unresolved/out-of-scope/invalid
URIs are labelled and cannot navigate. Conditional branch metadata is shown.
Inspector scroll resets on file change; no selection shows an explicit prompt.

The map remains a placeholder. No graph rendering, search/filter/focus controls,
recent projects, editing or filesystem watching are added in this stage.
