import 'dart:async';
import 'dart:io';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/ui/account/account_widgets.dart';
import 'package:app/src/ui/format.dart';
import 'package:core/core.dart' show LoginName;
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Вход на новом устройстве (задача 5.2.2): по имени и паролю (нужна
/// копия ключа на координаторе) или по фразе восстановления с новым
/// паролем для этого устройства. Затем — последний снимок с
/// предупреждением о возможном откате (2.5.2) и «Восстановить всё».
class SignInFlow extends StatefulWidget {
  const new({
    required this.server,
    required this.byPhrase,
    required this.onBack,
    required this.onDone,
    super.key,
  });

  final Map<String, Object?> server;
  final bool byPhrase;
  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  State<SignInFlow> createState() => _SignInFlowState();
}

class _SignInFlowState extends State<SignInFlow> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _phrase = TextEditingController();
  String? _newPassword;
  var _busy = false;
  String? _error;
  Map<String, Object?>? _result;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _phrase.dispose();
    super.dispose();
  }

  int get _phraseWords => _phrase.text.trim().isEmpty
      ? 0
      : _phrase.text.trim().split(RegExp(r'\s+')).length;

  bool get _ready => widget.byPhrase
      ? _phraseWords == 24 && _newPassword != null
      : LoginName.normalize(_login.text.trim()) != null &&
            _password.text.isNotEmpty;

  Future<void> _submit() async {
    final agent = AppScope.of(context).agent;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = widget.byPhrase
          ? await agent.call('account.recover', {
              ...widget.server,
              'phrase': _phrase.text.trim(),
              'password': _newPassword,
              'acceptWeak': true,
            }, accountTimeout)
          : await agent.call('account.login', {
              ...widget.server,
              'login': LoginName.normalize(_login.text.trim()),
              'password': _password.text,
            }, accountTimeout);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
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
    if (_result case final result?) {
      return RestoreAllPage(signedIn: result, onDone: widget.onDone);
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      shrinkWrap: true,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.byPhrase ? l10n.welcomeRecover : l10n.welcomeLogin,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 16),
        if (widget.byPhrase) ...[
          Text(l10n.recoverBody),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('phrase'),
            controller: _phrase,
            enabled: !_busy,
            minLines: 3,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.phraseField,
              helperText: l10n.phraseFieldCount(_phraseWords),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(l10n.recoverPasswordBody),
          const SizedBox(height: 8),
          NewPasswordFields(
            enabled: !_busy,
            onChanged: (p) => setState(() => _newPassword = p),
          ),
        ] else ...[
          Text(l10n.loginBody),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('login'),
            controller: _login,
            enabled: !_busy,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.loginName),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('password'),
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(labelText: l10n.password),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _ready && !_busy ? _submit() : null,
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(l10n.signingIn),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 16),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            TextButton(
              onPressed: _busy ? null : widget.onBack,
              child: Text(l10n.back),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _ready && !_busy ? _submit : null,
              child: Text(widget.byPhrase ? l10n.recover : l10n.signIn),
            ),
          ],
        ),
      ],
    );
  }
}

/// После входа: последний снимок учётной записи, предупреждение о
/// возможном откате (новое устройство не знает, каким был последний
/// снимок; manifest.md, раздел 6) и восстановление всего в выбранную
/// папку — сценарий «новый компьютер — восстановить всё» без CLI.
class RestoreAllPage extends StatefulWidget {
  const new({required this.signedIn, required this.onDone, super.key});

  /// Ответ `account.login` или `account.recover`.
  final Map<String, Object?> signedIn;
  final VoidCallback onDone;

  @override
  State<RestoreAllPage> createState() => _RestoreAllPageState();
}

class _RestoreAllPageState extends State<RestoreAllPage> {
  List<Map<String, Object?>>? _snapshots;
  List<Object?> _warnings = const [];
  final _target = TextEditingController();
  var _busy = true;
  String? _error;
  var _started = false;

