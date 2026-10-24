import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_adb/adb_protocol.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_test/flutter_test.dart';

/// A wire-level peer: it negotiates a real packet limit, reconstructs SYNC
/// records across transport packets, and can reject an install or drop a link.
class TestDaemon {
  late ServerSocket server;
  final sockets = <Socket>[];
  final commands = <String>[];
  final data = BytesBuilder(copy: false);
  int maxPacket = 0;
  int? mode;
  int? dropAfter;
  String installResult = 'Success\n';

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      sockets.add(socket);
      var input = <int>[];
      final sessions = <int, List<int>>{};
      socket.listen(
        (bytes) {
          input.addAll(bytes);
          while (input.length >= 24) {
            final header = ByteData.sublistView(Uint8List.fromList(input));
            final length = header.getUint32(12, Endian.little);
            if (input.length < 24 + length) break;
            final command = header.getUint32(0, Endian.little);
            final local = header.getUint32(4, Endian.little);
            final payload = input.sublist(24, 24 + length);
            input = input.sublist(24 + length);
            void send(int cmd, int a, int b, List<int>? p) => socket.add(
                  AdbProtocol.generateMessage(
                    cmd,
                    a,
                    b,
                    p == null ? null : Uint8List.fromList(p),
                  ),
                );
            if (command == AdbProtocol.CMD_CNXN) {
              send(
                AdbProtocol.CMD_CNXN,
                AdbProtocol.CONNECT_VERSION,
                4096,
                utf8.encode('device::\x00'),
              );
            } else if (command == AdbProtocol.CMD_OPEN) {
              final destination = utf8.decode(payload).replaceAll('\x00', '');
              send(AdbProtocol.CMD_OKAY, 100 + local, local, null);
              if (destination == 'sync:') {
                sessions[local] = [];
              } else if (destination.startsWith('shell:')) {
                final cmd = destination.substring(6);
                commands.add(cmd);
                send(
                  AdbProtocol.CMD_WRTE,
                  100 + local,
                  local,
                  utf8.encode(
                    cmd.startsWith('pm install ') ? installResult : '',
                  ),
                );
                send(AdbProtocol.CMD_CLSE, 100 + local, local, null);
              }
            } else if (command == AdbProtocol.CMD_WRTE) {
              if (length > maxPacket) maxPacket = length;
              if (length > 4096) {
                socket.destroy();
                return;
              }
              if (dropAfter != null && data.length >= dropAfter!) {
                socket.destroy();
                return;
              }
              send(AdbProtocol.CMD_OKAY, 100 + local, local, null);
              final sync = sessions[local];
              if (sync == null) continue;
              sync.addAll(payload);
              while (sync.length >= 8) {
                final id = ascii.decode(sync.sublist(0, 4));
                final n = ByteData.sublistView(Uint8List.fromList(sync))
                    .getUint32(4, Endian.little);
                final bodySize = id == 'DONE' || id == 'QUIT' ? 0 : n;
                if (sync.length < 8 + bodySize) break;
                final body = sync.sublist(8, 8 + bodySize);
                sync.removeRange(0, 8 + bodySize);
                if (id == 'SEND') {
                  mode = int.parse(utf8.decode(body).split(',').last);
                }
                if (id == 'DATA') data.add(body);
                if (id == 'DONE') {
                  send(
                    AdbProtocol.CMD_WRTE,
                    100 + local,
                    local,
                    [79, 75, 65, 89, 0, 0, 0, 0],
                  );
                }
              }
            }
          }
        },
        onError: (_) {},
      );
    });
  }

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  }
}

void main() {
  late TestDaemon peer;
  late Directory temp;
  late File apk;
  late List<int> bytes;
  setUp(() async {
    peer = TestDaemon();
    await peer.start();
    temp = await Directory.systemTemp.createTemp('adb-transfer-test-');
    bytes = List.generate(128 * 1024 + 17, (i) => i % 251);
    apk = await File('${temp.path}/test.apk').writeAsBytes(bytes);
  });
  tearDown(() async {
    await peer.close();
    await temp.delete(recursive: true);
  });

  test('SYNC reconstruction, correct permissions, install result and cleanup',
      () async {
    final result = await Adb.installApkResult(apk.path, port: peer.server.port);
    expect(result, 'Success');
    expect(peer.data.toBytes(), bytes);
    expect(peer.mode, 420); // octal 0644, expressed as decimal on the wire
    expect(peer.maxPacket, lessThanOrEqualTo(4096));
    expect(peer.commands.first, startsWith('pm install -r '));
    expect(peer.commands.last, startsWith('rm -f '));
  });

  test('package-manager rejection is retained and temporary file is cleaned',
      () async {
    peer.installResult =
        'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures differ]\n';
    expect(
      await Adb.installApkResult(apk.path, port: peer.server.port),
      contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE'),
    );
    expect(peer.commands.last, startsWith('rm -f '));
  });

  test(
      'disconnect during SYNC throws promptly and a fresh connection can retry',
      () async {
    peer.dropAfter = 65536;
    await expectLater(
      Adb.installApkResult(apk.path, port: peer.server.port)
          .timeout(const Duration(seconds: 3)),
      throwsA(isNot(isA<TimeoutException>())),
    );
    peer.dropAfter = null;
    peer.data.clear();
    expect(
      await Adb.installApkResult(apk.path, port: peer.server.port),
      'Success',
    );
    expect(peer.data.toBytes(), bytes);
  });
}
