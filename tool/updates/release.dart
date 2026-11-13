// Манифест обновлений для релиза GitHub (задача 5.8.2):
// собирает подписанный `stable.json` и `stable.json.sig` из файлов релиза.
//
//   dart run tool/updates/release.dart \
//     --files build/release --tag v0.0.4 --repo 3davinci/backpeer \
//     --public-key "$UPDATE_PUBLIC_KEY"
//
// Закрытый ключ — `UPDATE_SIGNING_KEY` (base64 seed) или `--key`; на машине
// подписи он хранится в секрете GitHub Environment (П-3, docs/ops/github.md).
// Пакеты — установщик Windows, AppImage и `.deb` Linux и `.dmg` macOS, если
// он уже лежит в папке релиза. `.rpm` в манифест не входит: клиент для него
// только уведомляет. Порядок сборок linux: сначала AppImage, потом `.deb` —
// клиенты 0.0.7 и раньше не различают вид сборки и берут первую подходящую,
// то есть образ.
//
// URL пакетов — `https://github.com/<repo>/releases/download/<tag>/<файл>`;
// клиент берёт манифест из `https://github.com/<repo>/releases/latest/
// download/<channel>.json` (docs/spec/updates.md, раздел 8).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';

Future<void> main(List<String> args) async {
  final flags = _parseFlags(args);
  final filesDir = Directory(flags['files'] ?? 'build/release');
  final tag = flags['tag'];
  final repo = flags['repo'];
  final channel = flags['channel'] ?? 'stable';
  final outDir = Directory(flags['out'] ?? filesDir.path);
  final seedText = flags['key'] ?? Platform.environment['UPDATE_SIGNING_KEY'];
  final expectedPublic =
      flags['public-key'] ?? Platform.environment['UPDATE_PUBLIC_KEY'];
  if (tag == null || repo == null) {
    stderr.writeln('нет --tag или --repo');
    exit(64);
  }
  if (seedText == null || seedText.isEmpty) {
    stderr.writeln('нет ключа подписи: --key или UPDATE_SIGNING_KEY');
    exit(64);
  }
  if (channel != 'stable' && channel != 'beta') {
    stderr.writeln('канал должен быть stable или beta: $channel');
    exit(64);
  }
  if (!filesDir.existsSync()) {
    stderr.writeln('нет папки ${filesDir.path}');
    exit(1);
  }

  final version = _versionFromTag(tag);
  final minVersion = ProductVersion.parse(flags['min-version'] ?? '0.0.0');
  if (minVersion > version) {
    stderr.writeln('minVersion $minVersion новее version $version');
    exit(64);
  }
  final rollout = double.tryParse(flags['rollout'] ?? '1');
  if (rollout == null || rollout < 0 || rollout > 1) {
    stderr.writeln('rollout — число от 0 до 1');
    exit(64);
  }

  final crypto = await SodiumCryptoProvider.load();
  final key = await crypto.ed25519FromSeed(
    SecretBytes(base64Decode(seedText.trim())),
  );
  final publicKey = base64Encode(key.publicKey);
  if (expectedPublic != null && expectedPublic != publicKey) {
    stderr
      ..writeln('ключ подписи не совпадает с UPDATE_PUBLIC_KEY:')
      ..writeln('  подпись: $publicKey')
      ..writeln('  ожидался: $expectedPublic');
    exit(1);
  }

  final packages = <Map<String, Object?>>[];
  final files =
      filesDir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.json') && !f.path.endsWith('.sig'))
          .toList()
        ..sort((a, b) {
          final byKind = _priority(a.path).compareTo(_priority(b.path));
          return byKind != 0 ? byKind : a.path.compareTo(b.path);
        });
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final kind = _assetKind(name);
    if (kind == null) continue;
    final bytes = file.readAsBytesSync();
    packages.add({
      'platform': kind.$1,
      'arch': kind.$2,
      'url':
          'https://github.com/$repo/releases/download/'
          '${Uri.encodeComponent(tag)}/${Uri.encodeComponent(name)}',
      'sha256': bytesToHex(crypto.blake2b256(bytes)),
      'size': bytes.length,
    });
    stdout.writeln('  ${kind.$1}/${kind.$2 ?? '-'}: $name (${bytes.length} B)');
  }
  if (packages.isEmpty) {
    stderr.writeln('в ${filesDir.path} нет пакетов для автообновления');
    exit(1);
  }

  final manifest = {
    'format': 1,
    'channel': channel,
    'version': version.toString(),
    'minVersion': minVersion.toString(),
    'releasedAt': DateTime.now().toUtc().toIso8601String(),
    'rollout': rollout,
    'packages': packages,
    'signer': publicKey,
  };
  final json = const JsonEncoder.withIndent('  ').convert(manifest);
  final bytes = utf8.encode(json);
  final manifestFile = File('${outDir.path}/$channel.json')
    ..writeAsBytesSync(bytes, flush: true);
  final signature = await crypto.ed25519Sign(
    key,
    signingInput('updates', Uint8List.fromList(bytes)),
  );
  File('${manifestFile.path}.sig').writeAsBytesSync(signature, flush: true);
  stdout
    ..writeln('Манифест: ${manifestFile.path}')
    ..writeln('Подпись:  ${manifestFile.path}.sig')
    ..writeln(
      'Версия:   $version, канал: $channel, пакетов: ${packages.length}',
    )
    ..writeln('Ключ:     $publicKey');
}

