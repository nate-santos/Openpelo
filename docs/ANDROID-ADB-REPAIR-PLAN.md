# OpenPelo Android ADB repair plan

Saved October 24, 2026.

## Baseline and diagnosis

Windows installs use native adb.exe. Android installs use the Dart flutter_adb transport. The Android release pins dependency revision 58ce3167a9d4f217f46e034b0a56402e7640d50d. A captured Android-to-Android install negotiates a 4,096-byte ADB maximum payload, then sends one 65,536-byte WRTE and stalls with a zero-byte target APK.

## Execution

1. Establish a repeatable baseline using one fixed APK and checksum on two API 30 emulators, with Windows OpenPelo as a control. Independently verify target package version and launch.
2. Reproduce the oversized write with focused dependency regression tests: below, at, and above a negotiated packet limit, multi-megabyte payloads, acknowledgements, rejection, disconnect, and timeout.
3. Repair flutter_adb transport framing to split writes to negotiated maxData and await acknowledgements; bound waits and propagate errors. Inspect decimal 0644 file mode and zero-length flush writes.
4. Make OpenPelo surface useful upload/package-manager errors, release busy state, permit retry, close connections, and attempt temporary-file cleanup.
5. Build a clearly identified repaired Android APK and test catalog install, local APK, replacement, interruption and retry. Verify package/version and launch; resolve the Android picker issue if reproduced.
6. Validate Android 11 wireless pairing and reconnect after application restart, then rerun Windows installation.

## Acceptance criteria

- Every ADB transfer respects the negotiated payload limit.
- Catalog and local APK installs succeed from Android OpenPelo to the target emulator.
- Installed apps launch and replacement installs work.
- Interrupted transfers produce bounded, recoverable errors and permit a successful retry.
- Android 11 pairing and reconnection after app restart work.
- Windows OpenPelo still installs successfully.

## Deliverables

Reviewable source changes, meaningful regression tests, a rebuilt Android APK, retained packet/UI/package evidence, and a final acceptance matrix. Record unverified criteria explicitly; never infer a pass from a success message alone.

## Progress

- [x] Plan saved.
- [x] Repositories and build tools prepared.
- [x] Regression failure reproduced in tests.
- [x] Dependency and OpenPelo repair implemented.
- [x] Regression tests and analysis pass (150 combined tests; clean analysis).
- [x] Rebuilt Android app passes emulator installation and recovery checks.
- [x] Pairing/persistent identity checked on authenticated Android 11, including TLS reconnection after app restart and a successful install.
- [x] Windows regression checked through the Windows release UI.

## Completed implementation

The repaired dependency is saved in commit 28995a196ba5f098141807ea76af7cfe16a31985 and included as a licensed source snapshot in Openpelo/third_party/flutter_adb. OpenPelo uses that relative package path, so the repair is self-contained. After explicit publication authorization, the repair branches were pushed only to nate-santos/flutter_adb (fix/negotiated-adb-writes) and nate-santos/Openpelo (fix/android-adb-transfer). No upstream repositories were changed.

The tested Android x86_64 APK is test-environment/OpenPelo-Android-adb-repair-x86_64.apk (version 1.0.81-adb-repair, build 82). The final acceptance matrix and evidence index are in Openpelo/docs/ANDROID_ADB_REPAIR_RESULTS.md.
