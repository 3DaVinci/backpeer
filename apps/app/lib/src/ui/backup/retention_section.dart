import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/screens/backup_screen.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Политика хранения снимков (задача 5.3.5): сколько последних,
/// почасовых, дневных, недельных и месячных хранить, или все. Хранится в
/// `config.json` (общая с `cli config --keep-…`), агент применяет её после
/// каждого бэкапа.
class RetentionSection extends StatefulWidget {
  const new({required this.agent, required this.settings, super.key});

  final BackgroundProcess agent;
  final Map<String, Object?> settings;

  @override
  State<RetentionSection> createState() => _RetentionSectionState();
}

class _RetentionSectionState extends State<RetentionSection> {
  static const _fields = ['last', 'hourly', 'daily', 'weekly', 'monthly'];

  /// Как у `RetentionPolicy.defaults` в `core`.
  static const _defaults = {
    'last': 1,
    'hourly': 24,
    'daily': 7,
    'weekly': 4,
    'monthly': 12,
  };

  final Map<String, TextEditingController> _controllers = {
    for (final f in _fields) f: TextEditingController(),
  };
  Map<String, Object?>? _shown;

  Map<String, Object?>? get _policy =>
      widget.settings['retention'] as Map<String, Object?>?;

  @override
  void initState() {
    super.initState();
    _fill();
    for (final c in _controllers.values) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void didUpdateWidget(RetentionSection old) {
    super.didUpdateWidget(old);
    if ('$_policy' != '$_shown') _fill();
  }

  void _fill() {
    _shown = _policy;
    for (final f in _fields) {
      _controllers[f]!.text = '${_policy?[f] ?? _defaults[f]}';
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, int>? get _entered {
    final out = <String, int>{};
    for (final f in _fields) {
      final v = int.tryParse(_controllers[f]!.text);
      if (v == null || v < (f == 'last' ? 1 : 0)) return null;
      out[f] = v;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final connected = widget.agent.state == LinkState.connected;
    final policy = _policy;
    final configured = widget.settings.containsKey('retention');
    final entered = _entered;
    final changed =
        entered != null &&
        policy != null &&
        _fields.any((f) => entered[f] != policy[f]);
    final labels = {
      'last': l10n.keepLast,
      'hourly': l10n.keepHourly,
      'daily': l10n.keepDaily,
      'weekly': l10n.keepWeekly,
      'monthly': l10n.keepMonthly,
    };
    return Section(
      title: l10n.retention,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.keepAll),
          value: configured && policy == null,
          onChanged: connected && configured
              ? (all) => changeSettings(context, {
                  'retention': all ? null : (entered ?? _defaults),
                })
              : null,
        ),
        if (policy != null) ...[
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final f in _fields)
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _controllers[f],
                    enabled: connected,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: labels[f]),
                  ),
                ),
            ],
          ),
          if (entered == null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.retentionInvalid,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: connected && changed
                ? () => changeSettings(context, {'retention': entered})
                : null,
            child: Text(l10n.save),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          l10n.retentionHint,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
