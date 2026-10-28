import 'dart:ffi';
import 'dart:io';

import 'package:agent/src/desktop/gdbus.dart';
import 'package:ffi/ffi.dart';

/// Источник питания компьютера (задача 5.3.2: бэкап только от сети).
abstract interface class PowerSource {
  /// Для текущей ОС: Linux — UPower, macOS — `pmset`, Windows —
  /// `GetSystemPowerStatus` (5.6.3). `FS_AGENT_POWER=none` — не проверять.
  factory forPlatform([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    if (env['FS_AGENT_POWER'] == 'none') return const NoPowerSource();
    if (Platform.isLinux) return const UPowerSource();
    if (Platform.isMacOS) return const PmsetPowerSource();
    if (Platform.isWindows) return const WindowsPowerSource();
    return const NoPowerSource();
  }

  /// Для журнала: `upower`, `pmset`, `windows`, `none`.
  String get name;

  /// `true` — от батареи, `false` — от сети, `null` — неизвестно (агент
  /// считает, что от сети: настольный компьютер, нет UPower).
  Future<bool?> onBattery();
}

/// Питание неизвестно: ограничение «только от сети» не действует.
final class NoPowerSource implements PowerSource {
  const new();

  @override
  String get name => 'none';

  @override
  Future<bool?> onBattery() async => null;
}

/// Linux: свойство `OnBattery` службы UPower по системной шине. Нет UPower
/// — то же, что читает она сама: `/sys/class/power_supply`.
final class UPowerSource implements PowerSource {
  const new({this.sysfs = '/sys/class/power_supply'});

  final String sysfs;

  @override
  String get name => 'upower';

  @override
  Future<bool?> onBattery() async {
    final out = await gdbusCall(
      system: true,
      destination: 'org.freedesktop.UPower',
      objectPath: '/org/freedesktop/UPower',
      method: 'org.freedesktop.DBus.Properties.Get',
      args: [
        gvariantString('org.freedesktop.UPower'),
        gvariantString('OnBattery'),
      ],
    );
    if (out != null) {
      if (out.contains('true')) return true;
      if (out.contains('false')) return false;
    }
    return _fromSysfs();
  }

  /// Есть сеть (`Mains`, `USB` с `online` = 1) — от сети; есть только
  /// разряжающиеся батареи — от батареи; ничего нет — неизвестно.
  bool? _fromSysfs() {
    final List<FileSystemEntity> supplies;
    try {
      supplies = Directory(sysfs).listSync();
    } on FileSystemException {
      return null;
    }
    var battery = false;
    for (final dir in supplies) {
      String? read(String name) {
        try {
          return File('${dir.path}/$name').readAsStringSync().trim();
        } on FileSystemException {
          return null;
        }
      }

      switch (read('type')) {
        case 'Mains' || 'USB':
          if (read('online') == '1') return false;
        case 'Battery':
          if (read('scope') != 'Device' && read('status') == 'Discharging') {
            battery = true;
          }
      }
    }
    return battery ? true : null;
  }
}

/// macOS: `pmset -g batt` — первая строка «Now drawing from 'AC Power'»
/// или «'Battery Power'».
final class PmsetPowerSource implements PowerSource {
  const new();

  @override
  String get name => 'pmset';

  @override
  Future<bool?> onBattery() async {
    try {
      final result = await Process.run('pmset', ['-g', 'batt']);
      if (result.exitCode != 0) return null;
      return parsePmset('${result.stdout}');
    } on ProcessException {
      return null;
    }
  }

  static bool? parsePmset(String out) {
    if (out.contains("'Battery Power'")) return true;
    if (out.contains("'AC Power'")) return false;
    return null;
  }
}

/// Windows: `GetSystemPowerStatus` из kernel32, поле `ACLineStatus`: 0 —
/// от батареи, 1 — от сети, 255 — неизвестно.
final class WindowsPowerSource implements PowerSource {
  const new();

  @override
  String get name => 'windows';

  @override
  Future<bool?> onBattery() async {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final get = kernel32
          .lookupFunction<
            Int32 Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)
          >('GetSystemPowerStatus');
      // SYSTEM_POWER_STATUS: 4 байта флагов и два DWORD.
      final status = calloc<Uint8>(12);
      try {
        if (get(status) == 0) return null;
        return switch (status[0]) {
          0 => true,
          1 => false,
          _ => null,
        };
      } finally {
        calloc.free(status);
      }
    } on Object {
      return null;
    }
  }
}

/// Для тестов: питание задаёт тест.
final class FakePowerSource implements PowerSource {
  new({this.battery});

  bool? battery;

  @override
  String get name => 'fake';

  @override
  Future<bool?> onBattery() async => battery;
}
