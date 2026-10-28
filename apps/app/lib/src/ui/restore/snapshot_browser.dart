import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/restore/versions_dialog.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Путь в исходном виде для `restore`: корень бэкапа и имена внутри
/// (`/home/u/docs` + `sub`, `a.txt` → `/home/u/docs/sub/a.txt`).
String sourcePath(List<String> path) {
  final root = path.first;
  final rest = path.skip(1).join('/');
  if (rest.isEmpty) return root;
  return root.endsWith('/') || root.endsWith(r'\')
      ? '$root$rest'
      : '$root/$rest';
}

/// Восстановить [paths] (пусто — весь снимок) из снимка [snapshot].
typedef RestoreRequest = void Function(
  String snapshot,
  List<List<String>> paths,
);

/// Дерево файлов снимка (задача 5.4.1): каталог читается, только когда
/// его открыли, и постранично (метод агента `tree` с `offset` и `limit`) —
/// снимок с миллионом файлов открывается без зависания. Поиск по имени —
/// метод `search`, версии файла — `versions`. Отмеченные файлы и папки
/// восстанавливаются вместе.
class SnapshotBrowser extends StatefulWidget {
  const new({
    required this.agent,
    required this.snapshot,
    required this.onClose,
    required this.onRestore,
    super.key,
  });

  final BackgroundProcess agent;

  /// Элемент ответа `snapshots`.
  final Map<String, Object?> snapshot;
  final VoidCallback onClose;
  final RestoreRequest onRestore;

  /// Сколько строк каталога агент отдаёт за раз.
  static const pageSize = 500;

  @override
  State<SnapshotBrowser> createState() => _SnapshotBrowserState();
}

class _SnapshotBrowserState extends State<SnapshotBrowser> {
  var _path = <String>[];
  final _pages = <int, List<Map<String, Object?>>>{};
  final _loading = <int>{};
  int? _total;
  String? _error;

  /// Ответы для прежнего каталога после перехода не нужны.
  var _generation = 0;

  /// Отмеченное: путь в исходном виде → имена от корня.
  final _selected = <String, List<String>>{};

  final _query = TextEditingController();
  Map<String, Object?>? _found;
  var _searching = false;

  String get _id => widget.snapshot['id']! as String;

  @override
  void initState() {
    super.initState();
    _open(const []);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(List<String> path) {
    setState(() {
      _generation++;
      _path = path;
      _pages.clear();
      _loading.clear();
      _total = null;
      _error = null;
      _found = null;
    });
    unawaited(_loadPage(0));
  }

  Future<void> _loadPage(int page) async {
    if (_loading.contains(page) || _pages.containsKey(page)) return;
    _loading.add(page);
    final generation = _generation;
    try {
      final result = await widget.agent.call('tree', {
        'snapshot': _id,
        'path': _path,
        'offset': page * SnapshotBrowser.pageSize,
        'limit': SnapshotBrowser.pageSize,
      }, const Duration(minutes: 5));
      if (!mounted || generation != _generation) return;
      setState(() {
        _total = result['total']! as int;
        _pages[page] = [
          for (final e in result['entries']! as List<Object?>)
            e! as Map<String, Object?>,
        ];
      });
    } on ControlException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = e.message);
    } finally {
      if (generation == _generation) _loading.remove(page);
    }
  }

  /// Строка [index] каталога; страницы ещё нет — запрашивает её.
  Map<String, Object?>? _entry(int index) {
    final page = index ~/ SnapshotBrowser.pageSize;
    final rows = _pages[page];
    if (rows == null) {
      unawaited(_loadPage(page));
      return null;
    }
    final i = index % SnapshotBrowser.pageSize;
    return i < rows.length ? rows[i] : null;
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) {
      setState(() => _found = null);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await widget.agent.call('search', {
        'snapshot': _id,
        'query': query,
        'limit': 500,
      }, const Duration(minutes: 30));
      if (!mounted) return;
      setState(() => _found = result);
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _toggle(List<String> path, {required bool on}) {
    setState(() {
      if (on) {
        _selected[sourcePath(path)] = path;
      } else {
        _selected.remove(sourcePath(path));
      }
    });
  }

  Future<void> _versions(List<String> path) async {
    final snapshot = await showVersionsDialog(
      context,
      agent: widget.agent,
      path: path,
    );
    if (snapshot != null) widget.onRestore(snapshot, [path]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final found = _found;
    final matches = [
      for (final m in (found?['matches'] as List<Object?>?) ?? const [])
        m! as Map<String, Object?>,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.browserBack,
              onPressed: widget.onClose,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l10n.snapshotFrom(
                    formatDateTime(l10n, widget.snapshot['createdAt']) ?? '',
                    '${widget.snapshot['hostname'] ?? ''}',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('search'),
          controller: _query,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: l10n.searchHint,
            border: const OutlineInputBorder(),
            suffixIcon: found == null
                ? null
                : IconButton(
                    tooltip: l10n.searchClear,
                    onPressed: () {
                      _query.clear();
                      setState(() => _found = null);
                    },
                    icon: const Icon(Icons.clear),
                  ),
          ),
          onSubmitted: (_) => unawaited(_search()),
        ),
        const SizedBox(height: 8),
        if (found == null)
          _Breadcrumbs(path: _path, onOpen: _open)
        else
          Text(
            found['truncated'] == true
                ? l10n.searchTruncated(matches.length)
                : l10n.searchResults(matches.length),
          ),
        if (_searching) const LinearProgressIndicator(),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.failed(error),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: found != null
                ? (matches.isEmpty
                      ? Center(child: Text(l10n.searchNothing))
                      : ListView.builder(
                          itemCount: matches.length,
                          itemExtent: 64,
                          itemBuilder: (context, i) {
                            final m = matches[i];
                            final path = [
                              for (final n in m['path']! as List<Object?>)
                                n! as String,
                            ];
                            return _EntryTile(
                              entry: m,
                              location: sourcePath(path),
                              selected: _selected.containsKey(sourcePath(path)),
                              onSelect: ({required on}) =>
                                  _toggle(path, on: on),
                              onOpen: () => _open(path),
                              onVersions: () => _versions(path),
                            );
                          },
                        ))
                : switch (_total) {
                    null => const Center(child: CircularProgressIndicator()),
                    0 => Center(child: Text(l10n.folderEmpty)),
                    final total => ListView.builder(
                      key: ValueKey('tree-${_path.join('/')}'),
                      itemCount: total,
                      itemExtent: 56,
                      itemBuilder: (context, i) {
                        final entry = _entry(i);
                        if (entry == null) {
                          return ListTile(title: Text(l10n.loadingItem));
                        }
                        final path = [..._path, entry['name']! as String];
                        return _EntryTile(
                          entry: entry,
                          selected: _selected.containsKey(sourcePath(path)),
                          onSelect: ({required on}) => _toggle(path, on: on),
                          onOpen: () => _open(path),
                          onVersions: () => _versions(path),
                        );
                      },
                    ),
                  },
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: widget.agent.state == LinkState.connected
                  ? () => widget.onRestore(_id, _selected.values.toList())
                  : null,
              icon: const Icon(Icons.restore),
              label: Text(
                _selected.isEmpty ? l10n.restoreAll : l10n.restoreSelected,
              ),
            ),
            if (_selected.isNotEmpty) ...[
              Text(l10n.selectedCount(_selected.length)),
              TextButton(
                onPressed: () => setState(_selected.clear),
                child: Text(l10n.clearSelection),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// «Снимок › корень › папка»: переход на любой уровень выше.
class _Breadcrumbs extends StatelessWidget {
  const new({required this.path, required this.onOpen});

  final List<String> path;
  final void Function(List<String>) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: path.isEmpty ? null : () => onOpen(const []),
          child: Text(l10n.browserRoot),
        ),
        for (var i = 0; i < path.length; i++) ...[
          const Icon(Icons.chevron_right, size: 18),
          TextButton(
            onPressed: i == path.length - 1
                ? null
                : () => onOpen(path.sublist(0, i + 1)),
            child: Text(path[i]),
          ),
        ],
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const new({
    required this.entry,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onVersions,
    this.location,
  });

  final Map<String, Object?> entry;
  final bool selected;
  final void Function({required bool on}) onSelect;
  final VoidCallback onOpen;
  final VoidCallback onVersions;

  /// Где лежит найденное (поиск); `null` — строка каталога.
  final String? location;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = entry['name']! as String;
    final type = entry['type'];
    final directory = type == 'directory';
    final details = [
      if (!directory) formatSize(l10n, (entry['size'] ?? 0) as int),
      ?formatDateTime(l10n, entry['mtime']),
    ].join(' · ');
    return ListTile(
      key: ValueKey('entry-$name'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: selected,
            onChanged: (v) => onSelect(on: v ?? false),
            semanticLabel: name,
          ),
          Icon(switch (type) {
            'directory' => Icons.folder_outlined,
            'symlink' => Icons.link,
            _ => Icons.insert_drive_file_outlined,
          }),
        ],
      ),
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        location == null ? details : '$location\n$details',
        maxLines: location == null ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: directory ? onOpen : () => onSelect(on: !selected),
      trailing: directory
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: l10n.fileVersions,
              onPressed: onVersions,
              icon: const Icon(Icons.history),
            ),
    );
  }
}
