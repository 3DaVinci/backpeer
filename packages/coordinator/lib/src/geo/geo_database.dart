import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/nodes/node_address.dart';
import 'package:logging/logging.dart';

/// Геоданные узла по адресу, с которого он обращается к координатору.
///
/// Место хранителя — персональные данные (модель угроз, К-2): координатор
/// хранит только код страны, название города и координаты, а на сайт отдаёт
/// их сводкой по городам, без привязки к узлу.
final class GeoLocation {
  const new({required this.country, this.city, this.latitude, this.longitude});

  /// Код страны ISO 3166-1 alpha-2 в верхнем регистре.
  final String country;

  /// Город; `null` — справочник знает только страну.
  final String? city;

  /// Широта и долгота города в градусах; `null` — неизвестны.
  final double? latitude;
  final double? longitude;

  @override
  String toString() => city == null ? country : '$country, $city';
}

/// Справочник geoip из CSV-файлов DB-IP Lite (https://db-ip.com/db/).
///
/// Поддерживаются `dbip-city-lite-*.csv` (страна, город, координаты) и
/// `dbip-country-lite-*.csv` (только страна), в том числе сжатые `.csv.gz`.
/// Если в папке есть оба, берётся городской: он содержит и страну.
///
/// Данные DB-IP Lite распространяются по лицензии CC BY 4.0: на сайте
/// продукта нужна ссылка на db-ip.com (см. `docs/ops/coordinator.md`).
/// Файл читается один раз при запуске; при обновлении справочника
/// координатор перезапускают.
///
/// Адреса IPv6 не разбираются: в базе Lite они есть не всегда, и узел без
/// геоданных просто не попадает на карту.
final class GeoDatabase {
  new _(this._ranges, this._countries, this._cities, this.source);

  /// Предел числа диапазонов: 5 млн строк — около 120 МБ памяти. Больше —
  /// ошибка настроек, а не тихая нехватка памяти.
  static const maxRanges = 5000000;

  static final _log = Logger('geoip');

  final _Ranges _ranges;
  final List<String> _countries;
  final List<String> _cities;

  /// Файл, из которого загружен справочник (для журнала и `status`).
  final String source;

  /// Открывает справочник в папке [directory]. `null` — в папке нет
  /// подходящих файлов: геоданные выключены.
  ///
  /// Папки нет — ошибка, а не выключенная возможность: опечатку в
  /// настройках оператор должен видеть.
  static Future<GeoDatabase?> open(
    String directory, {
    DateTime Function()? clock,
  }) async {
    final now = clock ?? DateTime.now;
    final started = now();
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      throw GeoDatabaseException('папки справочника нет: $directory');
    }
    final files = <String>[];
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last.toLowerCase();
      if (name.endsWith('.csv') || name.endsWith('.csv.gz')) {
        files.add(entry.path);
      }
    }
    if (files.isEmpty) return null;
    files.sort();
    // Городской справочник важнее: в нём есть и страна.
    final city = files.where(_isCityFile).toList();
    final source = city.isNotEmpty ? city.first : files.first;
    final db = await _load(source);
    _log.info(
      LogEvent('geoip_loaded', {
        'source': source,
        'ranges': db.ranges,
        'countries': db._countries.length,
        'cities': db._cities.length,
        'ms': now().difference(started).inMilliseconds,
      }),
    );
    return db;
  }

  static bool _isCityFile(String path) => path.toLowerCase().contains('city');

  static Future<GeoDatabase> _load(String path) async {
    final compressed = path.toLowerCase().endsWith('.gz');
    var bytes = File(path).openRead();
    if (compressed) bytes = bytes.transform(gzip.decoder);
    final builder = _Builder(path);
    final countries = <String>[];
    final countryIndex = <String, int>{};
    final cities = <String>[];
    final cityIndex = <String, int>{};
    var lineNumber = 0;
    final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      lineNumber++;
      final text = line.trimRight();
      if (text.isEmpty) continue;
      if (lineNumber == 1 && !text.contains('.')) {
        continue; // строка заголовка
      }
      final fields = _splitCsv(text);
      if (fields.length < 3) {
        throw GeoDatabaseException('$path:$lineNumber: меньше трёх полей');
      }
      final start = _ipv4(fields[0]);
      final end = _ipv4(fields[1]);
      final code = fields[2].trim().toUpperCase();
      if (start == null || end == null || start > end) {
        throw GeoDatabaseException(
          '$path:$lineNumber: плохой диапазон адресов',
        );
      }
      if (!_countryCode.hasMatch(code)) {
        throw GeoDatabaseException('$path:$lineNumber: плохой код страны');
      }
      var country = countryIndex[code];
      if (country == null) {
        country = countries.length;
        if (country >= 0xffff) {
          throw GeoDatabaseException('$path: слишком много стран');
        }
        countries.add(code);
        countryIndex[code] = country;
      }
      var city = -1;
      var latitude = double.nan;
      var longitude = double.nan;
      if (fields.length >= 8) {
        final name = fields[5].trim();
        if (name.isNotEmpty) {
          final known = cityIndex[name];
          if (known == null) {
            city = cities.length;
            cities.add(name);
            cityIndex[name] = city;
          } else {
            city = known;
          }
        }
        final lat = double.tryParse(fields[6]);
        final lon = double.tryParse(fields[7]);
        if (lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180) {
          latitude = lat;
          longitude = lon;
        }
      }
      builder.add(start, end, country, city, latitude, longitude);
    }
    if (builder.length == 0) {
      throw GeoDatabaseException('$path: в справочнике нет строк');
    }
    return GeoDatabase._(builder.build(), countries, cities, path);
  }

  /// Место по адресу клиента. `null` — адрес не IPv4, частный или его нет
  /// в справочнике.
  GeoLocation? lookup(String address) {
    final ip = InternetAddress.tryParse(address);
    if (ip == null) return null;
    var raw = ip.rawAddress;
    if (raw.length == 16 && _isMappedV4(raw)) raw = raw.sublist(12);
    if (raw.length != 4) return null;
    if (!NodeAddresses.isPublic(ip)) return null;
    final value = (raw[0] << 24) | (raw[1] << 16) | (raw[2] << 8) | raw[3];
    final i = _ranges.find(value);
    if (i < 0) return null;
    final city = _ranges.city[i];
    final lat = _ranges.latitude[i];
    final lon = _ranges.longitude[i];
    return GeoLocation(
      country: _countries[_ranges.country[i]],
      city: city < 0 ? null : _cities[city],
      latitude: lat.isNaN ? null : lat,
      longitude: lon.isNaN ? null : lon,
    );
  }

  /// Число диапазонов — для журнала и проверок.
  int get ranges => _ranges.length;
}

