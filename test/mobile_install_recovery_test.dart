import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/apk_metadata.dart';
import 'package:openpelo/models/device_model.dart';
import 'package:openpelo/providers/app_provider.dart';
import 'package:openpelo/services/adb_service.dart';
import 'package:openpelo/services/apk_probe_service.dart';
import 'package:openpelo/services/catalog_service.dart';
import 'package:openpelo/services/install_result.dart';

class TestProbe extends ApkProbeService {
  @override
  Future<ApkMetadata> inspectFile(File file) async =>
      ApkMetadata(minSdk: 21, nativeAbis: []);
}

class InstallAdb extends AdbService {
  Completer<String> result = Completer<String>();
  int calls = 0;
  InstallAdb() : super(onLog: (_, _) {});
  @override
  Future<String> installApk(String serial, String apkPath) {
    calls++;
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'transfer timeout releases busy state and permits a successful retry',
    () async {
      final adb = InstallAdb();
      final provider = AppProvider(
        adbService: adb,
        catalogService: CatalogService(probeService: TestProbe()),
        apkPicker: () async => 'test.apk',
      );
      provider.selectedDevice = DeviceModel(
        serial: 'test',
        status: 'device',
        transport: 'wifi',
        apiLevel: 30,
      );
      addTearDown(provider.dispose);
      final first = provider.installLocalApk((_) async => false);
      await Future<void>.delayed(Duration.zero);
      expect(provider.isBusy, isTrue);
      await provider.installLocalApk((_) async => false);
      expect(adb.calls, 1);
      adb.result.completeError(
        TimeoutException('ADB write acknowledgement timed out'),
      );
      await first;
      expect(provider.isBusy, isFalse);
      expect(
        provider.logs.any(
          (entry) => entry.message.contains('acknowledgement timed out'),
        ),
        isTrue,
      );
      adb.result = Completer<String>()..complete('Success');
      await provider.installLocalApk((_) async => false);
      expect(provider.isBusy, isFalse);
      expect(adb.calls, 2);
      expect(provider.logs.last.message, 'Successfully installed local APK');
    },
  );

  test(
    'a rejection containing the word Success is not a successful install',
    () {
      expect(
        isSuccessfulInstallResult('Failure [Success is not permitted]'),
        isFalse,
      );
      expect(
        isSuccessfulInstallResult('Performing Streamed Install\r\nSuccess\r\n'),
        isTrue,
      );
    },
  );
}
