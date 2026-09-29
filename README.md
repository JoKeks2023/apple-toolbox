# Joris Apple Toolbox

A native multi-platform lab app that answers one question: **What can my Apple devices actually do?**
Every experiment runs a real public Apple API on the current device and shows why something does or does not work, without faking results or bypassing entitlements.

The full product vision lives in [`SPEC.md`](SPEC.md).

## Targets

| Scheme | Platform | Notes |
| --- | --- | --- |
| `AppleToolbox iOS` | iPhone, iPad | Main app; embeds the widget extension and the watch app; runs the unit and UI tests |
| `AppleToolbox macOS` | Mac | Same shared sources as iOS |
| `AppleToolbox tvOS` | Apple TV | Same shared sources, tvOS-specific availability |
| `AppleToolbox watchOS` | Apple Watch | Companion watch lab in `AppleToolbox/WatchApp` |
| `AppleToolbox Widget` | iOS widget extension | `AppleToolbox/Widget`, reads the App Group store |

Requires Xcode 26 or newer; all targets use the Swift 6 language mode with `MainActor` default isolation.

Many experiments (NFC, UWB, LiDAR, HealthKit, HomeKit, camera, motion, App Attest) only produce meaningful results on a physical device. Signing team `T9CA6D7T8N` needs these capabilities on the App IDs; automatic signing registers them on the first device build: HomeKit, HealthKit (with Background Delivery), NFC Tag Reading, Sign in with Apple and the App Group `group.com.jorisconrad.AppleToolbox` (app and widget). ShazamKit matching also needs the ShazamKit App Service enabled for the App ID in the developer portal.

## Structure

```text
AppleToolbox/
├── AppleToolboxApp.swift, ContentView.swift   app entry, sidebar navigation
├── UI/
│   ├── ExperimentDetailView.swift   hero, "Why doesn't this work?", checks, run router, requirements
│   ├── ExperimentLifecycle.swift    stops live sessions on leave, reset
│   ├── EntitlementExplorerView.swift
│   ├── Components.swift
│   └── Experiments/                 one run view per experiment
├── Shared/
│   ├── Models/              experiment model, status system, checks, explanations
│   ├── ExperimentRegistry/  all experiment descriptors
│   ├── PermissionSystem/    permission probes (never prompt) and live availability
│   ├── CapabilitySystem/    device scanner, capability registry, provisioning inspector
│   └── Services/            one service per experiment family
├── WatchApp/                watchOS lab
└── Widget/                  WidgetKit extension
scripts/generate-app-icons.py   renders all app icons and tvOS brand assets
docs/tasks/                     task briefs and reports
```

Adding an experiment: add a descriptor to `ExperimentRegistry` (with a live `evaluate` check from `ExperimentAvailability`), a service in `Shared/Services`, a run view in `UI/Experiments` routed in `ExperimentRunView`, and, if needed, a "Why doesn't this work?" entry. The iOS target picks up new files automatically; the macOS, tvOS and watchOS targets list their sources explicitly in the project file.

## Tests

Run the `AppleToolbox iOS` scheme's tests (⌘U): Swift Testing unit tests in `AppleToolboxTests` and XCUITest smoke tests in `AppleToolboxUITests`.

## Issues

Bugs and planned work are tracked as GitHub issues in this repository.
