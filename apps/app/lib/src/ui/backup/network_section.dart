import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/screens/backup_screen.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:flutter/material.dart';

/// Пределы скорости на выбор для сети клиента, байт в секунду;
/// 0 — без предела. Меньше, чем у хранителя: домашний исходящий канал
/// часто 1–5 Мбит/с.
const List<int> networkSpeedChoices = [
  0,
  128 << 10,
  512 << 10,
  1 << 20,
  5 << 20,
  20 << 20,
];

/// Пределы скорости сети для бэкапа, проверки и восстановления на этом
/// компьютере (`config.json`: `uploadBytesPerSecond`,
/// `downloadBytesPerSecond`). Действуют на все задания агента, а не только
/// на открытое окно; у хранителя свои пределы — на экране «Хранитель».
class NetworkSection extends StatelessWidget {
  const new({required this.agent, required this.settings, super.key});

  final BackgroundProcess agent;
  final Map<String, Object?> settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final connected = agent.state == LinkState.connected;
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    int value(String key) => settings[key] as int? ?? 0;
    Widget speed(String label, String key) {
      final current = value(key);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 220, child: Text(label)),
            DropdownButton<int>(
              key: ValueKey('network-$key'),
              value: networkSpeedChoices.contains(current) ? current : 0,
              onChanged: connected
                  ? (v) => changeSettings(context, {key: v})
                  : null,
              items: [
                for (final v in networkSpeedChoices)
                  DropdownMenuItem(
                    value: v,
                    child: Text(
                      v == 0
                          ? l10n.speedUnlimited
                          : l10n.speedValue(formatSize(l10n, v)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Section(
      title: l10n.networkSection,
      children: [
        speed(l10n.networkUpload, 'uploadBytesPerSecond'),
        speed(l10n.networkDownload, 'downloadBytesPerSecond'),
        const SizedBox(height: 8),
        Text(l10n.networkLimitsHint, style: muted),
      ],
    );
  }
}
