import 'dart:convert';
import 'dart:typed_data';

/// Подписываемое сообщение `"fs/v1/sign/<context>" || 0x00 || data`
/// (crypto.md, раздел 3.5). Перечень контекстов — protocol.md, раздел 6.
Uint8List signingInput(String context, List<int> data) {
  final label = ascii.encode('fs/v1/sign/$context');
  return Uint8List(label.length + 1 + data.length)
    ..setAll(0, label)
    ..setAll(label.length + 1, data);
}
