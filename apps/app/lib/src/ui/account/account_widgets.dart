import 'package:app/l10n/app_localizations.dart';
import 'package:core/core.dart'
    show PasswordHint, PasswordPolicy, PasswordProblem, PasswordVerdict;
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Ошибка метода `account.*` агента словами интерфейса; неизвестный код —
/// текст агента.
String accountError(AppLocalizations l10n, ControlException e) =>
    switch (e.code) {
      'wrong_password' => l10n.wrongPassword,
      'weak_password' => l10n.errorWeakPassword,
      'phrase_not_confirmed' => l10n.errorPhraseNotConfirmed,
      'bad_phrase' => l10n.errorBadPhrase,
      'login_taken' => l10n.errorLoginTaken,
      'unauthenticated' => l10n.errorUnauthenticated,
      'too_many_devices' => l10n.errorTooManyDevices,
      'current_device' => l10n.errorCurrentDevice,
      'no_phrase' => l10n.errorNoPhrase,
      'rate_limited' => l10n.errorRateLimited,
      'unavailable' => l10n.errorUnavailable,
      'exists' => l10n.errorExists,
      'keys_required' => l10n.keysRequired,
      _ => l10n.failed(e.message),
    };

/// Время на методы с Argon2id и запросами к координатору.
const accountTimeout = Duration(minutes: 3);

/// Новый пароль дважды с оценкой стойкости по `PasswordPolicy` (crypto.md,
/// раздел 4.3; задача 2.4.4): слабый не принимается, средний — только с
/// явным согласием. [onChanged] получает годный пароль или `null`.
class NewPasswordFields extends StatefulWidget {
  const new({
    required this.onChanged,
    this.userInputs = const [],
    this.enabled = true,
    this.label,
    super.key,
  });

  final ValueChanged<String?> onChanged;

  /// Что атакующий знает о пользователе (имя для входа).
  final List<String> userInputs;
  final bool enabled;
  final String? label;

  @override
  State<NewPasswordFields> createState() => _NewPasswordFieldsState();
}

class _NewPasswordFieldsState extends State<NewPasswordFields> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  var _acceptWeak = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    final password = _first.text;
    final verdict = password.isEmpty
        ? PasswordVerdict.rejected
        : PasswordPolicy.assess(
            password,
            userInputs: widget.userInputs,
          ).verdict;
    final ok =
        password == _second.text &&
        (verdict == PasswordVerdict.strong ||
            (verdict == PasswordVerdict.weak && _acceptWeak));
    widget.onChanged(ok ? password : null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final password = _first.text;
    final assessment = password.isEmpty
        ? null
        : PasswordPolicy.assess(password, userInputs: widget.userInputs);
    final mismatch = _second.text.isNotEmpty && _second.text != password;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('newPassword'),
          controller: _first,
          obscureText: true,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: widget.label ?? l10n.newPassword,
            helperText: l10n.passwordAdvice(PasswordPolicy.minLength),
            helperMaxLines: 2,
          ),
          onChanged: (_) {
            _acceptWeak = false;
            _changed();
          },
        ),
        if (assessment != null) ...[
          const SizedBox(height: 12),
          _Strength(verdict: assessment.verdict),
          for (final p in assessment.problems)
            _Note(problemText(l10n, p), error: true),
          for (final h in assessment.hints) _Note(hintText(l10n, h)),
          if (assessment.verdict == PasswordVerdict.weak)
            CheckboxListTile(
              key: const ValueKey('acceptWeak'),
              value: _acceptWeak,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.acceptWeakPassword),
              onChanged: widget.enabled
                  ? (v) {
                      _acceptWeak = v ?? false;
                      _changed();
                    }
                  : null,
            ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('repeatPassword'),
          controller: _second,
          obscureText: true,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: l10n.repeatPassword,
            errorText: mismatch ? l10n.passwordsDiffer : null,
          ),
          onChanged: (_) => _changed(),
        ),
      ],
    );
  }
}

String problemText(AppLocalizations l10n, PasswordProblem p) => switch (p) {
  PasswordProblem.tooShort => l10n.passwordTooShort(PasswordPolicy.minLength),
  PasswordProblem.forbiddenCharacter => l10n.passwordForbiddenCharacter,
  PasswordProblem.tooGuessable => l10n.passwordTooGuessable,
};

String hintText(AppLocalizations l10n, PasswordHint h) => switch (h) {
  PasswordHint.commonPassword => l10n.hintCommonPassword,
  PasswordHint.dictionaryWord => l10n.hintDictionaryWord,
  PasswordHint.name => l10n.hintName,
  PasswordHint.personalInfo => l10n.hintPersonalInfo,
  PasswordHint.otherLayout => l10n.hintOtherLayout,
  PasswordHint.substitution => l10n.hintSubstitution,
  PasswordHint.reversed => l10n.hintReversed,
  PasswordHint.keyboardPattern => l10n.hintKeyboardPattern,
  PasswordHint.repeat => l10n.hintRepeat,
  PasswordHint.sequence => l10n.hintSequence,
  PasswordHint.date => l10n.hintDate,
};

class _Strength extends StatelessWidget {
  const new({required this.verdict});

  final PasswordVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (value, color, label) = switch (verdict) {
      PasswordVerdict.rejected => (0.2, scheme.error, l10n.passwordRejected),
      PasswordVerdict.weak => (0.6, scheme.tertiary, l10n.passwordWeak),
      PasswordVerdict.strong => (1.0, scheme.primary, l10n.passwordStrong),
    };
    return Semantics(
      liveRegion: true,
      label: l10n.passwordStrength(label),
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: value,
              color: color,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Text(l10n.passwordStrength(label)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const new(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: error ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// 24 слова фразы восстановления с номерами, в четыре колонки.
class PhraseGrid extends StatelessWidget {
  const new({required this.words, super.key});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, word) in words.indexed)
            SizedBox(
              width: 150,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${i + 1}. ',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(
                      text: word,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                key: ValueKey('word${i + 1}'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Предупреждение или пояснение в рамке.
class NoticeCard extends StatelessWidget {
  const new({
    required this.title,
    required this.body,
    this.icon = Icons.info_outline,
    this.warning = false,
    super.key,
  });

  final String title;
  final String body;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = warning
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = warning
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;
    return Card(
      color: background,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: foreground),
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: TextStyle(color: foreground)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
