import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/ui/account/create_account.dart';
import 'package:app/src/ui/account/sign_in.dart';
import 'package:app/src/ui/keeper/keeper_onboarding.dart';
import 'package:app/src/ui/widgets/process_banner.dart';
import 'package:flutter/material.dart';

/// Что пользователь делает на этом устройстве.
enum WelcomeChoice { create, login, recover }

/// Первый запуск — учётной записи на устройстве нет (задачи 5.2.1, 5.2.2):
/// создать новую, войти по паролю или восстановить по фразе. Остаётся на
/// экране, пока пользователь не закончит (после создания с сервером —
/// предложение стать хранителем, после входа — восстановить данные), даже
/// когда агент уже сообщил о новой учётной записи.
class WelcomeFlow extends StatefulWidget {
  const new({required this.onDone, super.key});

  final VoidCallback onDone;

  @override
  State<WelcomeFlow> createState() => _WelcomeFlowState();
}

class _WelcomeFlowState extends State<WelcomeFlow> {
  WelcomeChoice? _choice;

  /// Учётная запись создана — следующий шаг: роль хранителя.
  var _keeper = false;
  late final _server = TextEditingController(
    text: AppScope.of(context).coordinator,
  );

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  /// Параметры координатора для методов `account.*`: пусто — без него.
  Map<String, Object?> get _serverParams {
    final url = _server.text.trim();
    return url.isEmpty ? const {} : {'coordinator': url};
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agent = AppScope.of(context).agent;
    final back = _choice == null ? null : () => setState(() => _choice = null);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ProcessBanner(process: agent, name: l10n.processAgent),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: switch (_choice) {
                    _ when _keeper => KeeperOnboarding(onDone: widget.onDone),
                    null => _Choose(
                      server: _server,
                      onChoice: (c) => setState(() => _choice = c),
                    ),
                    WelcomeChoice.create => CreateAccountFlow(
                      server: _serverParams,
                      onBack: back!,
                      // Без сервера хранителю негде регистрироваться.
                      onDone: _serverParams.isEmpty
                          ? widget.onDone
                          : () => setState(() => _keeper = true),
                    ),
                    WelcomeChoice.login => SignInFlow(
                      server: _serverParams,
                      byPhrase: false,
                      onBack: back!,
                      onDone: widget.onDone,
                    ),
                    WelcomeChoice.recover => SignInFlow(
                      server: _serverParams,
                      byPhrase: true,
                      onBack: back!,
                      onDone: widget.onDone,
                    ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choose extends StatefulWidget {
  const new({required this.server, required this.onChoice});

  final TextEditingController server;
  final ValueChanged<WelcomeChoice> onChoice;

  @override
  State<_Choose> createState() => _ChooseState();
}

class _ChooseState extends State<_Choose> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final local = widget.server.text.trim().isEmpty;
    return ListView(
      padding: const EdgeInsets.all(32),
      shrinkWrap: true,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.welcomeTitle(l10n.appTitle),
            style: theme.textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.welcomeBody),
        const SizedBox(height: 24),
        _ChoiceCard(
          icon: Icons.person_add_alt_1_outlined,
          title: l10n.welcomeCreate,
          body: l10n.welcomeCreateHint,
          onTap: () => widget.onChoice(WelcomeChoice.create),
        ),
        _ChoiceCard(
          icon: Icons.login,
          title: l10n.welcomeLogin,
          body: l10n.welcomeLoginHint,
          onTap: local ? null : () => widget.onChoice(WelcomeChoice.login),
        ),
        _ChoiceCard(
          icon: Icons.key_outlined,
          title: l10n.welcomeRecover,
          body: l10n.welcomeRecoverHint,
          onTap: () => widget.onChoice(WelcomeChoice.recover),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(l10n.serverSection),
          subtitle: Text(local ? l10n.serverNone : widget.server.text.trim()),
          children: [
            TextField(
              key: const ValueKey('server'),
              controller: widget.server,
              decoration: InputDecoration(
                labelText: l10n.serverAddress,
                helperText: l10n.serverAddressHint,
                helperMaxLines: 3,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      enabled: onTap != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(icon, size: 32),
      title: Text(title),
      subtitle: Text(body),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
