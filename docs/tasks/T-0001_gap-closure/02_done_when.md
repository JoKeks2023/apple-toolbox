# Done when

- Every issue #1–#37 is closed by exactly one commit on `main` whose message contains `Fixes #N`.
- `typecheck.py ios macos tvos watchos widget tests` passes for the final `main` (lightweight `swiftc -typecheck` per SDK, file lists taken from `project.pbxproj`).
- `xcodebuild -list` parses the project; `plutil -lint` passes for plists/entitlements; `actool` compiles the asset catalog for iOS, macOS, tvOS and watchOS.
- The validation report lists what could **not** be verified at runtime.
