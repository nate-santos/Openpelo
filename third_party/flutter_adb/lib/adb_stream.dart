// Copyright 2024 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_adb/adb_connection.dart';
import 'package:flutter_adb/adb_protocol.dart';

class AdbStream {
  // Preserve broadcast listeners while retaining replies that arrive before
  // the first consumer can subscribe (e.g. immediately after OPEN).
  late final StreamController<Uint8List> _readStream;
  final List<Uint8List> _earlyPayloads = [];
  bool _hasReadListener = false;
  bool _closed = false;
  final StreamController<bool> _writeReadyController =
      StreamController<bool>.broadcast();

  Stream<Uint8List> get onPayload => _readStream.stream;
  Stream<bool> get onWriteReady => _writeReadyController.stream;

  final AdbConnection _adbConnection;
  final int localId;
  int? remoteId;
  bool _writeReady = false;
  Completer<void>? _ready;
  Future<void> _writeTail = Future<void>.value();
  final Duration ioTimeout;

  bool get isClosed => _closed;

  AdbStream(
    this.localId,
    this._adbConnection, {
    this.ioTimeout = const Duration(seconds: 15),
  }) {
    _readStream = StreamController<Uint8List>.broadcast(
      onListen: () {
        _hasReadListener = true;
        for (final payload in _earlyPayloads) {
          _readStream.add(payload);
        }
        _earlyPayloads.clear();
        if (_closed) _readStream.close();
      },
    );
  }

  void addPayload(Uint8List payload) {
    if (isClosed) return;
    if (_hasReadListener) {
      _readStream.add(payload);
    } else {
      _earlyPayloads.add(payload);
    }
  }

  void readyForWrite() {
    if (isClosed) return;
    _writeReady = true;
    _ready?.complete();
    _ready = null;
    _writeReadyController.add(_writeReady);
  }

  Future<void> sendReady() async {
    if (remoteId == null) {
      throw Exception('Remote ID is not set');
    }
    await _adbConnection
        .sendMessage(AdbProtocol.generateReady(localId, remoteId!));
  }

  Future<bool> writeString(String payload) {
    return write(utf8.encode(payload), true);
  }

  Future<void> waitUntilReady() async {
    if (!_writeReady && !isClosed) {
      _ready ??= Completer<void>();
      await _ready!.future.timeout(
        ioTimeout,
        onTimeout: () {
          throw TimeoutException(
            'ADB write acknowledgement timed out',
            ioTimeout,
          );
        },
      );
    }
    if (isClosed && !_writeReady) {
      throw StateError('ADB stream closed during transfer');
    }
  }

  /// SYNC records may be 64 KiB; each ADB transport packet must still fit the
  /// peer's negotiated limit. Serialize callers so their records cannot mix.
  Future<bool> write(Uint8List payload, bool flush) {
    final result = _writeTail.then((_) => _write(payload, flush));
    _writeTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> _write(Uint8List payload, bool flush) async {
    if (isClosed) throw StateError('ADB stream closed during transfer');
    if (remoteId == null) {
      throw Exception('Remote ID is not set');
    }
    final limit = _adbConnection.maxData ?? AdbProtocol.CONNECT_MAXDATA;
    if (limit <= 0) throw StateError('Invalid ADB maximum payload: $limit');
    for (var offset = 0; offset < payload.length; offset += limit) {
      await waitUntilReady();
      _writeReady = false;
      _writeReadyController.add(false);
      final end =
          offset + limit < payload.length ? offset + limit : payload.length;
      await _adbConnection.sendMessage(
        AdbProtocol.generateWrite(
          localId,
          remoteId!,
          Uint8List.sublistView(payload, offset, end),
        ),
        flush: true,
      );
    }
    // An empty write is a barrier, not a zero-length transport packet.
    await waitUntilReady();
    return true;
  }

  void close() {
    if (isClosed) {
      return;
    }
    _closed = true;
    if (_hasReadListener) _readStream.close();
    _ready?.complete();
    _ready = null;
    _writeReadyController.close();
  }

  Future<void> sendClose() async {
    if (isClosed) {
      return;
    }
    await _adbConnection.sendMessage(
      AdbProtocol.generateClose(localId, remoteId!),
      flush: true,
    );
    close();
  }
}
