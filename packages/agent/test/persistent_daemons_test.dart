// Постоянная копия программ (задача 5.7.3, 5.7.2): службы ОС должны
// запускать программы по пути, который не исчезнет. Linux AppImage
// монтируется во временную папку, пакет macOS запускают из `.dmg`,
// «Загрузок» (App Translocation) или переносят — путь внутрь пакета после
// этого не работает, а приложение показывает «служба запущена».

import 'dart:io';

import 'package:agent/agent.dart';
import 'package:test/test.dart';

void main() {
  test('запуск из AppImage — копия нужна', () {
    expect(PersistentDaemons.needed({'APPIMAGE': '/tmp/.mount_x/app'}), isTrue);
  });

  test('FS_DAEMONS_PERSISTENT переопределяет решение ОС', () {
    expect(PersistentDaemons.needed({'FS_DAEMONS_PERSISTENT': '0'}), isFalse);
    expect(PersistentDaemons.needed({'FS_DAEMONS_PERSISTENT': '1'}), isTrue);
  });

  test('macOS: копия нужна всегда — пакет может лежать на образе .dmg', () {
    expect(PersistentDaemons.needed({}), Platform.isMacOS);
  });

  test('папка копии: macOS — Application Support, остальные — .local/lib', () {
    final target = PersistentDaemons.forUser({'HOME': '/home/u'}).target.path;
    if (Platform.isMacOS) {
      expect(target, '/home/u/Library/Application Support/backpeer/daemons');
    } else {
      expect(target, '/home/u/.local/lib/backpeer/daemons');
    }
  });
}
