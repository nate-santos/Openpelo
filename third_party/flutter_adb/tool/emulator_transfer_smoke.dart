import 'dart:io';

import 'package:flutter_adb/flutter_adb.dart';

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 5555 : int.parse(args.first);
  final temp = await Directory.systemTemp.createTemp('openpelo-adb-smoke-');
  final source = File('${temp.path}/source.bin');
  final returned = File('${temp.path}/returned.bin');
  final bytes = List<int>.generate(2 * 1024 * 1024 + 17, (i) => i % 251);
  const remote = '/data/local/tmp/openpelo_transfer_regression.bin';
  try {
    await source.writeAsBytes(bytes);
    if (!await Adb.uploadFile(source.path, remote, port: port)) {
      throw StateError('Upload failed');
    }
    if (!await Adb.downloadFile(remote, returned.path, port: port)) {
      throw StateError('Download failed');
    }
    final actual = await returned.readAsBytes();
    if (actual.length != bytes.length ||
        Iterable<int>.generate(bytes.length)
            .any((i) => actual[i] != bytes[i])) {
      throw StateError('Transferred bytes differ');
    }
    print('PASS: ${bytes.length} bytes uploaded and downloaded unchanged.');
    print(await Adb.sendSingleCommand('ls -l $remote', port: port));
  } finally {
    await Adb.sendSingleCommand('rm -f $remote', port: port);
    await temp.delete(recursive: true);
  }
}
