import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../core/analysis/analysis_snapshot.dart';
import '../core/analysis/project_analyzer.dart';
import '../core/file_system/project_scan.dart';

typedef DirectoryPicker = Future<String?> Function();
typedef ProjectAnalysis = Future<AnalysisSnapshot> Function(String root);

enum OpenProjectPhase { idle, selecting, analyzing, ready, failure }

class OpenProjectState {
  OpenProjectState({
    required this.phase,
    this.snapshot,
    this.selectedFileId,
    this.error,
    Iterable<Diagnostic> diagnostics = const [],
  }) : diagnostics = List.unmodifiable(diagnostics);

  final OpenProjectPhase phase;

  /// Last successfully recognized project, retained on cancel/failure/reopen.
  final AnalysisSnapshot? snapshot;
  final String? selectedFileId;
  final String? error;
  final List<Diagnostic> diagnostics;
}

/// Native selection stays on the UI isolate; pure-Dart analysis runs in a worker.
Future<AnalysisSnapshot> analyzeProjectInBackground(String root) =>
    Isolate.run(() => const ProjectAnalyzer().analyze(root));

Future<String?> _showDirectoryPicker() =>
    getDirectoryPath(confirmButtonText: 'Open Project');

class ProjectController extends ChangeNotifier {
  ProjectController({DirectoryPicker? pickDirectory, ProjectAnalysis? analyze})
    : _pickDirectory = pickDirectory ?? _showDirectoryPicker,
      _analyze = analyze ?? analyzeProjectInBackground;

  final DirectoryPicker _pickDirectory;
  final ProjectAnalysis _analyze;
  OpenProjectState _state = OpenProjectState(phase: OpenProjectPhase.idle);
  OpenProjectState get state => _state;
  int _request = 0;
  bool _disposed = false;

  void _set(OpenProjectState value, {bool preserveSelection = true}) {
    _state = OpenProjectState(
      phase: value.phase,
      snapshot: value.snapshot,
      error: value.error,
      diagnostics: value.diagnostics,
      selectedFileId:
          preserveSelection && identical(value.snapshot, _state.snapshot)
          ? _state.selectedFileId
          : value.selectedFileId,
    );
    notifyListeners();
  }

  void selectFile(String? fileId) {
    if (_disposed || fileId == _state.selectedFileId) return;
    if (fileId != null &&
        !(_state.snapshot?.files.containsKey(fileId) ?? false)) {
      return;
    }
    _set(
      OpenProjectState(
        phase: _state.phase,
        snapshot: _state.snapshot,
        error: _state.error,
        diagnostics: _state.diagnostics,
        selectedFileId: fileId,
      ),
      preserveSelection: false,
    );
  }

  Future<void> openProject() async {
    // A native modal picker must not be opened twice concurrently.
    if (_disposed || _state.phase == OpenProjectPhase.selecting) return;
    final request = ++_request;
    final previous = _state.snapshot;
    bool current() => !_disposed && request == _request;
    _set(
      OpenProjectState(phase: OpenProjectPhase.selecting, snapshot: previous),
    );
    try {
      final root = await _pickDirectory();
      if (!current()) return;
      if (root == null) {
        _set(
          OpenProjectState(
            phase: previous == null
                ? OpenProjectPhase.idle
                : OpenProjectPhase.ready,
            snapshot: previous,
          ),
        );
        return;
      }
      _set(
        OpenProjectState(phase: OpenProjectPhase.analyzing, snapshot: previous),
      );
      final snapshot = await _analyze(root);
      if (!current()) return;
      if (snapshot.project == null) {
        _set(
          OpenProjectState(
            phase: OpenProjectPhase.failure,
            snapshot: previous,
            error: 'Could not open this Dart/Flutter project.',
            diagnostics: snapshot.diagnostics,
          ),
        );
      } else {
        _set(
          OpenProjectState(phase: OpenProjectPhase.ready, snapshot: snapshot),
          preserveSelection: false,
        );
      }
    } catch (error) {
      if (!current()) return;
      _set(
        OpenProjectState(
          phase: OpenProjectPhase.failure,
          snapshot: previous,
          error: 'Could not open project: $error',
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
