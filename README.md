# Joris Apple Toolbox

A native multi-platform lab app that answers one question: **What can my Apple devices actually do?**
Every experiment runs a real public Apple API on the current device and shows why something does or does not work, without faking results or bypassing entitlements.

The full product vision lives in [`SPEC.md`](SPEC.md).

## Targets

| Scheme | Platform | Notes |
| --- | --- | --- |
| `AppleToolbox iOS` | iPhone, iPad | Main app, embeds the widget extension |
| `AppleToolbox macOS` | Mac | Same shared sources as iOS |
| `AppleToolbox tvOS` | Apple TV | Same shared sources, tvOS-specific availability |
| `AppleToolbox watchOS` | Apple Watch | Watch-specific UI in `AppleToolbox/WatchApp` |
| `AppleToolbox Widget` | iOS widget extension | `AppleToolbox/Widget` |

Requires Xcode 26 or newer. Many experiments (NFC, UWB, LiDAR, HealthKit, HomeKit, camera, motion) only produce meaningful results on a physical device, and some need capabilities enabled for the signing team.

## Structure

```text
AppleToolbox/
├── AppleToolboxApp.swift, ContentView.swift   app entry and navigation
├── Shared/
│   ├── Models/                experiment model and status system
│   ├── ExperimentRegistry/    all experiment descriptors
│   ├── CapabilitySystem/      device capability detection
│   └── Services/              one service per experiment family
├── WatchApp/                  watchOS entry point
└── Widget/                    WidgetKit extension
```

Adding an experiment means adding a descriptor to `ExperimentRegistry`, a service in `Shared/Services`, and a run view. The iOS target picks up new files automatically; the macOS, tvOS and watchOS targets list their sources explicitly in the project file.

## Issues

Bugs and planned work are tracked as GitHub issues in this repository.
