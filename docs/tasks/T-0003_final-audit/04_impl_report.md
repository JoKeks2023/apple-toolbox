# Implementation report

Work was done by the lead session plus five agents in their own worktrees. Their commits were cherry-picked onto `main`; conflicts in `project.pbxproj` were additions on both sides and were resolved by keeping both.

| Commit | Subject |
| --- | --- |
| a08c4e6 | Sanitize Multipeer peer names and track peers by ID |
| 0d94ecc | Keep an experiment running while its full-screen cover shows |
| 4db238b | Add the Group Activities entitlement to the Mac app |
| 9430761 | Clean up the audio session and tone graph after a failed start |
| d0c3440 | Run every watchOS experiment on Apple Watch |
| e580b29 | Add WatchConnectivity transfers and paired-watch state |
| 3d02dc5 | Add a notification service extension for remote pushes |
| 3444269 | Add an AutoFill credential provider extension |
| 6fe9238 | Add a local packet tunnel and a Personal VPN flow |
| 072fa43 | Run Core ML predictions and train image and sound models |
| d4ee61f | Add Core AI and Foundation Models image input experiments |
| 0b16730 | Build the notification service helpers for watchOS too |
| 9b2fe36 | Add ShazamKit custom catalogs and audio recording to file |
| df18781 | Add Vision object detection and ARKit world maps and object scans |
| 350689f | Discover unpaired accessories and set up with a payload |
| d82163c | Read MIFARE and ISO 15693 blocks, configure Wi-Fi accessories |
| a4b28b3 | Create Wallet passes in every style and watch the library |
| 14be869 | Report Region Restricted and drop unused statuses |
| 4f70bc7 | Add an Apple TV layout, controller haptics and tvOS Multipeer |
| 02e65a3 | Close scanner, motion, Wi-Fi, UWB and App Intents gaps |

**Runtime audit fixes:** #102 Multipeer names, #103 full-screen covers, #104 macOS SharePlay entitlement, #105 audio cleanup. The audit found no high-confidence crash; the long Mac name was the only reachable crash.

**New targets:** Notification Service, Credential Provider and Packet Tunnel.

**Experiments:** 82 (was 78):
- New experiments: `foundation-models-image`, `core-ai`, `homekit-accessory-browser` and `wireless-accessory-configuration`.
- Multipeer now also runs on tvOS.

**Deviations from the issues:**
- #87 removes the `developmentOnly` and `simulatorOnly` statuses because no experiment fits them. SPEC §6 still lists them.
- Region Restricted uses the device region. That only approximates the real rules: the Apple Account region for HCE, the payment provider for Tap to Pay.
- The Tap to Pay country list is a snapshot and may go stale.

**Entitlements added:**
- iOS app:
  - `com.apple.developer.matter.allow-setup-payload`
  - `com.apple.external-accessory.wireless-configuration`
  - AutoFill Credential Provider
  - Network Extension (`packet-tunnel-provider`)
  - `vpn.api` (`allow-vpn`)
- Mac app: `group-session`
- Watch app: HomeKit and Sign in with Apple

All are self-service for a paid team; they have to be enabled on the App IDs, or automatic signing does it on the first device build.
