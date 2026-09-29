# Implementation report

One commit per issue on `main` (#40 and #60 share the Maps-lab commit, as the issue for the deprecated API was fixed where the code was rewritten). Work was split into category packages done by agents in separate worktrees and integrated by cherry-pick; #42, #43, #81, #82 and #83 were done directly.

| Issue | Commit | Subject |
| --- | --- | --- |
| #38 | 2685fab | Sandbox the Mac app and give it entitlements and versions |
| #39 | d1f770c | Make read-only experiment rows focusable on tvOS |
| #40 | 576e80d | Add a Maps lab and drop the deprecated MKMapItem.placemark |
| #42 | 8e981b0 | Split the experiment catalog and run routing per category |
| #43 | 512a4c9 | Show required Apple programs and report Device Only in the Simulator |
| #44 | 70fcc8b | Turn the CryptoKit experiment into a Credential / Crypto Lab |
| #45 | 82d1503 | Show LocalAuthentication policies, domain state and rights |
| #46 | 1424b15 | Add Keychain Sharing, security key and credential provider labs |
| #47 | 74e3b18 | Represent advanced Wallet credentials with their Apple programs |
| #48 | a1068cf | Add an NFC Inspector for ISO 7816, ISO 15693, FeliCa and MIFARE |
| #49 | 946b270 | Add NFC card emulation with CardSession eligibility checks |
| #50 | d437cd4 | Add the Wallet pass library, add-pass sheet and Apple Pay request |
| #51 | 7b9ba84 | Add a GATT explorer to the Core Bluetooth experiment |
| #52 | 39c8491 | Add Bluetooth Peripheral Mode with a custom GATT service |
| #53 | 2241c45 | Add AccessorySetupKit, External Accessory and Bluetooth MIDI experiments |
| #54 | 30e86ce | Turn the network path experiment into a Network Inspector |
| #55 | 9a6a9c9 | Add a Wi-Fi and network capabilities experiment |
| #56 | 9bafd3b | Show Nearby Interaction distance and direction on a live radar |
| #57 | 935957c | Add a Spatial Link experiment for nearby Apple Toolbox devices |
| #58 | 48189b0 | Add iBeacon ranging and a Location Dashboard |
| #59 | 904fc41 | Add an indoor survey utility on top of IMDF levels |
| #60 | 576e80d | Add a Maps lab and drop the deprecated MKMapItem.placemark |
| #61 | f6fdcbc | Turn HomeKit Discovery into the Home Inspector |
| #62 | f2579a1 | Add a Camera Lab with preview, photo, controls, depth and video |
| #63 | 6afeee7 | Turn Camera & Vision into a Vision Lab with overlays and tracking |
| #64 | c9875d8 | Replace the ARKit status check with an ARKit & RealityKit Lab |
| #65 | 6d6f7a4 | Extend Natural Language with tokens, tags, sentiment, embeddings |
| #66 | 53c097a | Add SpeechAnalyzer live and file transcription |
| #67 | 2e7f82a | Add Create ML on-device training experiment |
| #68 | 3a3118d | Add Foundation Models tool calling and context experiment |
| #69 | c48687e | Turn Audio Input into an Audio Analyzer with tone, effects and FFT |
| #70 | 0da6b82 | Add a Media experiment with Now Playing, remote commands and AirPlay |
| #71 | 5ed57a6 | Add MusicKit catalog search, library, playlists and playback |
| #72 | 3651500 | Turn HealthKit Status into the HealthKit Reader |
| #73 | af87a10 | Expand the notifications experiment and add a content extension |
| #74 | 44ff985 | Add a Live Activities experiment with Dynamic Island views |
| #75 | cbf962a | Add an interactive widget and Control Center controls |
| #76 | 2ed0bc8 | Index experiments in Spotlight and donate Open Experiment intents |
| #77 | f879e25 | Add a Continuity experiment for Handoff, SharePlay and sharing |
| #78 | d71dbc9 | Add watch complications, heart rate and background refresh |
| #79 | ab21241 | Add a Platform category with Metal and Mac Hardware labs |
| #80 | 5fdad88 | Add iPad labs for Apple Pencil, pointer and keyboard, and windows |
| #81 | dc10d9e | Add the Developer Tools Lab and a Diagnostics experiment |
| #82 | 0fe6fd1 | Add a Tools section for the promoted inspectors |
| #83 | 6473964 | Keep the widget timeline provider off the main actor |

## Result

- 71 experiments in 18 categories (was 39 in 14), 56 catalogued capabilities, 8 promoted tools, 7 targets plus 2 test targets.
- New targets: iOS notification content extension, watchOS widget extension (complications); the iOS widget extension gained an interactive widget, Control Center controls and a Live Activity.
- New issue found during integration and fixed: #83 (widget timeline provider isolation).

## Integration notes

- Project-file conflicts were resolved by re-registering each agent's new files with the target membership recorded in its own commit, and by re-applying build-setting changes (macOS sandbox for #38, `NSSupportsLiveActivities` for #74, watch app settings for #78) that a project-file merge would otherwise drop.
- Files emptied from both sides by parallel moves were deleted and removed from the project (`ConnectivityExperimentServices.swift`, `HealthNotificationServices.swift`, `MediaExperimentServices.swift`).
- Agent decisions kept deliberately: AccessorySetupKit Info.plist keys not declared (they would restrict Core Bluetooth to ASK-paired accessories); HCE entitlement not added (Apple-managed, `CardSession()` requires it); Health Records keys not added (App Review clinical requirement); `UIBackgroundModes` audio and `bluetooth-peripheral` not added (App Review implications).
