# Validation report

## Verified (static, 8 GB M1, no builds, no simulators)

| Check | Result |
| --- | --- |
| `swiftc -emit-module`, Swift 6 strict, file lists from `project.pbxproj`: iOS Simulator SDK, iOS device SDK, macOS, tvOS, watchOS, iOS widget, watch widget, notification content extension | OK, 0 errors, 0 warnings |
| Unit tests module (39 test files, Swift Testing) | Typechecks |
| UI tests (Swift 6) | Typecheck, 0 diagnostics |
| `plutil -lint` on all 10 plists/entitlements | OK |
| `actool`: iOS, macOS, watchOS (`AppIcon`), tvOS (`App Icon & Top Shelf Image`) | Compiles |
| `xcodebuild -list` / `-showBuildSettings` for all 9 targets | Parse; bundle IDs, Swift 6, entitlements files resolve |
| Swift 6 runtime-isolation audit: all framework delegates/protocol conformances | Main-queue delegates stay isolated (no custom queues set); off-main delegates and callbacks are `nonisolated`/`@Sendable`; one violation found and fixed (#83) |
| Pure logic run outside the app by agents | CryptoKit lab (56 checks incl. RFC/NIST vectors), audio DSP (FFT/interpolation), IMDF reader (Apple sample: 643 features), HomeKit/HealthKit formatting helpers |

## Not verified

- **No build, link, signing or launch** of any target, and **no test execution**. Code signing will need the capabilities listed in the README on the App IDs; the new extension bundle IDs must be registered.
- **No runtime behaviour** of any experiment: permission prompts, sensors, radios (NFC, Bluetooth, UWB, Wi-Fi), camera/Vision/AR/RoomPlan, audio engines, HomeKit/HealthKit data, Wallet/Apple Pay sheets, notifications/Live Activities/widgets/controls/complications, Spotlight/Handoff/SharePlay, multi-device flows (Multipeer, Spatial Link, WatchConnectivity), Create ML training, Foundation Models, SpeechAnalyzer, MusicKit/ShazamKit.
- **Pre-checks that could not be confirmed without a device:** `CardSession.isSupported`/`isEligible` and `CredentialSession.isEligible` are called without the Apple-managed entitlements (documented as pre-checks).

The device checklist is issue #41.

## Known limits and risks

- Several capabilities are Apple-managed or need programs (HCE, critical alerts, Tap to Pay, secure element credentials, CarPlay, Home/Car Key); the app shows these as boundaries only.
- Mac: the app is sandboxed; Indoor Survey data saved by earlier unsandboxed builds stays outside the container.
- `OpenExperimentIntent` became an `OpenIntent` (#76); Shortcuts that bound its old parameter lose that value.
- AccessorySetupKit picker stays disabled until the owner decides to declare the ASK Info.plist keys (trade-off with Core Bluetooth scanning, see #53).
