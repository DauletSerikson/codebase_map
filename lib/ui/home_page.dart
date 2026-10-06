import 'package:flutter/material.dart';

import '../app/project_controller.dart';
import 'project_workspace.dart';
import '../core/file_system/project_scan.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});
  final ProjectController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late ProjectController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ProjectController();
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? ProjectController();
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final state = _controller.state;
      return Scaffold(
        appBar: AppBar(title: const Text('Codebase Map')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.snapshot == null) ...[
                    Text(
                      'Understand your project.',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: state.phase == OpenProjectPhase.selecting
                          ? null
                          : _controller.openProject,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open Project'),
                    ),
                  ),
                  if (state.phase == OpenProjectPhase.selecting ||
                      state.phase == OpenProjectPhase.analyzing) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(
                      state.phase == OpenProjectPhase.selecting
                          ? 'Choose a project folder…'
                          : 'Analyzing project…',
                    ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    _Diagnostics(diagnostics: state.diagnostics),
                  ],
                  if (state.snapshot != null) ...[
                    const SizedBox(height: 24),
                    ProjectWorkspace(
                      snapshot: state.snapshot!,
                      selectedFileId: state.selectedFileId,
                      onSelectFile: _controller.selectFile,
                    ),
                    _Diagnostics(diagnostics: state.snapshot!.diagnostics),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _Diagnostics extends StatelessWidget {
  const _Diagnostics({required this.diagnostics});
  final List<Diagnostic> diagnostics;

  @override
  Widget build(BuildContext context) {
    if (diagnostics.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text('${diagnostics.length} diagnostics'),
      children: [
        for (final diagnostic in diagnostics)
          ListTile(
            title: Text(diagnostic.message),
            subtitle: diagnostic.path == null
                ? null
                : Text(
                    '${diagnostic.path}${diagnostic.location == null ? '' : ':${diagnostic.location!.line}:${diagnostic.location!.column}'}',
                  ),
          ),
      ],
    );
  }
}