/// Ошибка справочника geoip: сообщение для оператора.
final class GeoDatabaseException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'GeoDatabaseException: $message';
}

/// Накопитель диапазонов: типизированные массивы с удвоением ёмкости.
/// Строки CSV не превращаются в объекты — на 3 млн строк это экономит
/// сотни мегабайт.
final class _Builder {
  new(this.path);

  final String path;
  int _length = 0;
  var _starts = Uint32List(1 << 12);
  var _ends = Uint32List(1 << 12);
  var _countries = Uint16List(1 << 12);
  var _cities = Int32List(1 << 12);
  var _latitude = Float64List(1 << 12);
  var _longitude = Float64List(1 << 12);

  int get length => _length;

  void add(
    int start,
    int end,
    int country,
    int city,
    double latitude,
    double longitude,
  ) {
    if (_length > 0 && start < _starts[_length - 1]) {
      throw GeoDatabaseException('$path: диапазоны не по возрастанию');
    }
    if (_length >= GeoDatabase.maxRanges) {
      throw GeoDatabaseException(
        '$path: больше ${GeoDatabase.maxRanges} диапазонов — '
        'нужен справочник поменьше',
      );
    }
    if (_length == _starts.length) _grow();
    _starts[_length] = start;
    _ends[_length] = end;
    _countries[_length] = country;
    _cities[_length] = city;
    _latitude[_length] = latitude;
    _longitude[_length] = longitude;
    _length++;
  }

  void _grow() {
    final capacity = _starts.length * 2;
    _starts = _growUint32(_starts, capacity);
    _ends = _growUint32(_ends, capacity);
    _countries = _growUint16(_countries, capacity);
    _cities = _growInt32(_cities, capacity);
    _latitude = _growFloat64(_latitude, capacity);
    _longitude = _growFloat64(_longitude, capacity);
  }

  _Ranges build() => _Ranges(
    Uint32List.sublistView(_starts, 0, _length),
    Uint32List.sublistView(_ends, 0, _length),
    Uint16List.sublistView(_countries, 0, _length),
    Int32List.sublistView(_cities, 0, _length),
    Float64List.sublistView(_latitude, 0, _length),
    Float64List.sublistView(_longitude, 0, _length),
  );
}

Uint32List _growUint32(Uint32List old, int capacity) =>
    Uint32List(capacity)..setRange(0, old.length, old);

Uint16List _growUint16(Uint16List old, int capacity) =>
    Uint16List(capacity)..setRange(0, old.length, old);

Int32List _growInt32(Int32List old, int capacity) =>
    Int32List(capacity)..setRange(0, old.length, old);

Float64List _growFloat64(Float64List old, int capacity) =>
    Float64List(capacity)..setRange(0, old.length, old);

final class _Ranges {
  const new(
    this.start,
    this.end,
    this.country,
    this.city,
    this.latitude,
    this.longitude,
  );

  final Uint32List start;
  final Uint32List end;
  final Uint16List country;
  final Int32List city;
  final Float64List latitude;
  final Float64List longitude;

  int get length => start.length;

  /// Последний диапазон, начало которого не больше [value]; -1 — нет.
  int find(int value) {
    var low = 0;
    var high = start.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (start[mid] <= value) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (found < 0 || value > end[found]) return -1;
    return found;
  }
}

final RegExp _countryCode = RegExp(r'^[A-Z]{2}$');

bool _isMappedV4(Uint8List raw) {
  for (var i = 0; i < 10; i++) {
    if (raw[i] != 0) return false;
  }
  return raw[10] == 0xff && raw[11] == 0xff;
}

/// IPv4 в 32-битное число без знака; не разбирается — `null`.
int? _ipv4(String value) {
  final parts = value.trim().split('.');
  if (parts.length != 4) return null;
  var result = 0;
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) return null;
    if (part.length > 1 && part.startsWith('0')) return null;
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return null;
    result = (result << 8) | octet;
  }
  return result;
}

/// Разбор строки CSV с кавычками: в названиях городов встречаются запятые.
List<String> _splitCsv(String line) {
  if (!line.contains('"')) return line.split(',');
  final fields = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        buffer.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      fields.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  fields.add(buffer.toString());
  return fields;
}
