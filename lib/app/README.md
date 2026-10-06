# Open Project Flow (Stage 5)

`ProjectController` owns immutable `OpenProjectState` and notifies Flutter UI.
Injected picker/analysis functions allow deterministic unit/widget tests without
native dialogs. The default picker uses `file_selector.getDirectoryPath`; the
default analysis runs the existing pure-Dart pipeline via `Isolate.run`.

States: idle → selecting → analyzing → ready/failure. Native picker cancellation
restores the last successful project (or idle). A failed open also retains the
last successful snapshot and exposes the failure and original diagnostics.
Recognized projects with syntax/filesystem/resolution diagnostics still open as
partial results. Empty projects are valid and have an explicit empty-source state.

Only one native dialog is allowed at a time. A new request during analysis
supersedes the old request from the point the newer picker opens. Old successes
and failures cannot update state, including when the newer picker is cancelled.
Workers already running may finish; their results are ignored. Disposal likewise
invalidates pending operations and prevents late notifications.

`HomePage` creates/disposes its own controller unless an external controller is
supplied. The workspace shows project identity, source/edge totals and
expandable diagnostics. Tree and Inspector are connected in Stage 6; map,
search/filter/focus UI and recent projects are reserved for later stages. No persistence or security-scoped
bookmarks are implemented.

macOS DebugProfile and Release entitlements allow user-selected read-only file
access. The signed macOS debug build was verified by selecting this repository
through the native dialog and completing background analysis in the sandbox.
Windows/Linux native runtime verification and release-build verification remain
for platform acceptance. No new core/analyzer dependency on Flutter was added.


## Shared file selection (Stage 6)

`OpenProjectState.selectedFileId` is the single selection for Tree and Inspector.
`ProjectController.selectFile(id)` validates against the current snapshot;
unknown IDs are ignored, null clears selection. Selection survives loading,
cancel and failure while the existing snapshot remains. Successful analysis
resets selection, even when reopening the same project. Selection changes do not
mutate/reanalyze the snapshot or invalidate an active opening request.
