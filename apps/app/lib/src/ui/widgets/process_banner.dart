import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:flutter/material.dart';

/// Полоса над экраном, пока нет связи с фоновым процессом. Приложение
/// переподключается само; полоса исчезает, как только процесс ответит.
class ProcessBanner extends StatelessWidget {
  const new({required this.process, required this.name, super.key});

  final BackgroundProcess process;
  final String name;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: process,
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final scheme = Theme.of(context).colorScheme;
      final (icon, title) = switch (process.state) {
        LinkState.connected => (null, null),
        LinkState.connecting => (Icons.sync, l10n.linkConnecting(name)),
        LinkState.unavailable => (
          Icons.cloud_off_outlined,
          l10n.linkUnavailable(name),
        ),
      };
      if (title == null) return const SizedBox.shrink();
      return Semantics(
        liveRegion: true,
        child: Material(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: scheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        l10n.linkUnavailableHint,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
