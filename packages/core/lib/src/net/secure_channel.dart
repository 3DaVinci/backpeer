import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:core/src/errors.dart';
import 'package:core/src/net/byte_connection.dart';
import 'package:core/src/net/frames.dart';
import 'package:core/src/net/noise.dart';
import 'package:core/src/net/peer_identity.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:meta/meta.dart';
import 'package:protocol/protocol.dart' as pb;

/// Чтение транспортных кадров из [ByteConnection]: рукопожатие берёт их
/// по одному, затем тот же читатель переходит к [SecureChannel] вместе с
/// уже принятыми байтами. Между запросами кадров подписка на входящие
/// байты стоит на паузе — обратное давление до TCP.
final class NoiseFrameReader {
  new(Stream<Uint8List> input) : _input = StreamIterator(input);

  final StreamIterator<Uint8List> _input;
  final TransportFrameDecoder _decoder = TransportFrameDecoder();
  final Queue<Uint8List> _ready = Queue();

  /// Следующее сообщение Noise; `null` — поток закрыт на границе кадра.
  /// Обрыв внутри кадра — [DataFormatException].
  Future<Uint8List?> next() async {
    while (_ready.isEmpty) {
      if (!await _input.moveNext()) {
        if (_decoder.hasPartial) {
          throw const DataFormatException(
            object: 'noise-frame',
            problem: FormatProblem.truncated,
            detail: 'соединение закрыто посреди кадра',
          );
        }
        return null;
      }
      _ready.addAll(_decoder.add(_input.current));
    }
    return _ready.removeFirst();
  }

  Future<void> cancel() => _input.cancel();
}

/// Канал между клиентом и узлом после рукопожатия Noise (protocol.md,
/// разделы 3.3–3.4): сообщения `PeerMessage` в кадрах приложения.
///
/// Ошибка в принятых данных (тег, длина, Protobuf) — ошибка в потоке
/// [messages] и немедленное закрытие соединения без ответа.
final class SecureChannel {
  @internal
  new(
    this._connection,
    this._reader,
    NoiseTransportKeys keys,
    this.peer, {
    int rekeyInterval = NoiseFrames.rekeyInterval,
  }) : _encoder = ChannelEncoder(keys.send, rekeyInterval: rekeyInterval),
       _decoder = ChannelDecoder(keys.receive, rekeyInterval: rekeyInterval),
       sessionId = keys.handshakeHash {
    _messages = StreamController<pb.PeerMessage>(
      onListen: () => unawaited(_pump()),
      onPause: () => _resumed = Completer<void>(),
      onResume: _resume,
      onCancel: destroy,
    );
  }

  final ByteConnection _connection;
  final NoiseFrameReader _reader;
  final ChannelEncoder _encoder;
  final ChannelDecoder _decoder;
  late final StreamController<pb.PeerMessage> _messages;
  Completer<void>? _resumed;
  Future<void> _writes = Future.value();
  bool _closed = false;

  /// Проверенный собеседник.
  final PeerIdentity peer;

  /// `h` после рукопожатия: общий для сторон идентификатор сеанса.
  final Uint8List sessionId;

  /// Принятые сообщения; подписка одна. Поток закрывается вместе с
  /// соединением.
  Stream<pb.PeerMessage> get messages => _messages.stream;

  bool get isClosed => _closed;

  /// Отправляет [message]. Future завершается, когда данные переданы
  /// соединению (обратное давление); отправки идут строго по очереди.
  Future<void> send(pb.PeerMessage message) {
    if (_closed) return Future.error(StateError('канал закрыт'));
    final wire = _encoder.encode(message.writeToBuffer());
    return _writes = _writes.then((_) {
      if (_closed) throw StateError('канал закрыт');
      _connection.add(wire);
      return _connection.flush();
    });
  }

  /// Дожидается начатых отправок и закрывает соединение.
  Future<void> close() async {
    if (_closed) return;
    try {
      await _writes;
    } on Object {
      // Ошибку отправки уже получил вызывающий send.
    }
    if (_closed) return;
    _closed = true;
    await _connection.close();
    _dispose();
  }

  /// Закрывает соединение немедленно.
  void destroy() {
    if (_closed) return;
    _closed = true;
    _connection.destroy();
    _dispose();
  }

  void _dispose() {
    _encoder.dispose();
    _decoder.dispose();
    unawaited(_reader.cancel());
    _resume();
    if (!_messages.isClosed) unawaited(_messages.close());
  }

  void _resume() {
    _resumed?.complete();
    _resumed = null;
  }

  Future<void> _pump() async {
    try {
      while (!_closed) {
        if (_resumed case final resumed?) await resumed.future;
        if (_closed) break;
        final frame = await _reader.next();
        if (_closed) break;
        if (frame == null) {
          if (_decoder.hasPartial) {
            throw const DataFormatException(
              object: 'peer-message',
              problem: FormatProblem.truncated,
              detail: 'соединение закрыто посреди сообщения',
            );
          }
          break;
        }
        for (final body in _decoder.add(frame)) {
          final message = ManifestObjects.parseMessage(
            'peer-message',
            () => pb.PeerMessage.fromBuffer(body),
          );
          if (!_messages.isClosed) _messages.add(message);
        }
      }
    } on Object catch (e, st) {
      if (!_closed && !_messages.isClosed) _messages.addError(e, st);
      destroy();
      return;
    }
    // Собеседник закрыл соединение.
    if (!_closed) {
      _closed = true;
      _connection.destroy();
      _dispose();
    }
  }
}
