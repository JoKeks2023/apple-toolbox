# Constraints

- No `xcodebuild build` and no simulators (8 GB M1); static checks only. Runtime stays unverified (#41).
- Real public APIs only, honest boundaries, and Pickers for enumerable input (SPEC and global rules).
- Signing comes from `Config/Signing.xcconfig` / `Config/Local.xcconfig`. Nothing personal is hard-coded; use `ToolboxIdentifiers`.
- Swift 6 with MainActor default isolation: framework callbacks off the main thread must be `nonisolated` / `@Sendable`.
- iOS 27 APIs go behind `#available`. Deployment stays iOS/macOS 26.5, tvOS 26.0, watchOS 11.0.
- Agents work in their own worktrees; one commit per issue; push straight to `main`; no CI; no squash.
