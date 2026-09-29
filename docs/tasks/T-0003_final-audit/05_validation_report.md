# Validation report

**Static checks (main, before push):**
- `typecheck.py`, Swift 6 `-emit-module`, gave 0 errors and 0 warnings for every config: ios (193 files), iosdevice, macos (186), tvos (187), watchos (88), widget, watchwidget, notifcontent, notifservice, credprovider and tunnel. The tests typecheck (50 files).
- `plutil -lint` passed for every tracked plist and entitlements file.
- `xcodebuild -list` lists all 12 targets with no errors.

**What was not done:**
- Nothing was built, linked, installed, launched or tested.
- No unit or UI test was executed; the tests were only typechecked.

The owner declined local builds for now (8 GB M1), so every runtime claim is **unverified** and stays in #41. That includes:
- the extensions: push rewrite, AutoFill, tunnel start;
- the iOS 27 features: Core AI, Foundation Models image input;
- anything that needs specific hardware or other devices: watch runs, NFC and MIFARE reads, HomeKit and Matter setup, ShazamKit catalogs, ARWorldMap, controller haptics, tvOS focus, and Multipeer between iPhone and Apple TV.

**Known integration issue, fixed:** #91 added code to `NotificationServices.swift`, which the watch target compiles since #88. Commit 0b16730 fixes that.
