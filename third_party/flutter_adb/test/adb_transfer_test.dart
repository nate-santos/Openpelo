import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_adb/adb_connection.dart';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/adb_protocol.dart';
import 'package:flutter_adb/adb_stream.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingConnection extends AdbConnection {
  final packets = <Uint8List>[];
  late AdbStream stream;
  bool acknowledge = true;

  RecordingConnection(
    int limit, {
    Duration timeout = const Duration(seconds: 15),
  }) : super('127.0.0.1', 5555, AdbCrypto()) {
    maxData = limit;
    stream = AdbStream(1, this, ioTimeout: timeout)..remoteId = 7;
    stream.readyForWrite();
  }

  @override
  Future<void> sendMessage(Uint8List messageData, {bool flush = false}) async {
    if (ByteData.sublistView(messageData).getUint32(0, Endian.little) ==
        AdbProtocol.CMD_WRTE) {
      packets.add(Uint8List.fromList(messageData.sublist(24)));
      if (acknowledge) scheduleMicrotask(stream.readyForWrite);
    }
  }
}

void main() {
  for (final size in [4095, 4096, 4097, 65536, 2 * 1024 * 1024 + 17]) {
    test('a $size-byte write respects the 4096-byte negotiated limit',
        () async {
      final connection = RecordingConnection(4096);
      addTearDown(connection.stream.close);
      final bytes = Uint8List.fromList(
        List<int>.generate(size, (i) => i % 251),
      );

      expect(await connection.stream.write(bytes, true), isTrue);

      expect(connection.packets, isNotEmpty);
      expect(connection.packets.every((p) => p.length <= 4096), isTrue);
      expect(connection.packets.expand((p) => p).toList(), bytes);
    });
  }

  test('an empty flush does not send an empty ADB WRTE', () async {
    final connection = RecordingConnection(4096);
    addTearDown(connection.stream.close);
    await connection.stream.write(Uint8List(0), true);
    expect(connection.packets, isEmpty);
  });

  test('a missing acknowledgement times out instead of waiting forever',
      () async {
    final connection =
        RecordingConnection(4096, timeout: const Duration(milliseconds: 50))
          ..acknowledge = false;
    addTearDown(connection.stream.close);
    await expectLater(
      connection.stream.write(Uint8List(4097), true),
      throwsA(isA<TimeoutException>()),
    );
    expect(connection.packets, hasLength(1));
  });

  test('a peer close releases a writer waiting for acknowledgement', () async {
    final connection = RecordingConnection(4096)..acknowledge = false;
    final write = connection.stream.write(Uint8List(4097), true);
    final assertion = expectLater(write, throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    connection.stream.close();
    await assertion;
  });

  test('concurrent writes retain byte order and packet boundaries', () async {
    final connection = RecordingConnection(4096);
    addTearDown(connection.stream.close);
    await Future.wait([
      connection.stream.write(Uint8List.fromList(List.filled(5000, 1)), false),
      connection.stream.write(Uint8List.fromList(List.filled(5000, 2)), true),
    ]);
    expect(
      connection.packets.expand((p) => p),
      [...List.filled(5000, 1), ...List.filled(5000, 2)],
    );
  });

  test('a device reply before subscription is retained', () async {
    final connection = RecordingConnection(4096);
    connection.stream.addPayload(Uint8List.fromList([1, 2, 3]));
    connection.stream.close();
    expect(
      await connection.stream.onPayload.expand((p) => p).toList(),
      [1, 2, 3],
    );
  });
}
