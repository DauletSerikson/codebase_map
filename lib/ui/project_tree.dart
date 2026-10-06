import 'package:flutter/material.dart';

import '../core/analysis/analysis_snapshot.dart';

class _TreeEntry {
  _TreeEntry(this.path, this.depth, this.isDirectory);
  final String path;
  final int depth;
  final bool isDirectory;
  String get name => path.split('/').last;
}

class ProjectTree extends StatefulWidget {
  const ProjectTree({
    super.key,
    required this.snapshot,
    required this.selectedFileId,
    required this.onSelectFile,
  });
  final AnalysisSnapshot snapshot;
  final String? selectedFileId;
  final ValueChanged<String> onSelectFile;

  @override
  State<ProjectTree> createState() => _ProjectTreeState();
}

class _ProjectTreeState extends State<ProjectTree> {
  final _collapsed = <String>{};
  final _scroll = ScrollController();
  late List<_TreeEntry> _entries;

  @override
  void initState() {
    super.initState();
    _buildEntries();
    _revealSelection();
  }

  void _buildEntries() {
    final paths = <String, bool>{
      for (final scope in widget.snapshot.project!.sourceScopes)
        scope.name: true,
    };
    for (final id in widget.snapshot.files.keys) {
      paths[id] = false;
      final parts = id.split('/');
      for (var index = 1; index < parts.length; index++) {
        paths[parts.take(index).join('/')] = true;
      }
    }
    final children = <String, List<String>>{};
    for (final path in paths.keys) {
      final slash = path.lastIndexOf('/');
      final parent = slash < 0 ? '' : path.substring(0, slash);
      children.putIfAbsent(parent, () => []).add(path);
    }
    _entries = [];
    void visit(String parent, int depth) {
      final entries = children[parent] ?? [];
      entries.sort((a, b) {
        if (paths[a] != paths[b]) return paths[a]! ? -1 : 1;
        return a.compareTo(b);
      });
      for (final path in entries) {
        _entries.add(_TreeEntry(path, depth, paths[path]!));
        if (paths[path]!) visit(path, depth + 1);
      }
    }

    visit('', 0);
  }

  List<_TreeEntry> get _visible => _entries
      .where(
        (entry) =>
            !_collapsed.any((folder) => entry.path.startsWith('$folder/')),
      )
      .toList();

  void _revealSelection() {
    final id = widget.selectedFileId;
    if (id == null) return;
    _collapsed.removeWhere((folder) => id.startsWith('$folder/'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = _visible.indexWhere((entry) => entry.path == id);
      if (index >= 0) {
        final position = _scroll.position;
        final top = index * 48.0;
        if (top < position.pixels ||
            top + 48 > position.pixels + position.viewportDimension) {
          _scroll.jumpTo(top.clamp(0.0, position.maxScrollExtent));
        }
      }
    });
  }

  @override
  void didUpdateWidget(ProjectTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot)) {
      _collapsed.clear();
      _buildEntries();
    }
    if (oldWidget.selectedFileId != widget.selectedFileId ||
        !identical(oldWidget.snapshot, widget.snapshot)) {
      _revealSelection();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visible;
    if (entries.isEmpty) {
      return const Center(child: Text('No source folders found.'));
    }
    return ListView.builder(
      controller: _scroll,
      itemExtent: 48,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final file = widget.snapshot.files[entry.path]?.file;
        return Tooltip(
          message: entry.path,
          child: ListTile(
            key: ValueKey('tree:${entry.path}'),
            contentPadding: EdgeInsets.only(
              left: 8 + (entry.depth * 14).clamp(0, 70).toDouble(),
              right: 8,
            ),
            selected: !entry.isDirectory && entry.path == widget.selectedFileId,
            leading: Icon(
              entry.isDirectory
                  ? (_collapsed.contains(entry.path)
                        ? Icons.folder
                        : Icons.folder_open)
                  : Icons.description_outlined,
              size: 20,
            ),
            title: Text(
              entry.isDirectory ? '${entry.name}/' : entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: file == null
                ? null
                : file.content == null
                ? const Icon(Icons.warning_amber, size: 16)
                : file.isGenerated
                ? const Icon(Icons.auto_awesome, size: 16)
                : null,
            onTap: entry.isDirectory
                ? () => setState(() {
                    if (!_collapsed.add(entry.path)) {
                      _collapsed.remove(entry.path);
                    }
                  })
                : () => widget.onSelectFile(entry.path),
          ),
        );
      },
    );
  }
}
