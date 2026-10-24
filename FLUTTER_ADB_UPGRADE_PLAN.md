# flutter_adb upgrade plan — OpenPelo fork

Goal: replace the current Dart ADB client with one that supports modern
Android 11+ wireless pairing and a persistent device identity, without losing
the APK-install / file-transfer features OpenPelo's mobile mode depends on.

## Where things stand (verified 2026-10-23)

- OpenPelo's mobile ADB comes from `flutter_adb`, a **git dependency on
  doudar's fork** (`https://github.com/doudar/flutter_adb.git`), unpinned in
  `pubspec.yaml` (ref: HEAD); `pubspec.lock` resolves it to commit `15edbcf3`,
  version 0.1.1.
- That fork = upstream `flutter_adb` 0.1.1-era code (May–Oct 2024) plus two
  commits by doudar (2026-02-07): "added adb sync" (`9d29fbc9`) and a brace
  fix (`15edbcf3`). The SYNC commit adds `lib/adb_sync.dart` (push/pull) and
  the `Adb.installApk()` / `Adb.uploadFile()` / `Adb.downloadFile()` helpers
  in `lib/flutter_adb.dart`. Nothing else differs from upstream 0.1.1.
- Upstream (`Jellepepe/flutter_adb`, Pepe Tiebosch / byme.dev) released
  **1.0.0 on 2026-03-20**: Android 11+ wireless pairing (STLS + SPAKE2),
  QR pairing with mDNS, built-in keypair persistence
  (`AdbCrypto.exportKeyPairForStorage()` / `keyPairFromStorageMap()`),
  pointycastle ^4.0.0, edwards25519 + multicast_dns deps. Upstream main is 3
  commits past 1.0.0, including `38ffd0f6` "Fix signature reuse/resign (Fixes
  trust popup every connection)". Upstream has **no** SYNC/install support.
- OpenPelo usage (`lib/services/adb_service.dart`, mobile branches only —
  desktop shells out to platform-tools `adb`):
  - 18 static `Adb.*` call sites (`sendSingleCommand`, `installApk`,
    `downloadFile`), **none passing a `crypto:` argument** — so the fork's
    `crypto ?? AdbCrypto()` generates a fresh RSA keypair for every call.
  - `pairDevice()` throws
    `UnsupportedError('Pairing is not supported by the mobile ADB client.')`
    on mobile, even though the UI for it already exists
    (`lib/screens/wireless_connect_screen.dart` collects IP, pairing port,
    6-digit code, connect port; `app_provider.dart` calls
    `pairDevice(ip, port, code)`).
