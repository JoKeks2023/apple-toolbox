# Done when

- Issues #38, #39, #40 and #42–#82 are closed by exactly one commit each on `main` (`Fixes #N`).
- The final `main` passes the strict static check: `swiftc -emit-module` in Swift 6 for iOS (Simulator and device SDK), macOS, tvOS, watchOS, the widget, the notification content extension, the watch widget extension and the unit tests; plus UI tests, `plutil`, `actool`, `xcodebuild -list`/`-showBuildSettings`.
- The validation report lists what is unverified at runtime and every capability the App IDs need.
