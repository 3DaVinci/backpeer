import 'dart:async';
import 'dart:math';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/ui/account/account_widgets.dart';
import 'package:core/core.dart' show LoginName;
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Шаги создания учётной записи.
enum _Step { name, password, phrase, check, done }

/// Создание учётной записи (задача 5.2.1): имя и режим копии ключа, пароль
/// с оценкой стойкости, 24 слова фразы с советами, проверка нескольких
/// слов. Нельзя продолжить, не подтвердив фразу; слабый пароль не
/// принимается (агент проверяет то же самое).
class CreateAccountFlow extends StatefulWidget {
  const new({
    required this.server,
    required this.onBack,
    required this.onDone,
    super.key,
  });

  /// `coordinator` для `account.create`; пусто — без координатора.
  final Map<String, Object?> server;
  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  State<CreateAccountFlow> createState() => _CreateAccountFlowState();
}

class _CreateAccountFlowState extends State<CreateAccountFlow> {
  _Step _step = _Step.name;
  final _login = TextEditingController();
  var _keyCopy = true;
  String? _password;
  List<String>? _words;
  var _written = false;
  late List<int> _positions;
  final _checks = <int, TextEditingController>{};
  var _busy = false;
  String? _error;
  String? _loginError;
  Map<String, Object?>? _created;

  bool get _withServer => widget.server.isNotEmpty;