/// `v0.0.4` → `0.0.4`; prerelease-теги (`v0.0.4-dev.1`) в манифест не идут.
ProductVersion _versionFromTag(String tag) {
  final text = tag.startsWith('v') ? tag.substring(1) : tag;
  if (text.contains('-') || text.contains('+')) {
    stderr.writeln('тег $tag не стабильный: в манифест идут только X.Y.Z');
    exit(64);
  }
  return ProductVersion.parse(text);
}

/// Платформа и архитектура по имени файла релиза.
(String, String?)? _assetKind(String name) {
  final windows = RegExp(r'^Backpeer-Setup-.*-windows-(x64|x86_64|arm64)\.exe$')
      .firstMatch(name);
  if (windows != null) return ('windows', _arch(windows[1]!));
  final linux = RegExp(r'^backpeer-.*-(x86_64|aarch64|x64|arm64)\.AppImage$')
      .firstMatch(name);
  if (linux != null) return ('linux', _arch(linux[1]!));
  // `.deb`: backpeer_0.0.8_amd64.deb — ставится клиентом через apt (5.8.2).
  final deb = RegExp(r'^backpeer_.*_(amd64|arm64)\.deb$').firstMatch(name);
  if (deb != null) return ('linux', _arch(deb[1]!));
  final macos = RegExp(r'^Backpeer-.*-macos-(x64|arm64|x86_64|aarch64)\.dmg$')
      .firstMatch(name);
  if (macos != null) return ('macos', _arch(macos[1]!));
  return null;
}

String _arch(String text) => switch (text) {
  'x86_64' || 'x64' || 'amd64' => 'x64',
  'aarch64' || 'arm64' => 'arm64',
  _ => text,
};

/// Порядок сборок в манифесте: сначала те, что понимают все клиенты.
int _priority(String name) {
  if (name.endsWith('.deb')) return 1;
  if (name.endsWith('.rpm')) return 2;
  return 0;
}

Map<String, String> _parseFlags(List<String> args) {
  final flags = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) {
      stderr.writeln('неизвестный аргумент: $arg');
      exit(64);
    }
    final name = arg.substring(2);
    if (i + 1 >= args.length) {
      stderr.writeln('нет значения у --$name');
      exit(64);
    }
    flags[name] = args[++i];
  }
  return flags;
}
