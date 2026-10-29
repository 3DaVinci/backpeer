import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/screens/overview_screen.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:flutter/material.dart';

/// Здоровье данных (задача 5.3.4): «всё в порядке», «ремонтируется»,
/// «требует внимания» с причинами словами интерфейса, дата последней
/// проверки, проверка сейчас. Уведомления ОС шлёт сам агент — окно может
/// быть закрыто.
class HealthCard extends StatelessWidget {
  const new({required this.agent, super.key});

  final BackgroundProcess agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = agent.status;
    final health = status?['health'] as Map<String, Object?>?;
    final state = health?['state'];
    final reasons = [
      for (final r in (health?['reasons'] as List<Object?>?) ?? const [])
        r! as Map<String, Object?>,
    ];
    final verify = status?['lastVerify'] as Map<String, Object?>?;
    final (icon, color, title, hint) = switch (state) {
      'ok' => (
        Icons.verified_outlined,
        scheme.primary,
        l10n.healthOk,
        l10n.healthOkHint,
      ),
      'repairing' => (
        Icons.build_circle_outlined,
        scheme.tertiary,
        l10n.healthRepairing,
        l10n.healthRepairingHint,
      ),
      'attention' => (
        Icons.error_outline,
        scheme.error,
        l10n.healthAttention,
        null,
      ),
      _ => (
        Icons.help_outline,
        scheme.onSurfaceVariant,
        l10n.healthUnknown,
        l10n.healthUnknownHint,
      ),
    };
    final idle = agent.state == LinkState.connected && status?['job'] == null;
    return Section(
      title: l10n.healthTitle,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: color),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  r['attention'] == true
                      ? Icons.warning_amber
                      : Icons.info_outline,
                  size: 18,
                  color: r['attention'] == true
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(healthReason(l10n, r))),
              ],
            ),
          ),
        if (hint != null && reasons.every((r) => r['attention'] != true))
          Text(hint),
        const SizedBox(height: 8),
        Fact(
          l10n.lastVerify,
          verify == null
              ? l10n.never
              : '${formatDateTime(l10n, verify['finishedAt'])} — '
                    '${outcomeName(l10n, verify['outcome'])}',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: idle && status?['configured'] == true
              ? () => runAction(context, () => agent.call('verify'))
              : null,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(l10n.verifyNow),
        ),
      ],
    );
  }
}

/// Причина состояния здоровья словами интерфейса; неизвестный код — текст
/// агента.
String healthReason(AppLocalizations l10n, Map<String, Object?> reason) =>
    switch (reason['code']) {
      'backup_failed' => l10n.healthReasonBackupFailed,
      'backup_stale' => l10n.healthReasonBackupStale,
      'rollback_warning' => l10n.healthReasonRollbackWarning,
      'unrecoverable' => l10n.healthReasonUnrecoverable,
      'at_risk' => l10n.healthReasonAtRisk,
      'fragments_missing' => l10n.healthReasonFragmentsMissing,
      'verify_failed' => l10n.healthReasonVerifyFailed,
      'never_verified' => l10n.healthReasonNeverVerified,
      _ => '${reason['message'] ?? reason['code']}',
    };