  @override
  void dispose() {
    _login.dispose();
    for (final c in _checks.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _normalizedLogin => LoginName.normalize(_login.text.trim());

  Future<void> _loadPhrase() async {
    final agent = AppScope.of(context).agent;
    setState(() => _busy = true);
    try {
      final result = await agent.call('account.new_phrase');
      final words = (result['words']! as List<Object?>).cast<String>();
      final count = (result['confirm'] as int?) ?? 3;
      final random = Random.secure();
      final positions = <int>{};
      while (positions.length < count) {
        positions.add(random.nextInt(words.length));
      }
      if (!mounted) return;
      setState(() {
        _words = words;
        _written = false;
        _positions = positions.toList()..sort();
        for (final c in _checks.values) {
          c.dispose();
        }
        _checks
          ..clear()
          ..addEntries(
            _positions.map((p) => MapEntry(p, TextEditingController())),
          );
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

  bool get _checked =>
      _words != null &&
      _checks.entries.every(
        (e) => e.value.text.trim().toLowerCase() == _words![e.key],
      );

  Future<void> _create() async {
    final agent = AppScope.of(context).agent;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await agent.call('account.create', {
        ...widget.server,
        if (_withServer) 'login': _normalizedLogin,
        if (_withServer) 'keyCopy': _keyCopy,
        'password': _password,
        // Средний пароль пользователь уже подтвердил галочкой.
        'acceptWeak': true,
        'confirm': {
          for (final MapEntry(:key, :value) in _checks.entries)
            '${key + 1}': value.text.trim().toLowerCase(),
        },
      }, accountTimeout);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _created = result;
        _step = _Step.done;
      });
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        switch (e.code) {
          case 'login_taken':
            _loginError = l10n.errorLoginTaken;
            _step = _Step.name;
          case 'weak_password':
            _step = _Step.password;
            _password = null;
            _error = accountError(l10n, e);
          case 'phrase_not_confirmed':
            // Агент перезапущен и забыл фразу: нужна новая.
            _words = null;
            _step = _Step.phrase;
            _error = l10n.phraseExpired;
          default:
            _error = accountError(l10n, e);
        }
      });
      if (e.code == 'phrase_not_confirmed') await _loadPhrase();
    }
  }

  void _go(_Step step) {
    setState(() {
      // Поля пароля создаются заново — пароль вводится снова.
      if (step == _Step.password) _password = null;
      _step = step;
      _error = null;
    });
    if (step == _Step.phrase && _words == null) unawaited(_loadPhrase());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (title, body, back, next) = switch (_step) {
      _Step.name => (
        l10n.createTitle,
        _nameStep(l10n),
        widget.onBack,
        !_withServer || _normalizedLogin != null
            ? () => _go(_Step.password)
            : null,
      ),
      _Step.password => (
        l10n.createPasswordTitle,
        _passwordStep(l10n),
        () => _go(_Step.name),
        _password != null ? () => _go(_Step.phrase) : null,
      ),
      _Step.phrase => (
        l10n.phraseTitle,
        _phraseStep(l10n),
        () => _go(_Step.password),
        _written ? () => _go(_Step.check) : null,
      ),
      _Step.check => (
        l10n.checkTitle,
        _checkStep(l10n),
        () => _go(_Step.phrase),
        _checked && !_busy ? _create : null,
      ),
      _Step.done => (l10n.createdTitle, _doneStep(l10n), null, widget.onDone),
    };
    return ListView(
      padding: const EdgeInsets.all(32),
      shrinkWrap: true,
      children: [
        if (_step != _Step.done)
          Text(
            l10n.stepOf(_step.index + 1, _Step.values.length - 1),
            style: theme.textTheme.labelLarge,
          ),
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 16),
        body,
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
            if (back != null)
              TextButton(
                onPressed: _busy ? null : back,
                child: Text(l10n.back),
              ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : next,
              child: Text(switch (_step) {
                _Step.check => l10n.createAccount,
                _Step.done => _withServer ? l10n.next : l10n.toBackup,
                _ => l10n.next,
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _nameStep(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!_withServer)
        NoticeCard(title: l10n.serverNone, body: l10n.localModeHint)
      else ...[
        TextField(
          key: const ValueKey('login'),
          controller: _login,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.loginName,
            helperText: l10n.loginNameHint,
            helperMaxLines: 2,
            errorText:
                _loginError ??
                (_login.text.isNotEmpty && _normalizedLogin == null
                    ? l10n.loginNameInvalid
                    : null),
          ),
          onChanged: (_) => setState(() => _loginError = null),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.keyCopyQuestion,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        RadioGroup<bool>(
          groupValue: _keyCopy,
          onChanged: (v) => setState(() => _keyCopy = v ?? true),
          child: Column(
            children: [
              RadioListTile<bool>(
                key: const ValueKey('keyCopyOn'),
                value: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.keyCopyOn),
                subtitle: Text(l10n.keyCopyOnHint),
              ),
              RadioListTile<bool>(
                key: const ValueKey('keyCopyOff'),
                value: false,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.keyCopyOff),
                subtitle: Text(l10n.keyCopyOffHint),
              ),
            ],
          ),
        ),
        if (!_keyCopy) ...[
          const SizedBox(height: 8),
          NoticeCard(
            title: l10n.keyCopyOffWarningTitle,
            body: l10n.keyCopyOffWarning,
            icon: Icons.warning_amber_outlined,
            warning: true,
          ),
        ],
      ],
    ],
  );

  Widget _passwordStep(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.createPasswordBody),
      const SizedBox(height: 16),
      NewPasswordFields(
        userInputs: [?_normalizedLogin],
        onChanged: (p) => setState(() => _password = p),
      ),
    ],
  );

  Widget _phraseStep(AppLocalizations l10n) {
    final words = _words;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.phraseBody),
        const SizedBox(height: 16),
        if (words != null) PhraseGrid(words: words),
        const SizedBox(height: 16),
        NoticeCard(
          title: l10n.phraseTipsTitle,
          body: l10n.phraseTips,
          icon: Icons.edit_note,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('phraseWritten'),
          value: _written,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(l10n.phraseWritten),
          onChanged: words == null
              ? null
              : (v) => setState(() => _written = v ?? false),
        ),
      ],
    );
  }

  Widget _checkStep(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.checkBody),
      const SizedBox(height: 16),
      for (final MapEntry(:key, :value) in _checks.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            key: ValueKey('check${key + 1}'),
            controller: value,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.wordNumber(key + 1),
              errorText:
                  value.text.trim().isNotEmpty &&
                      value.text.trim().toLowerCase() != _words![key] &&
                      value.text.trim().length >= _words![key].length
                  ? l10n.wordWrong
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
    ],
  );

  Widget _doneStep(AppLocalizations l10n) {
    final created = _created ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.createdBody),
        if (created['remembered'] == false) ...[
          const SizedBox(height: 16),
          NoticeCard(title: l10n.keysRequired, body: l10n.notRemembered),
        ],
      ],
    );
  }
}
