import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/screens/backup_screen.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:flutter/material.dart';

/// Расписание (задача 5.3.2): как часто, в какие часы, только от сети,
/// как часто проверять. Выполняет агент; ручной запуск и пауза — на
/// «Обзоре» и в «Текущем бэкапе».
class ScheduleSection extends StatelessWidget {
  const new({required this.agent, required this.settings, super.key});

  final BackgroundProcess agent;
  final Map<String, Object?> settings;

  static const _hour = 60;
  static const int _day = 24 * 60;
  static const int _week = 7 * 24 * 60;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final connected = agent.state == LinkState.connected;
    final interval = settings['intervalMinutes'] as int?;
    final hours = settings['hours'] as Map<String, Object?>?;
    final verify = settings['verifyIntervalHours'] as int?;
    final onAc = settings['onlyOnAcPower'] == true;
    void set(Map<String, Object?> patch) {
      if (connected) unawaited(changeSettings(context, patch));
    }

    final frequencies = <int?, String>{
      _hour: l10n.frequencyHourly,
      _day: l10n.frequencyDaily,
      _week: l10n.frequencyWeekly,
      null: l10n.manualOnly,
      // Значение из CLI или файла, которого нет в списке.
      if (interval != null && ![_hour, _day, _week].contains(interval))
        interval: l10n.everyMinutes(interval),
    };
    final checks = <int?, String>{
      24: l10n.frequencyDaily,
      24 * 7: l10n.frequencyWeekly,
      null: l10n.manualOnly,
      if (verify != null && ![24, 24 * 7].contains(verify))
        verify: l10n.everyMinutes(verify * 60),
    };
    Widget hourMenu(String label, String key, int value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: value,
          onChanged: connected
              ? (v) => set({
                  'hours': {...?hours, key: v},
                })
              : null,
          items: [
            for (var h = 0; h < 24; h++)
              DropdownMenuItem(value: h, child: Text(l10n.hourValue(h))),
          ],
        ),
      ],
    );

    return Section(
      title: l10n.schedule,
      children: [
        _Row(
          label: l10n.frequency,
          child: DropdownButton<int?>(
            value: interval,
            onChanged: connected ? (v) => set({'intervalMinutes': v}) : null,
            items: [
              for (final MapEntry(:key, :value) in frequencies.entries)
                DropdownMenuItem(value: key, child: Text(value)),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.onlyHours),
          value: hours != null,
          onChanged: connected
              ? (on) => set({
                  'hours': on ? {'from': 22, 'to': 7} : null,
                })
              : null,
        ),
        if (hours != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                hourMenu(l10n.hoursFrom, 'from', hours['from']! as int),
                hourMenu(l10n.hoursTo, 'to', hours['to']! as int),
              ],
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.onlyOnAc),
          subtitle: Text(l10n.onlyOnAcHint),
          value: onAc,
          onChanged: connected ? (on) => set({'onlyOnAcPower': on}) : null,
        ),
        _Row(
          label: l10n.verifySchedule,
          child: DropdownButton<int?>(
            value: verify,
            onChanged: connected
                ? (v) => set({'verifyIntervalHours': v})
                : null,
            items: [
              for (final MapEntry(:key, :value) in checks.entries)
                DropdownMenuItem(value: key, child: Text(value)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.scheduleNote,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const new({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 180, child: Text(label)),
      child,
    ],
  );
}
