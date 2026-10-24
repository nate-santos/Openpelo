# Android APK transfer repair

Android OpenPelo 1.0.81 negotiated 4,096-byte ADB transport payloads but sent a
65,536-byte SYNC data chunk as one WRTE. The daemon stopped acknowledging it;
the installer waited indefinitely with a zero-byte target APK. Native desktop
adb does not use this Dart transport and was unaffected.

This repair splits transport writes to the negotiated maximum, serializes
writes, bounds acknowledgement waits to 15 seconds, releases readers/writers
on disconnect, and retains early replies. Empty flushes no longer send WRTE.
SYNC file permissions use decimal 420 (Unix 0644); SYNC shutdown cancels its
reader. `Adb.installApkResult` preserves Android package-manager output and
attempts temporary-file cleanup. The existing boolean helper remains available.

Regression tests cover packet boundaries, multi-megabyte data, missing ACKs,
disconnect/retry, early replies, complete wire-level SYNC reconstruction,
permissions, package-manager rejection details, and cleanup.

`tool/emulator_transfer_smoke.dart [port]` uploads and downloads 2 MiB + 17 bytes
and compares every byte against an actual emulator. OpenPelo's Android UI was
also tested with catalog/local installs, replacement, and a forced timeout.
