# Joris Apple Toolbox

A native multi-platform lab app that answers one question: **What can my Apple devices actually do?**
Every experiment runs a real public Apple API on the current device and shows why something does or does not work, without faking results or bypassing entitlements. Mature experiments are promoted into everyday tools (NFC Inspector, Network Inspector, Location Dashboard, Audio Analyzer, Home Inspector, Indoor Survey, Crypto Lab, Device Scanner).

The full product vision lives in [`SPEC.md`](SPEC.md).

## Targets

| Scheme / target | Platform | Notes |
| --- | --- | --- |
| `AppleToolbox iOS` | iPhone, iPad | Main app; embeds the widget, the notification content extension and the watch app; hosts the unit and UI tests |
| `AppleToolbox macOS` | Mac | Same shared sources, App Sandbox |
| `AppleToolbox tvOS` | Apple TV | Same shared sources, tvOS-specific availability and focus |
| `AppleToolbox watchOS` | Apple Watch | Companion watch lab in `AppleToolbox/WatchApp`, embeds the watch widget |
| `AppleToolbox Widget` | iOS widget extension | Home/Lock Screen widgets, interactive widget, Control Center controls, Live Activity |
| `AppleToolbox Notification Content` | iOS notification content extension | Custom UI for the `toolbox.report` category |
| `AppleToolbox Watch Widget` | watchOS widget extension | Complications |

Requires Xcode 26 or newer; all targets use the Swift 6 language mode with `MainActor` default isolation and approachable concurrency.

## Signing and capabilities

Signing team `T9CA6D7T8N` (a paid Apple Developer Program team; several capabilities are not available to free Personal Teams). Automatic signing registers the capabilities below on the first device build; if provisioning fails, enable them on the App IDs in the developer portal.

- **iOS app** (`com.jorisconrad.AppleToolbox.ios`): Push Notifications (development), Time Sensitive Notifications, Sign in with Apple, Group Activities, HealthKit with Background Delivery, HomeKit, Hotspot, Access Wi-Fi Information, NFC Tag Reading, App Groups (`group.com.jorisconrad.AppleToolbox`), Keychain Sharing (`…AppleToolbox.shared`).
- **Widgets, watch app, watch widget:** App Groups; the watch app also HealthKit.
- **Mac app** (`com.jorisconrad.AppleToolbox.macos`): App Sandbox with camera, microphone, Bluetooth, USB, location, network client/server and user-selected files (read-only), Sign in with Apple, Keychain Sharing, App Groups; hardened runtime.
- **tvOS app:** HomeKit.
- **App Services:** MusicKit and ShazamKit must be enabled for the App ID in the developer portal (no entitlement key).
- **Apple-managed or program capabilities** (HCE card emulation, critical alerts, Tap to Pay, secure element credentials, CarPlay, …) are shown as boundaries in the app; they need Apple approval before they can be added.

Many experiments (NFC, UWB, LiDAR, HealthKit, HomeKit, camera, motion, App Attest, Pencil) only produce meaningful results on a physical device; in the Simulator they report "Device Only".

## Structure

```text
AppleToolbox/
├── AppleToolboxApp.swift, ContentView.swift   app entry, sidebar (Tools, Explore, Inspect)
├── UI/
│   ├── ExperimentDetailView.swift   hero, "Why doesn't this work?", checks, run router, requirements
│   ├── ExperimentLifecycle.swift    stops live sessions on leave, reset
│   ├── Routes/                      run-view routing, one file per category
│   ├── Experiments/                 run views
│   ├── EntitlementExplorerView.swift
│   └── Components.swift
├── Shared/
│   ├── Models/              experiment model, status system, checks, explanations, tools
│   ├── ExperimentRegistry/  descriptors, one Registry+<Category>.swift per category
│   ├── PermissionSystem/    permission probes (never prompt) and live availability
│   ├── CapabilitySystem/    device scanner, capability registry, provisioning inspector
│   └── Services/            one service per experiment family
├── WatchApp/                watchOS lab
├── WatchWidget/             watchOS complications
├── Widget/                  iOS widgets, controls, Live Activity
└── NotificationContent/     notification content extension
scripts/generate-app-icons.py   renders all app icons and tvOS brand assets
docs/tasks/                     task briefs and reports
```

Adding an experiment: add a descriptor to the category's `Registry+<Category>.swift` (live `evaluate` check, optional use case, "Why doesn't this work?" texts and Apple programs), a service in `Shared/Services`, a run view in `UI/Experiments`, and a case in `UI/Routes/<Category>Routes.swift`. The iOS target picks up new files automatically; the macOS, tvOS, watchOS and extension targets list their sources explicitly in the project file.

## Tests

Run the `AppleToolbox iOS` scheme's tests (⌘U): Swift Testing unit tests in `AppleToolboxTests` and XCUITest smoke tests in `AppleToolboxUITests`.

## Issues

Bugs and planned work are tracked as GitHub issues in this repository.
