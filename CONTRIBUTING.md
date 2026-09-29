# Contributing to Apple Toolbox

Thanks for helping answer "What can my Apple devices actually do?". Bug reports from real devices are just as valuable as new experiments — much of the app can only be exercised on hardware.

## Ground rules

- **Real public APIs only.** An experiment calls Apple's framework on the current device and shows its real result or error. No simulated data, no private API, no entitlement workarounds.
- **Explain the boundary.** If something needs hardware, a permission, an entitlement, an Apple program or another platform, the experiment says so through its live status and a "Why doesn't this work?" entry instead of hiding it.
- **Never prompt on open.** Status checks read state without triggering permission dialogs; prompts only come from an explicit button.
- **Pickers for choices.** Enumerable options (modes, types, presets) use a `Picker`; free-text fields are only for genuinely free input.
- **Swift 6 concurrency.** Everything is `MainActor` by default. Framework callbacks that run on background queues must be `@Sendable` (or `nonisolated`) and hop back to the main actor.

## Adding an experiment

1. Add an `ExperimentDescriptor` to the category's `AppleToolbox/Shared/ExperimentRegistry/Registry+<Category>.swift`: frameworks, platforms, requirements, a live `evaluate` check, and optionally a use case, "Why doesn't this work?" texts and required Apple programs.
2. Put the framework code in a service under `AppleToolbox/Shared/Services/` (`@MainActor final class …: ObservableObject`). Services with live sessions conform to `StoppableExperiment` so they stop when the user leaves.
3. Add a run view under `AppleToolbox/UI/Experiments/` and route it in `AppleToolbox/UI/Routes/<Category>Routes.swift`.
4. The iOS target picks up new files automatically. Add them to the macOS, tvOS and (if the registry needs them) watchOS targets in Xcode.
5. Add unit tests for pure logic in `AppleToolboxTests/`, and run `python3 scripts/generate-readme-catalog.py` to refresh the catalog in the README.

## Pull requests

- Open or reference an issue first for larger changes.
- Keep one topic per pull request and describe what you verified — on which device, OS and platform — and what you could not verify.
- Make sure every scheme still builds and the tests pass (⌘U on `AppleToolbox iOS`).
