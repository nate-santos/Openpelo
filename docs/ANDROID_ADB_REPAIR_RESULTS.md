# OpenPelo Android ADB repair — acceptance results

Completed October 24, 2026. All acceptance criteria pass.

## What changed

The Android release's Dart ADB client negotiated a 4,096-byte maximum payload
but sent a 65,536-byte file chunk in one ADB WRTE. The target stopped replying,
and installation remained busy indefinitely. Windows uses bundled native adb
and did not exercise that Dart transfer path.

The repair splits writes to the negotiated transport maximum, preserves record
order, waits for acknowledgements with a 15-second timeout, and releases
pending reads/writes on disconnect. It buffers replies arriving before a reader
subscribes without removing broadcast support. Empty flush writes no longer
create packets. File mode uses decimal 420 for Unix 0644.

The new install-result helper retains package-manager error output and attempts
temporary-file cleanup. OpenPelo uses it and recognizes an exact Success line,
so an error containing that word cannot be reported as success. Existing
finally blocks release the busy state; regression tests verify retry.

## Acceptance matrix

| Criterion | Result | Evidence |
| --- | --- | --- |
| Negotiated packet maximum respected | PASS | 6,550 captured SYNC WRTE packets; maximum payload 4,096 bytes. Boundary and multi-megabyte tests also pass. |
| Android catalog install | PASS | Controller emulator-5556 installed Grupetto v0.0.43 (`com.spop.poverlay`) on API 30 target emulator-5554. |
| Android local APK install | PASS | Controller installed Amaze 3.10 (`com.amaze.filemanager`) from its local Download folder onto emulator-5554. |
| Installed applications launch | PASS | Android activity launch evidence recorded for both apps; Amaze resumed its MainActivity. Grupetto's launch returned Status: ok. |
| Replacement installation | PASS | Grupetto retained its first-install time and advanced last-update time after the retry. |
| Bounded failure and successful retry | PASS | A proxy withheld one transfer acknowledgement. OpenPelo reported a timeout from 12:49:56 to 12:50:11 (15 seconds), restored controls, and reinstalled successfully at 12:51:06 without restarting. |
| Android 11 pairing and TLS | PASS | Authenticated API 30 Google Play target emulator-5558 listed openpelo@android; adbd recorded a matching authorized key. |
| Persistent identity after OpenPelo restart | PASS | The final APK reconnected at 13:10:44 with empty pairing-code/port fields and the existing paired identity. |
| Installation after TLS reconnect | PASS | Final APK installed/reinstalled Grupetto over TLS, logging Success at 13:12:30. Target version and launch were independently verified. |
| Windows regression | PASS | Windows OpenPelo 1.0.81 downloaded and installed Grupetto with native adb at 13:00:20. Exported activity identifies the target and install command. |

All 150 application and dependency tests pass together. Static analysis reports
no issues. The new transport tests were first run against the original code:
writes over the negotiated limit and the empty-flush test failed before repair.
A separate actual-emulator test uploaded/downloaded 2,097,169 bytes and compared
every byte successfully.

The Windows control APK and APK pulled back from the Android TLS target have
the same SHA-256: `120eb38a4f6b255d59c99be094c5f6b5bcb70730af1fcc41a4210ccd196a5efb`.

The Windows control used the downloaded Windows release, not a newly rebuilt
Windows binary. Android testing used Android 11/API 30 x86_64 emulators; physical
hardware and ARM devices were not tested.

## Build and source

- APK: `test-environment/OpenPelo-Android-adb-repair-x86_64.apk`, relative to the parent workspace.
- Version: `1.0.81-adb-repair`, version code 82; minimum API 24, target API 37.
- APK SHA-256: `d77c14afee6eb1cc38ef2258be40bb33688349fb2c872bbd429187b5e8f76919`.
- The APK is signed with a dedicated local emulator-test key. It is an x86_64 test artifact.
- Flutter 3.44.4 / Dart 3.12.2, Java 17, SDK platform 37.0, build tools 37.0.0, NDK 28.2.13676358.
- Dependency repair: local branch `fix/negotiated-adb-writes`, commit `28995a196ba5f098141807ea76af7cfe16a31985` in the sibling flutter_adb checkout.
- OpenPelo branch: `fix/android-adb-transfer`, based on flutter-adb-upgrade.
- OpenPelo includes the complete repaired package and license under `third_party/flutter_adb`, referenced by a relative path. No unpublished Git reference or local override is required.

Reproduction from the OpenPelo checkout:

```text
flutter pub get --enforce-lockfile
flutter test test third_party/flutter_adb/test
flutter analyze
flutter build apk --release --target-platform android-x64 --build-name 1.0.81-adb-repair --build-number 82
```

Use the project's normal release-signing configuration or sign the unsigned
test artifact with an emulator-test key. The test key is outside the repository.

## Emulator setup findings

The original unencrypted target uses the emulator's native ADB endpoint,
accessed from the controller through `10.0.2.2:5555`. The instrumented test proxy
used loopback port 15557 and did not modify packets during normal tests.

The authenticated target initially allowed pairing but its system service
could not write `/data/misc/adb/adb_keys` (EACCES). Its paired key appeared in
the UI but could not authorize TLS. Reboot did not resolve it. Clearing the
fresh emulator's debugging authorizations through Developer options and
re-enabling wireless debugging let Android recreate the store correctly.
Pairing, TLS connections, and installs then succeeded. No certificate checks
were disabled to work around that permission error.

The system document picker's item taps did not activate items under the test
automation. Keyboard navigation selected the APK normally and OpenPelo received
and installed it. No picker-specific application change was needed.

## Evidence index

Evidence remains under `test-environment/android-to-android/` in the parent
workspace. The original failed-release report is retained separately as
`TEST-REPORT.md`.

- `final-combined-tests.log`: 150 passing tests.
- `dependency-tests.log`, `openpelo-tests.log`: component test results.
- `repair-packets.jsonl`, `repair-packet-summary.json`: packet bounds and forced stall.
- `repair-catalog-install.xml`, `repair-local-install.xml`: Android UI success logs.
- `repaired-grupetto-package.txt`, `repaired-grupetto-replacement.txt`: initial/replacement package evidence.
- `repaired-amaze-package.txt`, `repaired-amaze-launch.txt`: local install and launch evidence.
- `repair-stall-result.xml`, `repair-retry-result.xml`: timeout and recovery evidence.
- `tls-second-source.xml`, `tls-second-target.xml`: successful real pairing/TLS connection.
- `tls-after-restart-connected.xml`: reconnection without pairing again.
- `final-tls-install-progress.xml`, `final-tls-success.png`: final APK's TLS install success.
- `final-tls-package.txt`, `final-tls-launch.txt`, `final-tls-auth.txt`: independent TLS-target verification.
- `windows-regression-activity.txt`: exported Windows install activity.
- `same-apk-checksum.txt`: identical-APK verification for Windows and Android.
- `final-controller-crash-log.txt`: no Android crash records for the final controller test.

GitHub publication is outside this local deliverable. Source and test artifacts
remain local; no remote branch, pull request, or release was created.
