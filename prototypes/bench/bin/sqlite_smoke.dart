// Замер 0.5.5: SQLite (пакет sqlite3) в собранном демоне. Открывает базу,
// пишет и читает строки, печатает версию библиотеки.
//
//   dart build cli -t bin/sqlite_smoke.dart

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main() {
  final dir = Directory.systemTemp.createTempSync('sqlite_smoke');
  try {
    final db = sqlite3.open('${dir.path}/index.db')
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('CREATE TABLE chunks (id BLOB PRIMARY KEY, segment BLOB)');
    final insert = db.prepare('INSERT INTO chunks VALUES (?, ?)');
    for (var i = 0; i < 10000; i++) {
      insert.execute([
        [i & 0xFF, (i >> 8) & 0xFF, 1, 2],
        [i % 7],
      ]);
    }
    insert.close();
    final count = db.select('SELECT count(*) AS n FROM chunks').first['n'];
    stdout.writeln(
      'SQLite ${sqlite3.version.libVersion}: записано и прочитано $count строк',
    );
    db.close();
  } finally {
    dir.deleteSync(recursive: true);
  }
}
