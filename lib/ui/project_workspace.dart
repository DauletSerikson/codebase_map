import 'package:flutter/material.dart';

import '../core/analysis/analysis_snapshot.dart';
import '../core/dependency_graph/graph_queries.dart';
import '../core/file_system/project_scan.dart';
import 'file_inspector.dart';
import 'project_tree.dart';

class ProjectWorkspace extends StatelessWidget {
  const ProjectWorkspace({
    super.key,
    required this.snapshot,
    required this.selectedFileId,
    required this.onSelectFile,
  });
  final AnalysisSnapshot snapshot;
  final String? selectedFileId;
  final ValueChanged<String> onSelectFile;

  Widget _panel(String title, Widget child, double height) => Card(
    margin: const EdgeInsets.all(4),
    child: SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(title)),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final inspector = selectedFileId == null
        ? null
        : GraphQueries(snapshot).inspect(selectedFileId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          snapshot.project!.packageName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        SelectableText(snapshot.project!.root),
        const SizedBox(height: 8),
        Text(
          '${snapshot.project!.kind == ProjectKind.flutter ? 'Flutter' : 'Dart'} project · '
          '${snapshot.files.length} source files · ${snapshot.graph.edges.length} local dependencies',
        ),
        if (snapshot.files.isEmpty)
          const Text('No Dart source files found in lib/ or test/.'),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final height = wide ? 520.0 : 360.0;
            final tree = _panel(
              'PROJECT',
              ProjectTree(
                snapshot: snapshot,
                selectedFileId: selectedFileId,
                onSelectFile: onSelectFile,
              ),
              height,
            );
            final map = _panel(
              'DEPENDENCY MAP',
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Project analyzed.\nWorkspace visualization is coming next.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              wide ? height : 160,
            );
            final details = _panel(
              'INSPECTOR',
              FileInspectorPanel(
                key: ValueKey(selectedFileId),
                inspector: inspector,
                onSelectFile: onSelectFile,
              ),
              height,
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [tree, map, details],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: tree),
                Expanded(flex: 4, child: map),
                Expanded(flex: 4, child: details),
              ],
            );
          },
        ),
      ],
    );
  }
}
