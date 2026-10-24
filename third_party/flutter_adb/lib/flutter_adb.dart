// Copyright 2024 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_adb/adb_connection.dart';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/adb_stream.dart';
import 'package:flutter_adb/adb_sync.dart';

export 'package:flutter_adb/adb_connection.dart';
export 'package:flutter_adb/adb_crypto.dart';
export 'package:flutter_adb/adb_pairing.dart';
export 'package:flutter_adb/adb_stream.dart';
export 'package:flutter_adb/adb_sync.dart';

class Adb {
  /// Convenience method to open an ADB connection, open a shell and send a single command, then closing the connection.
  /// The function will return the sanitized output of the command.
  static Future<String> sendSingleCommand(
    String command, {
    String ip = '127.0.0.1',
    int port = 5555,
    AdbCrypto? crypto,
  }) async {
    AdbConnection connection = AdbConnection(ip, port, crypto ?? AdbCrypto());
    try {
      if (!await connection.connect()) {
        throw StateError('Could not connect to ADB at $ip:$port');
      }
      return await _runCommand(connection, command);
    } finally {
      await connection.disconnect();
    }
  }

  /// Pushes an APK to the device over the ADB SYNC protocol and installs it
  /// with `pm install -r`. Returns true when the install reports Success.
  ///
  /// Ported from doudar's flutter_adb fork (the SYNC support OpenPelo's
  /// mobile mode was built on) onto upstream 1.0.0.
  static Future<bool> installApk(
    String apkPath, {
    String ip = '127.0.0.1',
    int port = 5555,
    AdbCrypto? crypto,
  }) async {
    try {
      return (await installApkResult(
        apkPath,
        ip: ip,
        port: port,
        crypto: crypto,
      ))
          .split('\n')
          .any((line) => line.trim() == 'Success');
    } catch (e) {
      print('Install error: $e');
      return false;
    }
  }

  /// Returns the actual package-manager result, retaining failure details.
  /// Transfer failures throw so callers can distinguish them from rejections.
  static Future<String> installApkResult(
    String apkPath, {
    String ip = '127.0.0.1',
    int port = 5555,
    AdbCrypto? crypto,
  }) async {
    AdbConnection connection = AdbConnection(ip, port, crypto ?? AdbCrypto());
    final remoteTemp =
        '/data/local/tmp/app_install_${DateTime.now().microsecondsSinceEpoch}.apk';
    try {
      if (!await connection.connect()) {
        throw StateError('Could not connect to ADB at $ip:$port');
      }
      AdbStream syncStream = await connection.open('sync:');
      AdbSync sync = AdbSync(syncStream);
      try {
        await sync.push(apkPath, remoteTemp);
        await sync.sendClose();
      } finally {
        try {
          await sync.abort();
        } catch (_) {
          syncStream.close();
        }
      }
      return await _runCommand(
        connection,
        'pm install -r "$remoteTemp"',
        timeout: const Duration(minutes: 2),
      );
    } finally {
      if (connection.connected) {
        try {
          await _runCommand(
            connection,
            'rm -f "$remoteTemp"',
            timeout: const Duration(seconds: 3),
          );
        } catch (_) {
          // A disconnected device may be unable to clean up its partial APK.
        }
      }
      await connection.disconnect();
    }
  }

  /// Uploads a local file to [remotePath] on the device via ADB SYNC.
  static Future<bool> uploadFile(
    String localPath,
    String remotePath, {
    String ip = '127.0.0.1',
    int port = 5555,
    AdbCrypto? crypto,
  }) async {
    AdbConnection connection = AdbConnection(ip, port, crypto ?? AdbCrypto());
    if (!await connection.connect()) {
      print('Failed to connect to $ip:$port');
      return false;
    }
    try {
      AdbStream stream = await connection.open('sync:');
      AdbSync sync = AdbSync(stream);
      await sync.push(localPath, remotePath);
      await sync.sendClose();
      return true;
    } catch (e) {
      print('Upload error: $e');
      return false;
    } finally {
      await connection.disconnect();
    }
  }

  /// Downloads [remotePath] from the device to [localPath] via ADB SYNC.
  static Future<bool> downloadFile(
    String remotePath,
    String localPath, {
    String ip = '127.0.0.1',
    int port = 5555,
    AdbCrypto? crypto,
  }) async {
    AdbConnection connection = AdbConnection(ip, port, crypto ?? AdbCrypto());
    if (!await connection.connect()) {
      print('Failed to connect to $ip:$port');
      return false;
    }
    try {
      AdbStream stream = await connection.open('sync:');
      AdbSync sync = AdbSync(stream);
      await sync.pull(remotePath, localPath);
      await sync.sendClose();
      return true;
    } catch (e) {
      print('Download error: $e');
      return false;
    } finally {
      await connection.disconnect();
    }
  }

  static Future<String> _runCommand(
    AdbConnection connection,
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final stream = await connection.open('shell:$command');
    try {
      final output = await stream.onPayload
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (!connection.connected) {
        throw StateError('ADB connection lost during command');
      }
      return output.replaceAll('\r', '').trim();
    } finally {
      await stream.sendClose();
    }
  }
}
