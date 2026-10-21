// Тесты работают только в Dart VM (64-битный int), JavaScript не нужен.
// ignore_for_file: avoid_js_rounded_ints

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('ByteWriter и ByteReader', () {
    test('целые little-endian и big-endian', () {
      final w = ByteWriter(1)
        ..u8(0xAB)
        ..u16le(0x0102)
        ..u32le(0x01020304)
        ..u64le(0x0102030405060708)
        ..u16be(0x0102)
        ..u32be(0x01020304)
        ..u64be(0x0102030405060708);
      expect(
        bytesToHex(w.toBytes()),
        'ab'
        '0201'
        '04030201'
        '0807060504030201'
        '0102'
        '01020304'
        '0102030405060708',
      );
      final r = ByteReader(w.toBytes());
      expect(r.u8(), 0xAB);
      expect(r.u16le(), 0x0102);
      expect(r.u32le(), 0x01020304);
      expect(r.u64le(), 0x0102030405060708);
      expect(r.u16be(), 0x0102);
      expect(r.u32be(), 0x01020304);
      expect(r.u64be(), 0x0102030405060708);
      expect(r.isAtEnd, isTrue);
    });

    test('u64 со старшим битом сохраняет все биты', () {
      final w = ByteWriter()..u64le(0xFFFFFFFFFFFFFFFF);
      expect(bytesToHex(w.toBytes()), 'ff' * 8);
      expect(ByteReader(w.toBytes()).u64le(), -1);
    });

    test('значение вне диапазона ширины', () {
      final w = ByteWriter();
      expect(() => w.u8(256), throwsRangeError);
      expect(() => w.u16le(-1), throwsRangeError);
      expect(() => w.u32be(0x100000000), throwsRangeError);
    });

    test('чтение за концом буфера', () {
      final r = ByteReader(Uint8List(3));
      expect(r.u16le, returnsNormally);
      expect(r.u16le, throwsRangeError);
      expect(r.offset, 2);
      expect(() => r.bytes(2), throwsRangeError);
    });

    test('bytes, zeros и skip', () {
      final w = ByteWriter()
        ..bytes([1, 2, 3])
        ..zeros(2)
        ..bytes([9]);
      final data = w.toBytes();
      expect(data, [1, 2, 3, 0, 0, 9]);
      final r = ByteReader(data);
      expect(r.bytes(3), [1, 2, 3]);
      r.skip(2);
      expect(r.remaining, 1);
      expect(r.u8(), 9);
    });
  });

  group('varint', () {
    const cases = {
      0: '00',
      1: '01',
      127: '7f',
      128: '8001',
      300: 'ac02',
      16384: '808001',
      0x7FFFFFFFFFFFFFFF: 'ffffffffffffffff7f',
      -1: 'ffffffffffffffffff01',
    };
    for (final MapEntry(key: value, value: hex) in cases.entries) {
      test('$value ↔ $hex', () {
        expect(bytesToHex((ByteWriter()..varint(value)).toBytes()), hex);
        final r = ByteReader(hexToBytes(hex));
        expect(r.varint(), value);
        expect(r.isAtEnd, isTrue);
      });
    }

    test('неканонический, слишком длинный и обрезанный', () {
      expect(
        () => ByteReader(hexToBytes('8000')).varint(),
        throwsFormatException,
      );
      expect(
        () => ByteReader(hexToBytes('ffffffffffffffffff02')).varint(),
        throwsFormatException,
      );
      expect(
        () => ByteReader(hexToBytes('ffffffffffffffffff8001')).varint(),
        throwsFormatException,
      );
      expect(() => ByteReader(hexToBytes('80')).varint(), throwsRangeError);
    });
  });

  group('hex', () {
    test('туда и обратно', () {
      final data = Uint8List.fromList(List.generate(256, (i) => i));
      final hex = bytesToHex(data);
      expect(hex.length, 512);
      expect(hex.substring(0, 8), '00010203');
      expect(hexToBytes(hex), data);
      expect(hexToBytes('ABcd'), [0xAB, 0xCD]);
    });

    test('ошибки разбора', () {
      expect(() => hexToBytes('abc'), throwsFormatException);
      expect(() => hexToBytes('zz'), throwsFormatException);
      expect(() => hexToBytes('0g'), throwsFormatException);
    });
  });

  test('constantTimeEquals', () {
    expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
  });
}
