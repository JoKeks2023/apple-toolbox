# Done when

- Every issue #87–#101 plus the runtime-bug issues is closed by exactly one commit on `main` (`Fixes #N`).
- `typecheck.py` passes with 0 errors and 0 warnings for every config: ios, iosdevice, macos, tvos, watchos, widget, watchwidget, notifcontent, every new extension, and the tests.
- `plutil -lint`, `actool`, `xcodebuild -list` and `-showBuildSettings` are clean for new targets.
- The README catalog is regenerated, and `05_validation_report.md` states plainly what is statically verified and what still needs #41.
