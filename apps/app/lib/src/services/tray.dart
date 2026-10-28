import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Пункт меню значка: `id` — что сделать (`backup`, `pause`, `resume`,
/// `open`, `quit`); `-` — разделитель.
@immutable
final class TrayItem {
  const new(this.id, this.label, {this.enabled = true});

  const new separator() : id = '-', label = '', enabled = true;

  final String id;
  final String label;
  final bool enabled;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'enabled': enabled,
  };

  @override
  bool operator ==(Object other) =>
      other is TrayItem &&
      other.id == id &&
      other.label == label &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, label, enabled);
}

/// Значок в трее (задача 5.6.2): нативная часть показывает значок и меню,
/// приложение задаёт строку состояния и пункты. «Открыть окно» и «Выйти»
/// нативная часть выполняет сама, остальное приходит в [actions].
abstract interface class TrayHost {
  /// Значок показан и его есть кому отобразить; `false` — трея нет
  /// (GNOME без расширения AppIndicator, другая ОС): тогда закрытие окна
  /// закрывает приложение, как обычно.
  Future<bool> available();

  Future<void> setMenu(String status, List<TrayItem> items);

  Stream<String> get actions;
}

/// [TrayHost] через канал `fs/tray` к нативной части (`linux/runner/
/// tray.cc`). Где нативной части нет (macOS, Windows — пока), значка нет.
final class ChannelTrayHost implements TrayHost {
  new([this._channel = const MethodChannel('fs/tray')]) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        _actions.add(call.arguments as String);
      }
    });
  }

  final MethodChannel _channel;
  final _actions = StreamController<String>.broadcast();

  @override
  Stream<String> get actions => _actions.stream;

  @override
  Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> setMenu(String status, List<TrayItem> items) async {
    try {
      await _channel.invokeMethod<void>('setMenu', {
        'status': status,
        'items': [for (final i in items) i.toJson()],
      });
    } on MissingPluginException {
      // Значка нет.
    }
  }
}