- Dependency check for 1.0.0 in OpenPelo: multicast_dns already a direct dep
  (^0.3.3+1, satisfies upstream's ^0.3.3); pointycastle is transitive only
  (3.9.1 → 4.0.0 via flutter_adb); edwards25519 is a new transitive dep. No
  direct conflicts expected.

## Approach

Rebase the one thing doudar's fork adds (SYNC) onto upstream 1.0.0, in a new
fork under Nate's account. Do **not** try to cherry-pick: upstream rewrote
`lib/flutter_adb.dart` (1740 bytes vs the fork's ~6 KB), so the port is a
hand-port of two files, not a merge.

### Phase 1 — Create `nate-santos/flutter_adb`

1. Fork `Jellepepe/flutter_adb` via the signed-in browser (the GitHub App
   can't fork — same standing workaround as the OpenPelo fork).
2. Branch `sync-on-1.0.0` from upstream main commit `d8c8c3eb`
   (1.0.0 + the trust-popup fix). Cut a tag at the end (e.g. `v1.0.0-sync.1`)
   and pin OpenPelo to the tag — do not repeat the current unpinned-HEAD
   setup.
3. Port from doudar's fork:
   - `lib/adb_sync.dart` — copy nearly as-is. Its API surface
     (`stream.onPayload`, `stream.write(Uint8List, bool)`) exists unchanged
     upstream. One fix while porting: `AdbSync.sendClose()` calls
     `stream.sendClose()` un-awaited; upstream made `sendClose()` async —
     await it.
   - `lib/flutter_adb.dart` — re-add the `installApk` / `uploadFile` /
     `downloadFile` statics and the private `_runCommand`, adapted to
     upstream: `AdbConnection(ip, port, crypto)` signature is unchanged, but
     `AdbStream.writeString` now returns `Future<bool>` and must be awaited.
   - Export `adb_sync.dart` from `flutter_adb.dart` alongside the existing
     exports (`adb_connection`, `adb_crypto`, `adb_pairing`, `adb_stream`).
   - Keep the BSD-3 copyright headers/attribution intact (both forks are
     Pepe Tiebosch's work; doudar's additions ride on the same license).
4. Sanity: `dart analyze`; add a small unit test for SYNC chunking against a
   fake `AdbStream` (none exist upstream today — keep it minimal).

### Phase 2 — OpenPelo integration (branch in `nate-santos/Openpelo`)

1. `pubspec.yaml`: point `flutter_adb` at `nate-santos/flutter_adb`,
   `ref: v1.0.0-sync.1`. `flutter pub get`; confirm resolution
   (pointycastle 4.x, edwards25519 added, multicast_dns unchanged).
2. `lib/services/adb_service.dart`:
   - Add a lazily-initialized, shared `AdbCrypto`:
     load `exportKeyPairForStorage()` JSON from `adb_keypair.json` in the
     app support directory (`path_provider` is already a dependency);
     if absent, create `AdbCrypto(adbKeyName: 'openpelo@android')`, persist
     it, reuse it for the life of the app.
   - Pass `crypto:` at all 18 `Adb.*` call sites.
   - Implement mobile `pairDevice(ip, port, code)` with
     `AdbPairing.pair(ip, port, code, crypto)`; delete the
     `UnsupportedError`. No UI changes needed — the pairing form and the
     provider call already exist.
3. Run the existing tests: `test/adb_service_test.dart`,
   `test/wireless_connection_manager_test.dart`,
   `test/app_provider_connection_test.dart`, plus `flutter analyze`.

### Phase 3 — Verify end-to-end

1. Build the phone APK with the fork's **Build Android APK** workflow
   (dogfoods the new pipeline).
2. On-device matrix against the Android 11 Peloton tablet:
   - Legacy flow: `tcpip 5555` endpoint → connect, run a shell probe,
     install an APK, download a file.
   - Modern flow: tablet Wireless Debugging → "Pair device with pairing
     code" → pair from the phone build → connect on the connect port →
     repeat install/download.
   - Persistence: kill and relaunch the phone app, reconnect — no new
     pairing, no re-authorization prompt (this is the regression the
     ephemeral-keypair behavior causes today).
3. Only after all three pass: merge to `main`, and the next upstream desktop
   release / Android workflow run picks the change up automatically.

## Phone-as-host UI (added 2026-10-23 at Nate's request)

The host device is a **phone**, not a tablet. Checked against the current
codebase — the UI mostly supports this already, because upstream designed a
mobile mode:

- `lib/screens/home_screen.dart` has an explicit breakpoint at 900 px:
  below it the layout stacks vertically (device rail above catalog/log)
  inside a `SingleChildScrollView`, with tighter padding.
- `test/home_screen_layout_test.dart` already runs a **390×844** scenario
  (phone-sized viewport) asserting device details and controls fit without
  overflow, alongside desktop sizes.
- `lib/screens/wireless_connect_screen.dart` (pairing/connect forms) is
  built from scrollable columns — phone-safe.
- All large dialogs go through `DraggableDialog`, which clamps its size to
  `min(requested, viewport − padding)` — a 900 px-wide dialog shrinks to fit
  a phone screen instead of overflowing.
- No orientation lock in the Android manifest; `configChanges` handles
  rotation/screen-size changes.

Known phone-size rough edges to fix in a small UI pass (Phase 2.5, can ride
along with Phase 2):

- `installed_app_manager_dialog.dart` turned out to be single-pane and
  phone-fine as-is. The real problems are all in `file_manager_dialog.dart`,
  confirmed by widget tests at phone sizes (they failed before the fix):
  the toolbar row (path field + 4 shortcut chips on one line), the file
  list's fixed columns (Name + Size 90 + Modified 150 + actions 192 ≈
  524 px minimum), and the destination bar (label + path + Change + open +
  "Ask each time" on one line) all overflow below ~600 px. Fixes applied:
  chips move to their own row under 600 px; the Modified column is hidden
  and per-file actions collapse to the overflow menu (which contains every
  action) under 600 px; the destination bar drops its label, iconifies
  Change, and stacks the toggle under 600 px.
- Widget-test coverage at phone sizes existed only for the home screen.
  Added: `test/file_manager_phone_layout_test.dart` (390×844, 360×800) and
  a 360×800 scenario in the home layout test.
- Dense desktop-style list tiles are usable but not touch-optimized;
  acceptable for v1, revisit only if on-device use says otherwise.

Phase 3's on-device matrix runs on **Nate's phone as the host**; the Peloton
tablet remains the target device.

### Explicitly deferred

- QR-code pairing (`AdbPairing.pairWithQr`): needs QR rendering/camera UI
  and an Android multicast lock for mDNS on the host side. The 6-digit code
  flow covers the tablet use case; add later only if wanted.
- Upstreaming the SYNC port back to Jellepepe/flutter_adb as a PR: nice to
  have, optional, and can be done from the same branch after it proves out
  on-device.

## Risks

- Pointycastle 4.x API changes are contained inside flutter_adb itself
  (OpenPelo never imports pointycastle directly) — low risk.
- Upstream 1.0.0 is young (Mar 2026) and single-maintainer; pinning an exact
  tag in our own fork keeps OpenPelo insulated from upstream churn. The
  maintenance delta we own is two files (`adb_sync.dart` + 3 helper statics).
- Pairing against Peloton's Android 11 build is the one genuinely unknown
  variable — Phase 3 tests it directly before merge; the legacy 5555 flow
  remains as fallback either way.

## Effort estimate

- Phase 1: ~half a day including the analyze/test pass.
- Phase 2: a few hours; the call-site changes are mechanical, the crypto
  storage is ~40 lines using upstream's built-in serialization.
- Phase 3: an hour of builds plus hands-on time with the tablet.
