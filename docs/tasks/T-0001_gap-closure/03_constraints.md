# Constraints

- **Hardware:** M1 with 8 GB RAM. No simulators, no full Xcode builds. Only `swiftc -typecheck`, `actool`, `plutil`, `xcodebuild -list/-showBuildSettings`.
- **No CI** on GitHub (owner decision).
- **Philosophy (SPEC.md):** only public APIs, never fake results, never bypass entitlements; unsupported states are explained.
- **Git:** push directly to `main`; one commit per issue; no squash merges; agents work in separate worktrees and their commits are cherry-picked onto `main`.
- **UI rule:** enumerable choices use a Picker (dropdown), not free text.
- **Signing:** new capabilities (HomeKit, HealthKit, NFC, App Groups, Sign in with Apple, …) must be enabled for the App IDs of the signing team (set in `Config/Local.xcconfig`, see `Config/Signing.xcconfig`); automatic signing is expected to register them on the first device build.
