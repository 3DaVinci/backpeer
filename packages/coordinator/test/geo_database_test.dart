// Справочник geoip из CSV DB-IP Lite: разбор, поиск по адресу, частные
// адреса и IPv6 мимо, сжатые файлы, ошибки в данных. Постгреса не нужно.

import 'dart:convert';
import 'dart:io';

import 'package:coordinator/src/geo/geo_database.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('geoip-test');
  });

  tearDown(() => dir.delete(recursive: true));

  Future<GeoDatabase?> open(
    List<String> names,
    String content, {
    bool compressed = false,
  }) async {
    for (final name in names) {
      final file = File('${dir.path}/$name');
      if (file.existsSync()) continue;
      final bytes = compressed
          ? gzip.encode(utf8.encode(content))
          : utf8.encode(content);
      await file.writeAsBytes(bytes);
    }
    return await GeoDatabase.open(dir.path);
  }

  test('город, страна и координаты по адресу', () async {
    final db = await open(
      ['dbip-city-lite-2026-11.csv'],
      '''
1.0.0.0,1.0.0.255,AU,Australia,Queensland,Brisbane,-27.4679,153.0281
2.0.0.0,2.0.0.255,DE,Germany,Berlin,Berlin,52.5244,13.4105
''',
    );
    expect(db, isNotNull);
    expect(db!.ranges, 2);
    final brisbane = db.lookup('1.0.0.7')!;
    expect(brisbane.country, 'AU');
    expect(brisbane.city, 'Brisbane');
    expect(brisbane.latitude, closeTo(-27.4679, 1e-9));
    expect(brisbane.longitude, closeTo(153.0281, 1e-9));
    expect(db.lookup('2.0.0.255')!.city, 'Berlin');
  });

  test('адрес вне диапазонов и частные адреса — без места', () async {
    final db = await open(
      ['dbip-city-lite.csv'],
      '''
1.0.0.0,1.0.0.255,AU,Australia,Queensland,Brisbane,-27.4679,153.0281
''',
    );
    expect(db!.lookup('9.9.9.9'), isNull);
    expect(db.lookup('10.0.0.1'), isNull);
    expect(db.lookup('192.168.1.1'), isNull);
    expect(db.lookup('127.0.0.1'), isNull);
    expect(db.lookup('2001:4860::1'), isNull);
    expect(db.lookup('не адрес'), isNull);
    expect(db.lookup('::ffff:10.0.0.1'), isNull);
  });

  test('сжатый файл читается так же', () async {
    final db = await open(
      ['dbip-country-lite.csv.gz'],
      '''
1.0.0.0,1.0.0.255,AU,Australia
''',
      compressed: true,
    );
    expect(db!.lookup('1.0.0.1')!.country, 'AU');
  });

  test('только страна: город и координаты неизвестны', () async {
    final db = await open(
      ['dbip-country-lite.csv'],
      '''
1.0.0.0,1.0.0.255,AU,Australia
''',
    );
    final place = db!.lookup('1.0.0.1')!;
    expect(place.country, 'AU');
    expect(place.city, isNull);
    expect(place.latitude, isNull);
  });

  test('городской справочник важнее странового', () async {
    final db = await open(
      ['dbip-country-lite.csv', 'dbip-city-lite.csv'],
      '''
1.0.0.0,1.0.0.255,AU,Australia,Queensland,Brisbane,-27.4679,153.0281
''',
    );
    expect(db!.source, endsWith('dbip-city-lite.csv'));
    expect(db.lookup('1.0.0.1')!.city, 'Brisbane');
  });

  test('запятая в названии города в кавычках', () async {
    final db = await open(
      ['dbip-city-lite.csv'],
      '''
8.0.0.0,8.0.0.255,US,United States,District of Columbia,"Washington, D.C.",38.8951,-77.0364
''',
    );
    expect(db!.lookup('8.0.0.1')!.city, 'Washington, D.C.');
  });

  test('строка заголовка пропускается', () async {
    final db = await open(
      ['dbip-city-lite.csv'],
      '''
range_start,range_end,country_code,country_name,region,city,latitude,longitude
1.0.0.0,1.0.0.255,AU,Australia,Queensland,Brisbane,-27.4679,153.0281
''',
    );
    expect(db!.ranges, 1);
  });

  test('пустая папка — геоданные выключены', () async {
    expect(await GeoDatabase.open(dir.path), isNull);
  });

  test('папки нет — ошибка настроек', () async {
    expect(
      () => GeoDatabase.open('${dir.path}/нет'),
      throwsA(isA<GeoDatabaseException>()),
    );
  });

  test('диапазоны не по возрастанию — ошибка', () async {
    expect(
      () => open(
        ['dbip-city-lite.csv'],
        '''
3.0.0.0,3.0.0.255,AU,Australia,,,-27.4679,153.0281
2.0.0.0,2.0.0.255,DE,Germany,,,52.5244,13.4105
''',
      ),
      throwsA(isA<GeoDatabaseException>()),
    );
  });

  test('битый код страны и плохой адрес — ошибки', () async {
    expect(
      () => open(
        ['dbip-city-lite.csv'],
        '''
1.0.0.0,1.0.0.255,RUS,Russia,,,-27.4679,153.0281
''',
      ),
      throwsA(isA<GeoDatabaseException>()),
    );
    dir
      ..deleteSync(recursive: true)
      ..createSync();
    expect(
      () => open(
        ['dbip-city-lite.csv'],
        '''
1.0.0.999,1.0.0.255,AU,Australia,,,-27.4679,153.0281
''',
      ),
      throwsA(isA<GeoDatabaseException>()),
    );
  });
}
