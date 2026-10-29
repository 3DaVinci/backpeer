import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Пароль для агента бэкапа (метод `unlock`, ADR-010): по умолчанию ключ
/// сохраняется в хранилище ключей системы.
class UnlockDialog extends StatefulWidget {
  const new({required this.agent, super.key});

  final BackgroundProcess agent;

  /// Показывает диалог; `true` — ключи открыты.
  static Future<bool> show(BuildContext context, BackgroundProcess agent) =>
      showDialog<bool>(
        context: context,
        builder: (_) => UnlockDialog(agent: agent),
      ).then((v) => v ?? false);

  @override
  State<UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<UnlockDialog> {
  final _password = TextEditingController();
  var _remember = true;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
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
      final result = await widget.agent.call(
        'unlock',
        {'password': _password.text, 'remember': _remember},
        // Argon2id и запрос к хранилищу ключей.
        const Duration(minutes: 2),
      );
      if (!mounted) return;
      if (_remember && result['remembered'] != true) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.notRemembered)));
      }
      Navigator.of(context).pop(true);
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == 'wrong_password'
            ? l10n.wrongPassword
            : l10n.failed(e.message);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.unlockTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.unlockBody),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l10n.password,
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            CheckboxListTile(
              value: _remember,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.rememberKeys),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _remember = v ?? true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.unlock),
        ),
      ],
    );
  }
}
