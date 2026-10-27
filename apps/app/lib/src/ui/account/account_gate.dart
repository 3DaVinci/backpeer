import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/account/welcome_flow.dart';
import 'package:app/src/ui/shell.dart';
import 'package:flutter/material.dart';

/// Без учётной записи на устройстве — первый запуск ([WelcomeFlow]), иначе
/// основные разделы ([Shell]). Решает агент (`configured` в `status`);
/// пока агента нет — разделы с полосой о связи.
class AccountGate extends StatefulWidget {
  const new({super.key});

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  /// Идёт первый запуск: он остаётся на экране и после того, как агент
  /// сообщит о новой учётной записи, — до конца сценария.
  var _welcome = false;

  @override
  Widget build(BuildContext context) {
    final agent = AppScope.of(context).agent;
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) {
        if (!_welcome &&
            agent.state == LinkState.connected &&
            agent.status?['configured'] == false) {
          _welcome = true;
        }
        return _welcome
            ? WelcomeFlow(onDone: () => setState(() => _welcome = false))
            : const Shell();
      },
    );
  }
}
