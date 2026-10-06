import 'package:flutter/material.dart';

import '../core/dependency_graph/dependency.dart';
import '../core/dependency_graph/graph_queries.dart';

class FileInspectorPanel extends StatelessWidget {
  const FileInspectorPanel({
    super.key,
    required this.inspector,
    required this.onSelectFile,
  });
  final FileInspector? inspector;
  final ValueChanged<String> onSelectFile;

  String _status(ResolutionStatus status) => switch (status) {
    ResolutionStatus.resolved => 'local',
    ResolutionStatus.sdk => 'Dart SDK',
    ResolutionStatus.externalPackage => 'external package',
    ResolutionStatus.outOfScope => 'outside scanned sources',
    ResolutionStatus.unresolved => 'unresolved',
    ResolutionStatus.invalidUri => 'invalid URI',
    ResolutionStatus.fileSystemError => 'filesystem error',
  };

  @override
  Widget build(BuildContext context) {
    final details = inspector;
    if (details == null) {
      return const Center(child: Text('Select a file to inspect.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          details.path.split('/').last,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text('PATH'),
        SelectableText(details.path, key: const ValueKey('inspector:path')),
        if (details.source.file.isGenerated) const Text('Generated file'),
        if (details.source.file.content == null)
          const Text('Source could not be read.'),
        const SizedBox(height: 16),
        const Text('STATISTICS'),
        Text('Imports: ${details.importsCount}'),
        Text('Imported by: ${details.importedByCount}'),
        Text('Lines: ${details.lineCount ?? 'unavailable'}'),
        const SizedBox(height: 16),
        const Text('DEPENDENCIES'),
        if (details.dependencies.isEmpty) const Text('No dependencies.'),
        for (var index = 0; index < details.dependencies.length; index++)
          _dependency(details.dependencies[index], index),
        const SizedBox(height: 16),
        const Text('USED BY'),
        if (details.usedBy.isEmpty) const Text('No incoming dependencies.'),
        for (var index = 0; index < details.usedBy.length; index++)
          ListTile(
            key: ValueKey('usedBy:$index'),
            contentPadding: EdgeInsets.zero,
            title: Text('← ${details.usedBy[index].sourceId}'),
            subtitle: Text(details.usedBy[index].type.name),
            onTap: () => onSelectFile(details.usedBy[index].sourceId),
          ),
        const SizedBox(height: 16),
        const Text('DIAGNOSTICS'),
        if (details.diagnostics.isEmpty) const Text('No file diagnostics.'),
        for (final diagnostic in details.diagnostics)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(diagnostic.message),
            subtitle: diagnostic.location == null
                ? null
                : Text(
                    'Line ${diagnostic.location!.line}, column ${diagnostic.location!.column}',
                  ),
          ),
      ],
    );
  }

  Widget _dependency(Dependency dependency, int index) => ListTile(
    key: ValueKey('dependency:$index'),
    contentPadding: EdgeInsets.zero,
    title: Text(
      '→ ${dependency.targetId ?? dependency.uri ?? '(invalid URI)'}',
    ),
    subtitle: Text(
      '${dependency.type.name} · ${_status(dependency.status)}'
      '${dependency.branch == null ? '' : ' · if ${dependency.branch!.variable}${dependency.branch!.value == null ? '' : ' == ${dependency.branch!.value}'}'}',
    ),
    onTap:
        dependency.status == ResolutionStatus.resolved &&
            dependency.targetId != null
        ? () => onSelectFile(dependency.targetId!)
        : null,
  );
}
