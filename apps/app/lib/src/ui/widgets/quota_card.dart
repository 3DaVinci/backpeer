import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:material_ui/material_ui.dart';

/// Квота и кредиты учётной записи (метод агента `quota`): сколько данных
/// сохранено, сколько даёт бесплатная бартерная квота за отданное место,
/// сколько добавляют кредиты и на сколько дней хватает баланса.
class QuotaCard extends StatefulWidget {
  const new({required this.agent, super.key});

  final BackgroundProcess agent;

  @override
  State<QuotaCard> createState() => _QuotaCardState();
}

class _QuotaCardState extends State<QuotaCard> {
  Map<String, Object?>? _quota;
  String? _error;
  var _noCoordinator = false;
  StreamSubscription<ControlEvent>? _events;
  var _wasConnected = false;

  @override
  void initState() {
    super.initState();
    _events = widget.agent.events.listen((e) {
      if (e.name == 'job_finished') unawaited(_load());
    });
    widget.agent.addListener(_onAgent);
    _onAgent();
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    widget.agent.removeListener(_onAgent);
    super.dispose();
  }

  void _onAgent() {
    final connected = widget.agent.state == LinkState.connected;
    if (connected && !_wasConnected) unawaited(_load());
    _wasConnected = connected;
  }

  Future<void> _load() async {
    try {
      final result = await widget.agent.call('quota');
      if (!mounted) return;
      setState(() {
        _quota = result;
        _error = null;
        _noCoordinator = false;
      });
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'no_coordinator' ? null : e.message;
        _noCoordinator = e.code == 'no_coordinator';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_noCoordinator) {
      return Section(
        title: l10n.quotaTitle,
        children: [Text(l10n.spaceNoCoordinator)],
      );
    }
    final q = _quota;
    final data = q?['dataBytes'] as int?;
    final barter = q?['barterBytes'] as int?;
    final max = q?['maxBytes'] as int?;
    final balance = q?['balanceMc'] as int?;
    final daily = q?['dailyCostMc'] as int?;
    final blocked = q?['blocked'] as bool? ?? false;
    final repair = q?['repairBytes'] as int?;
    final negative = balance != null && balance < 0;
    final days = balance != null && daily != null && daily > 0 && balance > 0
        ? balance ~/ daily
        : null;
    final loaded = data != null || barter != null || max != null;
    return Section(
      title: l10n.quotaTitle,
      trailing: IconButton(
        tooltip: l10n.refresh,
        onPressed: widget.agent.state == LinkState.connected ? _load : null,
        icon: const Icon(Icons.refresh),
      ),
      children: [
        if (_error case final error?) Text(l10n.failed(error)),
        if (!loaded && _error == null) Text(l10n.loadingItem),
        if (data != null) Fact(l10n.quotaData, formatSize(l10n, data)),
        if (barter != null) Fact(l10n.quotaFree, formatSize(l10n, barter)),
        if (max != null) Fact(l10n.quotaAvailable, formatSize(l10n, max)),
        if (balance != null) Fact(l10n.quotaCredits, '${_credits(balance)} CR'),
        if (days != null) Fact(l10n.quotaDays, formatCount(l10n, days)),
        if (repair != null && repair > 0)
          Fact(l10n.quotaRepair, formatSize(l10n, repair)),
        if (blocked) ...[
          const SizedBox(height: 8),
          Text(
            l10n.quotaBlocked,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ] else if (negative) ...[
          const SizedBox(height: 8),
          Text(
            l10n.quotaNegative,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (loaded) ...[
          const SizedBox(height: 8),
          Text(
            l10n.quotaHint,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  static String _credits(int micro) {
    final value = micro / 1000000;
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }
}
