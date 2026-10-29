import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/account/account_widgets.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Настройки учётной записи (задача 5.2.3): сведения, смена пароля,
/// фраза по паролю, копия ключа на координаторе, устройства и отзыв.
class AccountSettings extends StatefulWidget {
  const new({super.key});

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  BackgroundProcess? _agent;
  Map<String, Object?>? _info;
  List<Map<String, Object?>>? _devices;
  String? _devicesError;
  var _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final agent = AppScope.of(context).agent;
    if (!identical(agent, _agent)) {
      _agent?.removeListener(_onAgent);
      _agent = agent..addListener(_onAgent);
      _onAgent();
    }
  }

  @override
  void dispose() {
    _agent?.removeListener(_onAgent);
    super.dispose();
  }

  void _onAgent() {
    if (_info == null && !_loading && _agent?.state == LinkState.connected) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final agent = _agent!;
    setState(() => _loading = true);
    try {
      final info = await agent.call('account.info');
      if (!mounted) return;
      setState(() => _info = info);
      if (info['coordinator'] != null) await _loadDevices();
    } on ControlException {
      // Связь пропала — загрузим, когда вернётся.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDevices() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await _agent!.call(
        'account.devices',
        const {},
        accountTimeout,
      );
      if (!mounted) return;
      setState(() {
        _devices = [
          for (final d in result['devices']! as List<Object?>)
            d! as Map<String, Object?>,
        ]..sort((a, b) => '${a['addedAt']}'.compareTo('${b['addedAt']}'));
        _devicesError = null;
      });
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() => _devicesError = accountError(l10n, e));
    }
  }

  Future<void> _revoke(Map<String, Object?> device) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final id = device['deviceId']! as String;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.revokeTitle),
        content: SizedBox(width: 420, child: Text(l10n.revokeBody(_short(id)))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.revoke),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await _agent!.call('account.revoke', {'device': id}, accountTimeout);
      messenger.showSnackBar(SnackBar(content: Text(l10n.revoked)));
      await _loadDevices();
    } on ControlException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(accountError(l10n, e))));
    }
  }

  Future<void> _keyCopy(bool enabled) async {
    final l10n = AppLocalizations.of(context);
    final done = await PasswordActionDialog.show(
      context,
      title: enabled ? l10n.keyCopyEnableTitle : l10n.keyCopyDisableTitle,
      body: enabled ? l10n.keyCopyOnHint : l10n.keyCopyOffWarning,
      action: enabled ? l10n.enable : l10n.disable,
      run: (password) => _agent!.call('account.key_copy', {
        'password': password,
        'enabled': enabled,
      }, accountTimeout),
    );
    if (done != null) {
      setState(() => _info = {...?_info, 'keyCopy': enabled});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final info = _info;
    final connected = _agent?.state == LinkState.connected;
    if (info == null || info['configured'] != true) {
      return Section(
        title: l10n.accountSection,
        children: [
          if (_loading)
            const LinearProgressIndicator()
          else
            Text(l10n.notConfigured),
        ],
      );
    }
    final server = info['coordinator'] as String?;
    final keyCopy = info['keyCopy'] as bool?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: l10n.accountSection,
          children: [
            if (info['login'] case final String login)
              Fact(l10n.loginName, login),
            Fact(l10n.serverAddress, server ?? l10n.serverNone),
            Fact(l10n.thisDevice, _short(info['deviceId']! as String)),
            if (server != null)
              Fact(l10n.newDeviceSignIn, switch (keyCopy) {
                true => l10n.signInByPasswordOrPhrase,
                false => l10n.signInByPhraseOnly,
                null => l10n.unknown,
              }),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: connected
                      ? () => ChangePasswordDialog.show(context, _agent!)
                      : null,
                  icon: const Icon(Icons.password),
                  label: Text(l10n.changePassword),
                ),
                if (info['hasPhrase'] == true)
                  OutlinedButton.icon(
                    onPressed: connected
                        ? () => ShowPhraseDialog.show(context, _agent!)
                        : null,
                    icon: const Icon(Icons.key_outlined),
                    label: Text(l10n.showPhrase),
                  ),
              ],
            ),
            if (server != null) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('keyCopySwitch'),
                contentPadding: EdgeInsets.zero,
                value: keyCopy ?? false,
                title: Text(l10n.keyCopySwitch),
                subtitle: Text(
                  keyCopy ?? false ? l10n.keyCopyOnHint : l10n.keyCopyOffHint,
                ),
                onChanged: connected ? _keyCopy : null,
              ),
            ],
          ],
        ),
        if (server != null) ...[
          const SizedBox(height: 16),
          Section(
            title: l10n.devicesSection,
            trailing: IconButton(
              tooltip: l10n.refresh,
              onPressed: connected ? _loadDevices : null,
              icon: const Icon(Icons.refresh),
            ),
            children: [
              if (_devicesError case final error?) Text(error),
              if (_devices == null && _devicesError == null)
                const LinearProgressIndicator(),
              for (final d in _devices ?? const <Map<String, Object?>>[])
                _DeviceTile(
                  device: d,
                  onRevoke:
                      connected &&
                          d['current'] != true &&
                          d['revokedAt'] == null
                      ? () => _revoke(d)
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String _short(String id) => id.length > 16 ? '${id.substring(0, 16)}…' : id;

class _DeviceTile extends StatelessWidget {
  const new({required this.device, required this.onRevoke});

  final Map<String, Object?> device;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final revoked = device['revokedAt'];
    final current = device['current'] == true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        revoked != null ? Icons.block : Icons.computer,
        color: revoked != null ? Theme.of(context).disabledColor : null,
      ),
      title: Text(
        current
            ? l10n.deviceCurrent(_short(device['deviceId']! as String))
            : _short(device['deviceId']! as String),
      ),
      subtitle: Text(
        revoked != null
            ? l10n.deviceRevokedAt(formatDateTime(l10n, revoked) ?? '')
            : l10n.deviceAddedAt(formatDateTime(l10n, device['addedAt']) ?? ''),
      ),
      trailing: current || revoked != null
          ? null
          : TextButton(onPressed: onRevoke, child: Text(l10n.revoke)),
    );
  }
}

/// Действие по паролю: диалог с полем пароля, ошибки — под полем.
class PasswordActionDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.body,
    required this.action,
    required this.run,
    super.key,
  });

  final String title;
  final String body;
  final String action;
  final Future<Map<String, Object?>> Function(String password) run;

  /// Результат [run] или `null`, если отменено.
  static Future<Map<String, Object?>?> show(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    required Future<Map<String, Object?>> Function(String password) run,
  }) => showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => PasswordActionDialog(
      title: title,
      body: body,
      action: action,
      run: run,
    ),
  );

  @override
  State<PasswordActionDialog> createState() => _PasswordActionDialogState();
}

