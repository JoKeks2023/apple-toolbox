# Implementation report

One commit per issue on `main`. Commits by agents (worktrees `agent/*`) were cherry-picked; project-file conflicts were resolved by re-registering the agents' new files.

| Issue | Commit | Change | By |
| --- | --- | --- | --- |
| #1 | faa6feb | One run view per experiment, lazy `HMHomeManager`, real HomeKit delegate | main |
| #2 | 33d03c9 | Entitlements (NFC, HomeKit, HealthKit) wired to iOS, Face ID / Apple Music / Nearby keys, Bonjour services | main |
| #3 | 6bcb12c | Camera restartable, session work on a serial queue, `RotationCoordinator` orientation | main |
| #4 | a6caac6 | NFC / WatchConnectivity / Nearby delegates hop to the main actor; NFC success not overwritten | main |
| #5 | f1186c9 | Map result count, IMDF import errors visible | main |
| #6 | 4548dce | tvOS Info.plist generation, team, versions, bundle ID, HomeKit entitlement, brand assets | main |
| #7 | ce64cfe | Watch app embedded as companion; shared WatchConnectivity service with ping/pong | main |
| #8 | 0af0ed7 | `AudioSessionController` for Audio Input and Speech | main |
| #9 | 5cd3957 | `PeerInvitationPolicy`: only one Multipeer peer invites | main |
| #10 | f1959ed | `PermissionProbe` / `ExperimentAvailability`: live status, platform metadata fixed | main |
| #11 | 82faaee | `ExperimentLifecycle` (stop on leave, reset), pre-run checks | main |
| #12 | 84e61dc | `CapabilityRegistry` (54 capabilities, keys checked against Xcode's catalog) | agent |
| #13 | 16c57fa | Entitlement Explorer backed by the embedded provisioning profile | agent |
| #14 | b14043d | Device capability scanner (six sections, no prompts) | agent |
| #15 | b0269cb | "Why doesn't this work?" with reason, requirement, next step | main |
| #16 | 26465d2 | Foundation Models: availability reason, streaming, `@Generable` | agent |
| #17 | b784abc | Translation: language pickers, availability, `TranslationSession` | agent |
| #18 | 65f2ba6 | Sound Analysis live classification | agent |
| #19 | bf78111 | Core ML compute devices, model import/compile/inspect | agent |
| #20 | 9b7f704 | ShazamKit `SHManagedSession` matching | agent |
| #21 | 30f6e57 | RoomPlan capture, summary, USDZ export | agent |
| #22 | 2f3e68c | App Attest key/attestation/assertion, DeviceCheck token | agent |
| #23 | 1426e1d | Sign in with Apple flow + credential state; entitlement added | agent |
| #24 | 0e79c2f | Passkey registration/assertion requests | agent |
| #25 | cebae32 | App Intents + App Shortcuts, in-app run; display name "Apple Toolbox" | agent + main |
| #26 | 428641e | Widget with App Group store, Lock Screen families, configuration list | agent |
| #27 | 6f32f75 | Matter setup via `HMAccessorySetupManager` | agent |
| #28 | 7d6a953 | Location: accuracy, `CLMonitor` regions, visits, floor, heading | agent |
| #29 | 78dd11c | Motion: attitude, magnetic field, pedometer, altimeter (+ watch API fix) | agent + main |
| #30 | a2289d4 | Access-controlled Keychain item, persistent Secure Enclave key | agent |
| #31 | db4782a | Watch lab: motion, haptics, iPhone link, device | agent |
| #32 | a010b70 | Game Controller experiment, new Input category | agent + main |
| #33 | f1b9d8a | IMDF archive import (`MKGeoJSONDecoder`), level map | agent |
| #34 | a784713 | `.gitignore`, README, untracked `xcuserdata` | main |
| #35 | 04381f6 | Invariant and service tests, UI smoke tests; module name, test host and scheme fixed | main |
| #36 | 3af7ced | App icons (light/dark/tinted, macOS, watchOS) from `scripts/generate-app-icons.py` | main |
| #37 | 123b1e4 | Swift 6 + MainActor default isolation for all targets; background callbacks `@Sendable` | main |

**Follow-ups filed during the work:** #38 macOS entitlements/versions, #39 tvOS focus for output, #40 deprecated `MKMapItem.placemark`, #41 runtime verification checklist.
