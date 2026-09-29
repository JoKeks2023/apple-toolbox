# Scope

| Issue | SPEC | Gap |
| --- | --- | --- |
| #87 | §6 | Statuses OS Unsupported / Region Restricted / Development Only / Simulator Only are never produced |
| #88 | §29 §37 §38 | Watch app runs only 2 of 17 watchOS experiments; no pre-run checks or "Why not" on the watch; no pedometer/altimeter; not independent |
| #89 | §28 §29 §39 | WatchConnectivity is only a ping; no context, user info or file transfer; no paired-watch state |
| #90 | §30 §39 | tvOS mirrors the iPhone UI; controller haptics never played; no iPhone ↔ Apple TV path |
| #91 | §26 | No Notification Service Extension |
| #92 | §8 | No Credential Provider extension |
| #93 | §11 §12 | No Network Extension (packet tunnel, Personal VPN) |
| #94 | §20 | No Core ML inference; Create ML text and tabular only; no model export |
| #95 | §21 | No Core AI; no Foundation Models image input (iOS 27 SDK); execution label hard-coded |
| #96 | §22 | No ShazamKit custom catalog or signature generator; no recording to file |
| #97 | §17 | No HMAccessoryBrowser; Matter without a setup payload |
| #98 | §18 §19 | No Vision object detection; no ARWorldMap; object scanning only explained |
| #99 | §9 §10 §12 | No MIFARE commands or ISO 15693 block reads; no Wireless Accessory Configuration |
| #100 | §25 | Pass creator is generic-only; no locations/beacons/web service/NFC fields; no library observer |
| #101 | §7 §13 §15 §23 §27 | Scanner Matter/MusicKit, raw IMU, CoreWLAN on macOS, NI world transform, App Intent schema |
| (bugs) | — | Runtime traps from audit 2, one issue each |

**Out of scope:**
- §4 folder names (cosmetic)
- #41 device runs (the owner declined local builds for now)
- AccessorySetupKit variant and UIBackgroundModes (owner decisions)