class _PasswordActionDialogState extends State<PasswordActionDialog> {
  final _password = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.run(_password.text);
      if (mounted) Navigator.of(context).pop(result);
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = accountError(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.body),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l10n.password,
                errorText: _error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Фраза восстановления снова — после ввода пароля.
abstract final class ShowPhraseDialog {
  static Future<void> show(
    BuildContext context,
    BackgroundProcess agent,
  ) async {
    final l10n = AppLocalizations.of(context);
    final result = await PasswordActionDialog.show(
      context,
      title: l10n.showPhrase,
      body: l10n.showPhraseBody,
      action: l10n.show,
      run: (password) =>
          agent.call('account.phrase', {'password': password}, accountTimeout),
    );
    if (result == null || !context.mounted) return;
    final words = (result['words']! as List<Object?>).cast<String>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.phraseTitle),
        content: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhraseGrid(words: words),
              const SizedBox(height: 16),
              NoticeCard(
                title: l10n.phraseTipsTitle,
                body: l10n.phraseTips,
                icon: Icons.edit_note,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}

/// Смена пароля: текущий и новый с оценкой стойкости. Копия ключа на
/// координаторе тоже переходит под новый пароль; ключи агента для
/// фоновой работы не меняются (ADR-010).
class ChangePasswordDialog extends StatefulWidget {
  const new({required this.agent, super.key});

  final BackgroundProcess agent;

  static Future<void> show(BuildContext context, BackgroundProcess agent) =>
      showDialog<void>(
        context: context,
        builder: (_) => ChangePasswordDialog(agent: agent),
      );

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _old = TextEditingController();
  String? _new;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.agent.call('account.passwd', {
        'password': _old.text,
        'newPassword': _new,
        'acceptWeak': true,
      }, accountTimeout);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result['keyCopyUnknown'] == true
                ? l10n.passwordChangedKeyCopyUnknown
                : result['keyCopyUpdated'] == true
                ? l10n.passwordChangedEverywhere
                : l10n.passwordChanged,
          ),
        ),
      );
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = accountError(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.changePassword),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('currentPassword'),
                controller: _old,
                obscureText: true,
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(labelText: l10n.currentPassword),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              NewPasswordFields(
                enabled: !_busy,
                onChanged: (p) => setState(() => _new = p),
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy || _new == null || _old.text.isEmpty
              ? null
              : _submit,
          child: Text(l10n.changePassword),
        ),
      ],
    );
  }
}