  /// Папка для восстановления диалогом ОС (5.4.2).
  Future<void> _pickTarget() async {
    final folder = await AppScope.of(context)
        .pickFolder(initialDirectory: _target.text);
    if (folder != null && mounted) setState(() => _target.text = folder);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Папка по умолчанию — «Восстановлено» в домашней, на языке интерфейса.
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    _target.text =
        '$home${Platform.pathSeparator}'
        '${AppLocalizations.of(context).restoredFolder}';
    unawaited(_load());
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final agent = AppScope.of(context).agent;
    try {
      final result = await agent.call(
        'snapshots',
        const {},
        const Duration(minutes: 2),
      );
      if (!mounted) return;
      final list =
          [
            for (final s in result['snapshots']! as List<Object?>)
              s! as Map<String, Object?>,
          ]..sort(
            (a, b) => (a['sequence']! as int).compareTo(b['sequence']! as int),
          );
      setState(() {
        _snapshots = list;
        _warnings = (result['warnings'] as List<Object?>?) ?? const [];
        _busy = false;
      });
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = accountError(AppLocalizations.of(context), e);
      });
    }
  }

  Future<void> _restore(Map<String, Object?> snapshot) async {
    final agent = AppScope.of(context).agent;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await agent.call('restore', {
        'snapshot': snapshot['id'],
        'target': _target.text.trim(),
        // Узлы могут быть недолго недоступны: ждать до часа.
        'waitMinutes': 60,
      });
      widget.onDone();
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
    final theme = Theme.of(context);
    final snapshots = _snapshots;
    final latest = snapshots == null || snapshots.isEmpty
        ? null
        : snapshots.last;
    final indexError = widget.signedIn['indexError'];
    return ListView(
      padding: const EdgeInsets.all(32),
      shrinkWrap: true,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.signedInTitle, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 16),
        if (indexError is String) ...[
          NoticeCard(
            title: l10n.indexNotRestored,
            body: indexError,
            icon: Icons.warning_amber_outlined,
          ),
          const SizedBox(height: 16),
        ],
        if (widget.signedIn['remembered'] == false) ...[
          NoticeCard(title: l10n.keysRequired, body: l10n.notRemembered),
          const SizedBox(height: 16),
        ],
        if (snapshots != null && latest == null) Text(l10n.noSnapshots),
        if (latest != null) ...[
          Text(l10n.latestSnapshot, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                l10n.snapshotFrom(
                  formatDateTime(l10n, latest['createdAt']) ?? '',
                  '${latest['hostname'] ?? ''}',
                ),
              ),
              subtitle: Text(
                '${(latest['paths']! as List<Object?>).join(', ')}\n'
                '${_summary(l10n, latest)}',
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 4),
          Text(l10n.snapshotsTotal(snapshots!.length)),
          const SizedBox(height: 16),
          NoticeCard(
            title: _warnings.isEmpty
                ? l10n.rollbackCheckTitle
                : l10n.rollbackWarningTitle,
            body: _warnings.isEmpty ? l10n.rollbackCheck : l10n.rollbackWarning,
            icon: Icons.warning_amber_outlined,
            warning: _warnings.isNotEmpty,
          ),
          const SizedBox(height: 24),
          Text(l10n.restoreAllTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.restoreAllBody),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('target'),
                  controller: _target,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: l10n.restoreTarget),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.chooseFolder,
                onPressed: _busy ? null : _pickTarget,
                icon: const Icon(Icons.folder_open),
              ),
            ],
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 16),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            TextButton(
              onPressed: _busy && snapshots != null ? null : widget.onDone,
              child: Text(latest == null ? l10n.done : l10n.restoreLater),
            ),
            const Spacer(),
            if (latest != null)
              FilledButton.icon(
                onPressed: _busy || !Directory(_target.text.trim()).isAbsolute
                    ? null
                    : () => _restore(latest),
                icon: const Icon(Icons.restore),
                label: Text(l10n.restoreAll),
              ),
          ],
        ),
      ],
    );
  }
}

String _summary(AppLocalizations l10n, Map<String, Object?> snapshot) =>
    l10n.snapshotSummary(
      l10n.filesCount(snapshot['files']! as int),
      formatSize(l10n, snapshot['bytes']! as int),
    );
