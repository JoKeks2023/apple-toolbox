# Validation report

## What was verified (static, on the M1 / 8 GB machine)

| Check | Result |
| --- | --- |
| `swiftc -emit-module`, Swift 6, per SDK with the file lists from `project.pbxproj` (iOS simulator, macOS, tvOS simulator, watchOS simulator, widget) | OK, 0 errors. Remaining warnings: deprecated `MKMapItem.placemark` (#40), one unnecessary `try` |
| Unit tests module (`@testable import AppleToolbox`, Swift Testing) | Typechecks |
| UI tests (XCTest, Swift 6) | Typecheck |
| `actool` for iOS, macOS, watchOS (`AppIcon`) and tvOS (`App Icon & Top Shelf Image`) | Compiles; partial Info.plists contain the icons and top shelf images |
| `plutil -lint` Info.plist and all entitlements files | OK |
| `xcodebuild -list` / `-showBuildSettings` | Project parses; bundle IDs, entitlements, Info.plist generation, module names and test host resolve as intended |
| IMDF reader (agent, #33) | Ran in a small macOS program against Apple's "Displaying an Indoor Map" sample: 643 features, 4 levels |
| Capability registry URLs and keys (agent, #12) | Every documentation URL returned HTTP 200; keys checked against Xcode 27's capability catalog |

`-emit-module` was used instead of `-typecheck` because only it runs the SIL diagnostics (Swift 6 region isolation, definite initialization); switching surfaced real errors that `-typecheck` had missed.

## What was not verified

- **No build or link** of any target, **no launch**, **no test run** (no simulator, no Xcode build on this machine, no CI by decision). Linker, code signing, provisioning, asset embedding in the bundle and App Intents metadata extraction are unverified.
- **No runtime behavior** of any experiment. In particular the prompts, delegate callbacks, sensor values, Multipeer/Nearby between two devices, the watch companion install and ping, widgets, App Shortcuts, RoomPlan, Foundation Models, Translation and ShazamKit matching.
- **Swift 6 dynamic isolation**: callbacks that frameworks invoke off the main thread were audited against the SDK headers and marked `@Sendable`; callbacks documented to run on the main queue (CoreMotion `to: .main`, GameController handlers, Speech result handler, `NotificationCenter` with `.main`) were left main-actor isolated. A missed case would crash at runtime with an executor assertion, so this audit needs device testing.

The checklist for closing these gaps is issue #41.

## Known risks

- Signing needs the new capabilities on the App IDs (HomeKit, HealthKit, NFC, Sign in with Apple, App Group for app and widget). A free Personal Team cannot provision all of them.
- The watch app's bundle ID changed to `com.jorisconrad.AppleToolbox.ios.watchkitapp` (companion requirement); the tvOS bundle ID casing changed to `com.jorisconrad.AppleToolbox.tvos`. Previously installed builds remain as separate apps.
- The macOS target has no entitlements file (#38): protected Keychain items, Sign in with Apple, App Groups and App Attest are expected to fail there.
