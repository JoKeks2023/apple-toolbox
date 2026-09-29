<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/app-icon-dark.png">
    <img src="docs/assets/app-icon.png" width="128" height="128" alt="Apple Toolbox app icon">
  </picture>
</p>

<h1 align="center">Apple Toolbox</h1>

<p align="center"><a href="https://jokeks2023.github.io/apple-toolbox/"><b>jokeks2023.github.io/apple-toolbox</b></a></p>

<p align="center">
  <b>What can my Apple devices actually do?</b><br>
  <i>Let's try it.</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftUI-native-0A84FF?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/platforms-iOS%20%C2%B7%20iPadOS%20%C2%B7%20macOS%20%C2%B7%20watchOS%20%C2%B7%20tvOS-lightgrey?logo=apple" alt="Platforms">
  <img src="https://img.shields.io/badge/Xcode-26%2B-147EFB?logo=xcode&logoColor=white" alt="Xcode 26+">
  <img src="https://img.shields.io/badge/experiments-82-8E44AD" alt="Experiments">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-34C759" alt="MIT License"></a>
</p>

Apple Toolbox is a lab app **for developers** who want to see what their iPhone, iPad, Mac, Apple Watch and Apple TV can actually do — and what it would take to build it into their own app. It turns Apple's frameworks, sensors, radios and capabilities into **82 experiments** you can run on your own devices — from CryptoKit and the Secure Enclave to NFC, UWB, HomeKit, ARKit, Foundation Models and Live Activities.

Every experiment calls the **real public API** on the device in your hand. Nothing is simulated, nothing is faked, and no entitlement is bypassed. When something doesn't work, the app tells you exactly why: missing hardware, a permission you declined, an entitlement Apple has to approve, or a platform that simply doesn't have the framework.

## Highlights

- **How to implement it.** Every experiment shows the minimal Swift code for its core API, the Info.plist keys, the entitlements and the capabilities to enable, ready to copy. Every snippet typechecks against the SDK (`scripts/check-guide-snippets.py`).
- **Real APIs, honest results.** Every run shows live output from Apple's frameworks, including the real errors.
- **"Why doesn't this work?"** Each unavailable experiment explains the reason, what it needs and the next step — from "this iPhone has no LiDAR" to "this capability needs Apple's approval".
- **Pre-run checks.** Platform, OS, hardware, permissions, entitlements and Apple programs are checked before you start, without ever triggering a permission prompt.
- **Tools, not just demos.** Mature experiments grew into everyday utilities such as an NFC Inspector, a Network Inspector and an Audio Analyzer.
- **Entitlement Explorer.** 57 Apple capabilities with their entitlement keys, how to get them, and whether this build is actually provisioned for them — read from the app's own provisioning profile.
- **Device Scanner.** What your device exposes through public APIs: chip, sensors, cameras, radios, display, Apple Intelligence and more.
- **Every Apple platform.** One Swift 6 codebase for iOS, iPadOS, macOS, watchOS and tvOS, with widgets, a Live Activity, Control Center controls, watch complications and a notification content extension.

## Tools

Experiments promoted into utilities you can keep using. They sit at the top of the sidebar.

<!-- tools:start -->
| Tool | Grew out of | What it does |
| --- | --- | --- |
| **Device Scanner** | “List a few device facts” | What this device can do: hardware, sensors, cameras, radios and Apple features. |
| **NFC Inspector** | “Read NFC tag” | Identify ISO 7816, ISO 15693, FeliCa and MIFARE tags, send APDUs, read and write NDEF. |
| **Network Inspector** | “Show current connection” | Path, interfaces, TCP/UDP/TLS connections, an echo listener and Bonjour browsing. |
| **Location Dashboard** | “Show coordinates” | Record a track with speed, altitude and accuracy charts and export it as GPX or GeoJSON. |
| **Audio Analyzer** | “Play sine wave” | Tone generator, effects, routes and latency, and a live spectrum of the microphone. |
| **Home Inspector** | “Discover accessories” | Browse accessories and characteristics, write values, run scenes and list automations. |
| **Indoor Survey** | “Survey experiment” | Record survey points and paths on an IMDF level with an accuracy heatmap and GeoJSON export. |
| **Crypto Lab** | “Generate key” | Hash, encrypt, agree on keys, sign, HPKE and key import/export with round-trip checks. |
<!-- tools:end -->

## Experiment catalog

Grouped the way the app's sidebar is. Generated from the source with `scripts/generate-readme-catalog.py`.

<!-- catalog:start -->
<details>
<summary><b>Security</b> · 10 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **LocalAuthentication** | Inspect the biometry type, every LocalAuthentication policy with its live result and error code, and enrolment changes through the domain state; evaluate a policy with a reuse window and authorize LARight and LAPersistedRight. | iPhone · iPad · Mac |
| **CryptoKit Lab** | Hash, authenticate, encrypt, agree on keys, sign and seal with HPKE on your own text, and generate, export and import keys. Every run checks the round trip and shows that tampered data is rejected. | iPhone · iPad · Mac · Watch · TV |
| **Keychain** | Write, read, and delete a generic password, and store one behind SecAccessControl so reading it needs Face ID, Touch ID, or the passcode. | iPhone · iPad · Mac · Watch · TV |
| **Secure Enclave** | Create a non-exportable signing key, keep it across runs through its Keychain blob, sign and verify, and delete it again. | iPhone · iPad · Mac · Watch |
| **App Attest & DeviceCheck** | Generate and attest a Secure Enclave key, sign a sample payload with an assertion, and request a DeviceCheck token. The challenge is local; server-side verification is out of scope. | iPhone · iPad · Mac · Watch · TV |
| **Passkeys** | Send a real passkey registration or assertion request for a relying party you enter and inspect the credential or the system's error. Challenges are local random bytes. | iPhone · iPad · Mac · TV |
| **Sign in with Apple** | Run the real Sign in with Apple flow, inspect the returned credential (shortened identifier, real-user status, token and code sizes) and query its credential state. | iPhone · iPad · Mac · Watch · TV |
| **Keychain Sharing & iCloud Keychain** | Save, read and delete an item in the app's own, a team-shared or the App Group keychain access group, list every item the app can see per group, and mark items as iCloud Keychain synchronizable. | iPhone · iPad · Mac · TV |
| **Security Keys (WebAuthn)** | Register and use a FIDO2 security key over USB, NFC or Lightning with ASAuthorizationSecurityKeyPublicKeyCredentialProvider for a relying party you enter, with user verification, attestation and discoverable-credential choices. Challenges are local random bytes. | iPhone · iPad · Mac |
| **AutoFill Credential Provider** | A real AutoFill credential provider: the iOS app bundles an ASCredentialProviderViewController extension that fills demo passwords and creates and signs demo passkeys from the App Group vault. The app shows the live ASCredentialIdentityStore state, saves and removes identities, and asks to be turned on. | iPhone · iPad · Mac |

</details>

<details>
<summary><b>Location</b> · 3 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Core Location** | Inspect live coordinates, precise vs. approximate accuracy, heading and floor, and monitor a region, visits, and significant changes around you. | iPhone · iPad · Mac · Watch |
| **iBeacon Ranging** | Range iBeacons for a proximity UUID you enter, optionally narrowed by major and minor, with CLBeaconIdentityConstraint, and watch proximity, estimated distance and RSSI update live. | iPhone · iPad · Mac |
| **Location Dashboard** | Record a track from CLLocationUpdate.liveUpdates, draw it on a map, chart speed, altitude and accuracy over time, summarize the session and export the track as GPX or GeoJSON. | iPhone · iPad · Mac |

</details>

<details>
<summary><b>Sensors</b> · 1 experiment</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Core Motion** | Stream device motion with attitude and the calibrated magnetic field, count steps with the pedometer, and read barometric altitude. | iPhone · iPad · Watch |

</details>

<details>
<summary><b>Input</b> · 1 experiment</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Game Controller** | List connected game controllers and the Siri Remote with profile, battery, and haptics, discover wireless controllers, and watch live button, trigger, and stick input. | iPhone · iPad · Mac · TV |

</details>

<details>
<summary><b>Connectivity</b> · 11 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Core Bluetooth** | Scan for nearby Bluetooth Low Energy peripherals, connect to one, and explore its GATT database: services, characteristics and descriptors, reads, writes, notifications, RSSI and maximum write length. | iPhone · iPad · Mac · Watch |
| **Bluetooth Peripheral Mode** | Publish a custom Apple Toolbox GATT service with CBPeripheralManager, advertise it, answer read and write requests, and send notifications to subscribed centrals. | iPhone · iPad · Mac |
| **AccessorySetupKit** | Activate an ASAccessorySession, list the accessories authorized for Apple Toolbox, and show the system accessory picker for a declared Bluetooth accessory with the real session events and errors. | iPhone · iPad |
| **External Accessory (MFi)** | List MFi accessories connected over Lightning, USB-C or Bluetooth through EAAccessoryManager and log connect and disconnect notifications. | iPhone · iPad · Mac · TV |
| **Wireless Accessory Configuration** | Search for Wi-Fi accessories in setup mode with EAWiFiUnconfiguredAccessoryBrowser, see their name, model, setup SSID and features, and hand one to Apple's configuration sheet to join your network. | iPhone · iPad |
| **Bluetooth MIDI** | List Core MIDI sources and destinations, pair Bluetooth LE MIDI devices with Apple's pairing UI, and decode incoming MIDI messages live. | iPhone · iPad · Mac |
| **MultipeerConnectivity** | Discover nearby Apple Toolbox devices, connect them automatically, and exchange live messages over a local peer-to-peer session. | iPhone · iPad · Mac · TV |
| **WatchConnectivity** | Link iPhone and Apple Watch with WatchConnectivity: live reachability, paired-watch and complication state, ping messages, application context, queued user info with delivery confirmation, file transfers with metadata, and complication user info. | iPhone · Watch |
| **Continuity** | Hand off the open experiment to your other devices with NSUserActivity, explore experiments together over SharePlay, share an experiment summary with ShareLink and AirDrop, and inspect the Universal Links boundary of Associated Domains. | iPhone · iPad · Mac |
| **Nearby Interaction / UWB** | Range with a nearby iPhone over Ultra Wideband and see distance and direction live on a radar, with camera assistance, extended distance, convergence coaching and the accessory session boundary. | iPhone · iPad · Watch |
| **Spatial Link** | One live view of nearby Apple Toolbox devices: MultipeerConnectivity discovery, UWB distance and direction where both devices support it, each device's network path and message latency, plus the paired Apple Watch over WatchConnectivity. | iPhone · iPad · Mac |

</details>

<details>
<summary><b>Networking</b> · 2 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Network Inspector** | Inspect the live network path, open TCP, UDP or TLS connections with NWConnection, run an echo server with NWListener, and browse Bonjour services with NWBrowser. | iPhone · iPad · Mac · TV |
| **Wi-Fi & Network Capabilities** | Read the current Wi-Fi network, add a hotspot configuration, probe the local network permission, check the Multicast, Multipath and 5G slicing boundaries, and on iOS run a local packet tunnel (NEPacketTunnelProvider, test range only) and configure a Personal VPN (IKEv2) with real API calls. | iPhone · iPad · Mac |

</details>

<details>
<summary><b>NFC</b> · 3 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Core NFC** | Read NDEF tags and inspect their records with a real NFC reader session. | iPhone · iPad |
| **NFC Inspector** | Inspect ISO 7816, ISO 15693, FeliCa and MIFARE tags with an NFC tag reader session: identifiers and per-type metadata, a SELECT APDU with its status word, NDEF status and records, NDEF writing with optional locking, and a history of the last tags. | iPhone · iPad |
| **NFC Card Emulation** | Check CardSession support and eligibility, hold a presentment intent, and emulate an ISO 7816 card that answers a reader's SELECT for a demo AID, with every session lifecycle event and APDU logged. | iPhone |

</details>

<details>
<summary><b>Home</b> · 3 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Home Inspector** | Browse homes, rooms, accessories, services and characteristics with their types, properties, units and ranges; read and write values, follow live changes, run scenes, and list automations with their events and conditions. | iPhone · iPad · Watch · TV |
| **Matter Accessory Setup** | Start Apple Home's accessory setup flow (HMAccessorySetupManager) to commission a Matter or HomeKit accessory into a home, either letting Apple Home scan the code or passing a scanned or entered setup payload (MTRSetupPayload / HMAccessorySetupPayload), then inspect the returned identifiers or the real error. | iPhone · iPad |
| **Unpaired Accessory Discovery** | Search for HomeKit accessories that are in pairing mode and not yet added to any home with HMAccessoryBrowser, and watch them appear and disappear live. | iPhone · iPad |

</details>

<details>
<summary><b>Camera</b> · 2 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Camera Lab** | Live AVCaptureVideoPreviewLayer preview of any discovered camera, photo capture (HEIC/JPEG, flash) with EXIF metadata and depth data, focus, exposure bias, zoom, torch and video HDR controls, and short video recording with AVCaptureMovieFileOutput. | iPhone · iPad · Mac |
| **Vision Lab** | Run Vision's Swift requests on live camera frames or a picked photo: barcodes, face rectangles and landmarks, human body and hand pose, image classification, document segmentation, text recognition, object tracking, animal recognition, human rectangles and objectness-based saliency, with boxes, confidences and the observations drawn over the analyzed image. | iPhone · iPad · Mac |

</details>

<details>
<summary><b>Spatial</b> · 2 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **ARKit & RealityKit Lab** | Run world, face, body or image tracking in a RealityKit ARView: plane detection, raycast placement of box and sphere entities with materials, physics and animation, the live anchor list, scene reconstruction mesh and occlusion on LiDAR devices, tracking state, frame statistics and a configuration support matrix; save and restore an ARWorldMap with its anchors, and scan an ARReferenceObject with ARObjectScanningConfiguration to detect it again in world tracking. | iPhone · iPad |
| **RoomPlan** | Scan a room with RoomCaptureView on a LiDAR device, summarize walls, doors, windows, openings, objects and overall dimensions, and share the result as a USDZ model. | iPhone · iPad |

</details>

<details>
<summary><b>Audio</b> · 5 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Audio Analyzer** | Generate sine, square, sawtooth or noise tones with AVAudioSourceNode through an EQ, distortion, delay and reverb chain, inspect the output route, sample rate, IO buffer and latency, follow route changes, analyze the microphone with a live vDSP FFT spectrum and RMS/peak meter, and record it to an AAC, Apple Lossless, WAV or CAF file with AVAudioRecorder, play it back and inspect its size, format and duration. | iPhone · iPad · Mac |
| **Sound Analysis** | Classify live microphone audio with Apple's built-in sound classifier and watch the top three labels and their confidence update in real time. | iPhone · iPad · Mac |
| **Media & Now Playing** | Play Apple's public BipBop HLS stream with AVKit, publish Now Playing info with MPNowPlayingInfoCenter, receive play, pause, skip and scrub commands through MPRemoteCommandCenter, choose an AirPlay route with AVRoutePickerView, and log route changes. | iPhone · iPad · Mac · TV |
| **MusicKit** | Authorize MusicKit, read the Apple Music subscription and storefront, search the catalog for songs, albums, artists and playlists, read your library and its playlists, and play or queue items with ApplicationMusicPlayer where the account allows it. | iPhone · iPad · Mac · Watch · TV |
| **ShazamKit** | Listen through the microphone with SHManagedSession and identify the playing song in the Shazam catalog: title, artist, genres and Apple Music links, or the real no-match or error result. Build a custom catalog from microphone signatures (SHSignatureGenerator, SHCustomCatalog) and match against it with SHSession(catalog:). | iPhone · iPad · Mac |

</details>

<details>
<summary><b>AI</b> · 10 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Natural Language** | Identify the language, tokenize by word, sentence or paragraph, tag lexical classes and named entities, score sentiment, lemmatize, and compare words or sentences with the bundled NLEmbedding models, all on device. | iPhone · iPad · Mac · Watch · TV |
| **Foundation Models** | Read the on-device model's availability and concrete reason, stream a reply to your own prompt, and generate a typed @Generable result with guided generation. | iPhone · iPad · Mac |
| **Foundation Models Tools & Context** | Hold a multi-turn conversation in one LanguageModelSession whose model can call two app tools (device capabilities from the scanner, experiment catalog search), inspect the transcript, count tokens against the context size, and see context-overflow, guardrail and language errors as the framework reports them. | iPhone · iPad · Mac |
| **Foundation Models Image Input** | Attach a photo to a prompt with the iOS 27 Attachment / Transcript.ImageAttachment API, ask the on-device model about it, and let it call the Vision tools BarcodeReaderTool and OCRTool; every feature states whether it runs on device or would need internet and Private Cloud Compute. | iPhone · iPad · Mac |
| **Core AI** | List the compute unit kinds and device architecture Core AI reports, import a .aimodel package, read its metadata and operation mix with AIModelAsset, specialize it with a CPU, GPU or Neural Engine preference through AIModelCache, and time an InferenceFunction run with synthetic NDArray inputs. | iPhone · iPad · Mac |
| **Speech Recognition** | Use the real speech recognizer and microphone to transcribe live spoken words. | iPhone · iPad · Mac |
| **SpeechAnalyzer** | Transcribe the microphone live or a picked audio file with SpeechAnalyzer and SpeechTranscriber, watch volatile results turn into finalized text, and manage the locale's model assets with AssetInventory. | iPhone · iPad · Mac |
| **Core ML** | List the CPU, GPU and Neural Engine Core ML can use, compile a model trained on this device with Create ML or an imported .mlmodel, .mlpackage or .mlmodelc, inspect it, then run real predictions and compare load and prediction times for each compute-unit setting with MLComputePlan's device choice. | iPhone · iPad · Mac |
| **Create ML** | Train a text classifier or tabular regressor from a CSV, or an image or sound classifier from your own photos and audio files grouped by label, on this device with the Create ML framework; compare training and validation metrics, run the new model on your own input and export the .mlmodel. | iPhone · iPad · Mac |
| **Translation** | Pick a language pair from the languages the system supports, check whether it is installed, supported or unsupported, and translate your own text with a real TranslationSession. | iPhone · iPad · Mac |

</details>

<details>
<summary><b>Maps</b> · 4 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **MapKit Search** | Search real map data for places and inspect returned names and coordinates. | iPhone · iPad · Mac · TV |
| **Indoor Maps / IMDF** | Import an unzipped IMDF archive folder or individual GeoJSON files, decode every feature type with MKGeoJSONDecoder, count features per type and level, and draw the selected level's units and openings on a map. | iPhone · iPad · Mac |
| **Indoor Survey** | Survey an imported IMDF level: record reference points and walking paths with Core Location accuracy, floor, confidence and notes, compare reference and measured positions, view an accuracy heatmap, save surveys as JSON in the app's Documents folder (Application Support on Mac) and export them as GeoJSON. | iPhone · iPad · Mac |
| **Maps Lab** | Geocode addresses with MKGeocodingRequest, reverse geocode map taps with MKReverseGeocodingRequest, route with ETA for driving, walking, cycling and transit, preview Look Around, and switch map styles, 3D elevation, points of interest, annotations, overlays and your position. | iPhone · iPad · Mac · TV |

</details>

<details>
<summary><b>Wallet</b> · 11 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Wallet & PassKit** | List the passes PassKit shows this app and add a signed .pkpass you choose through the system's add-pass sheet. | iPhone · iPad · Mac |
| **Apple Pay** | Check canMakePayments per payment network, render PKPaymentButton types and styles, and run a real PKPaymentRequest through the payment sheet with a clearly labelled placeholder merchant identifier. | iPhone · iPad · Mac |
| **Wallet Pass Creator** | Create and export a real pass.json draft in any pass style (boarding pass with transit type, coupon, event ticket, store card, generic) with optional locations, iBeacons and relevant date, and watch PKPassLibraryDidChange live. An installable pass still requires Apple signing credentials; webServiceURL and NFC need a server and an Apple NFC certificate. | iPhone · iPad · Mac |
| **Secure Element Passes** | Query the Secure Element passes PassKit shows this app on this device and paired devices, with their activation state, plus the issuer entitlements and NFC & SE Platform eligibility that gate advanced Wallet credentials. | iPhone · iPad · Mac |
| **Corporate Badge** | Employee badges in Apple Wallet that open doors, turnstiles and elevators with a tap. Shown with its Apple program requirements. | iPhone |
| **Access Keys** | Keys for residential buildings, offices, gyms and campuses, stored in the Secure Element as Wallet access passes. Shown with its Apple program requirements. | iPhone |
| **Home Key** | An NFC key for Home Key compatible smart locks, created by the Apple Home app and kept in Wallet. Shown with its Apple program requirements. | iPhone |
| **Car Key** | Digital car keys (CCC Digital Key) in the Secure Element that unlock and start supported vehicles and can be shared. Shown with its Apple program requirements. | iPhone |
| **Student ID** | Contactless student IDs in Wallet for campus buildings, dining and payments at participating schools. Shown with its Apple program requirements. | iPhone |
| **Hotel Key** | Room keys in Wallet from participating hotels, valid from check-in to check-out and shareable with other guests. Shown with its Apple program requirements. | iPhone |
| **Tap to Pay on iPhone** | Accept contactless cards and Apple Pay on iPhone without extra hardware, through a payment service provider. Shown with its Apple program requirements. | iPhone |

</details>

<details>
<summary><b>Health</b> · 1 experiment</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **HealthKit Reader** | Request read access for a chosen set of Health data types, then read recent activity, heart, sleep, workout, respiratory, mobility and environmental samples and daily step totals; run an observer query with background delivery and see the Health Records boundary. | iPhone · iPad · Watch |

</details>

<details>
<summary><b>System</b> · 5 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **App Intents** | Run the app's App Intents in-process (status, SHA-256 hash, capability summary, open a category or experiment) and list the App Shortcuts registered for Siri, Spotlight, and Shortcuts. | iPhone · iPad · Mac · Watch · TV |
| **Spotlight & Siri** | Index every experiment in Spotlight as an App Intents IndexedEntity, open a tapped result straight into its experiment, and donate the Open Experiment intent whenever an experiment opens so Siri Suggestions can learn from it. | iPhone · iPad · Mac |
| **WidgetKit** | Share the last opened experiment with the Home Screen and Lock Screen widget through an App Group, run App Intents from an interactive widget and from Control Center controls in the widget's process, list what is placed and reload each kind. The interactive widget adapts to StandBy. | iPhone · iPad |
| **Live Activities** | Start, update and end a real Live Activity with ActivityKit: a measurement run that the widget extension draws on the Lock Screen and in the Dynamic Island (compact, minimal, expanded), updated by the app with real battery, thermal and Low Power readings. | iPhone · iPad |
| **UserNotifications** | Schedule real local notifications with categories and actions (text input, authentication-required, destructive), interruption levels, a runtime-rendered image attachment, threads and badges; log every delegate callback, draw one category with a notification content extension, register for APNs, rewrite remote pushes with a notification service extension (title marker, downloaded attachment) and probe the time-sensitive, critical-alert and communication boundaries. | iPhone · iPad · Mac · Watch · TV |

</details>

<details>
<summary><b>Platform</b> · 5 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Metal** | Inspect the system Metal GPU (architecture, GPU families, unified memory, recommended working set, ray tracing, threadgroup limits, argument buffer tier), then compile a compute kernel from source at runtime that doubles an array on the GPU and verify every value. | iPhone · iPad · Mac · TV |
| **Mac Hardware** | List Core Audio devices with transport, channels and sample rates, cameras including Continuity Camera, mounted volumes with capacity, APFS, encryption and case sensitivity, and connected displays with resolution, refresh rate and EDR headroom. Public APIs only, no IOKit. | Mac |
| **Apple Pencil** | Draw on a PencilKit canvas with the tool picker and read every touch live: force, altitude, azimuth and barrel roll, coalesced and predicted touches, Pencil hover distance and tilt, and double-tap and squeeze with the actions chosen in Settings. | iPad |
| **Pointer & Keyboard** | Track hover location with onContinuousHover, try hover effects (pointer styles on the Mac), read hardware key presses and modifier state with onKeyPress (onModifierKeysChanged on the Mac), and compare them with raw GCKeyboard and GCMouse input. | iPhone · iPad · Mac |
| **Windows & Displays** | Follow the window scene live: size classes, window and screen size, orientation, size restrictions, open sessions and the screens scenes are on (resolution, refresh rate, EDR, mirroring), and open a second window with openWindow. | iPhone · iPad |

</details>

<details>
<summary><b>Developer</b> · 3 experiments</summary>

| Experiment | What it does | Runs on |
| --- | --- | --- |
| **Capability Explorer** | Scan this device with public APIs: hardware, sensors, cameras, display, and Apple features, each reported as available, unavailable, or unknown without triggering a permission prompt. | iPhone · iPad · Mac · Watch · TV |
| **Developer Tools Lab** | Catalog of Apple's developer tools and diagnostic utilities, what each does, and which parts the Toolbox reproduces with public APIs. | iPhone · iPad · Mac · TV |
| **Diagnostics** | Read this app's own unified log, measure a workload with signposts, receive MetricKit payloads, and inspect thermal, memory, MDM configuration and cellular radio state. | iPhone · iPad · Mac · TV |

</details>
<!-- catalog:end -->

## Getting started

**Requirements:** Xcode 26 or newer. Deployment targets: iOS / iPadOS 26.5, macOS 26.5, tvOS 26.0, watchOS 11.0.

1. Clone the repository.
2. Set your signing team and a bundle ID prefix you own — once, for every target:
   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig   # git-ignored
   ```
   Fill in `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX`. The bundle IDs, the App Group and the shared keychain group are all derived from the prefix (see `Config/Signing.xcconfig`), so there is nothing to change in the project.
3. Open `AppleToolbox.xcodeproj`, pick a scheme — `AppleToolbox iOS`, `AppleToolbox macOS`, `AppleToolbox tvOS` or `AppleToolbox watchOS` — and run.

The Simulator works for most of the UI, but sensors, radios, the Secure Enclave, NFC, UWB, LiDAR and Pencil need real hardware; there the app reports **Device Only** instead of pretending.

### Capabilities

Several experiments need capabilities on your App IDs. Automatic signing registers most of them on the first device build; a few are not available to free Personal Teams (the app lists which under *Apple programs*).

| Target | Capabilities |
| --- | --- |
| iOS app | Push Notifications, Time Sensitive Notifications, Sign in with Apple, Group Activities, HealthKit (+ Background Delivery), HomeKit, Matter Allow Setup Payload, Hotspot, Access Wi-Fi Information, Wireless Accessory Configuration, NFC Tag Reading, AutoFill Credential Provider, Network Extensions (Packet Tunnel), Personal VPN, App Groups, Keychain Sharing |
| macOS app | App Sandbox (camera, microphone, Bluetooth, USB, location, network client/server, user-selected files), hardened runtime, Sign in with Apple, Group Activities, App Groups, Keychain Sharing |
| tvOS app | HomeKit |
| watchOS app | HealthKit, HomeKit, Sign in with Apple, App Groups (MusicKit as an App Service) |
| Widgets, notification service | App Groups |
| Credential provider extension | AutoFill Credential Provider, App Groups |
| Packet tunnel extension | Network Extensions (Packet Tunnel) |

MusicKit and ShazamKit are App Services you enable for the App ID in the developer portal. Apple-managed capabilities (for example NFC card emulation, critical alerts, Tap to Pay or secure element credentials) are shown in the app as boundaries: you can see what they would need, but they cannot be used without Apple's approval.

## How it's built

| Scheme / target | What it is |
| --- | --- |
| `AppleToolbox iOS` | iPhone and iPad app; embeds the widget, the notification content and service extensions, the credential provider, the packet tunnel and the watch app; hosts the tests |
| `AppleToolbox macOS` | Mac app from the same sources, sandboxed |
| `AppleToolbox tvOS` | Apple TV app from the same sources, with its own focus-driven tab and card layout |
| `AppleToolbox watchOS` | Watch app (also runs without the iPhone): every watchOS experiment, motion, haptics, heart rate, WatchConnectivity transfers |
| `AppleToolbox Widget` | Home and Lock Screen widgets, an interactive widget, Control Center controls, the Live Activity |
| `AppleToolbox Notification Content` | Custom notification UI |
| `AppleToolbox Watch Widget` | Watch complications |
| `AppleToolbox Notification Service` | Rewrites remote pushes (`mutable-content`): title marker, image attachment |
| `AppleToolbox Credential Provider` | AutoFill extension with demo passwords and passkeys |
| `AppleToolbox Packet Tunnel` | Local-only packet tunnel for the 198.18.0.0/15 test range |

```text
AppleToolbox/
├── AppleToolboxApp.swift, ContentView.swift   app entry and sidebar (Tools · Explore · Inspect)
├── UI/
│   ├── ExperimentDetailView.swift   status, why-not, checks, run, requirements, documentation
│   ├── ExperimentLifecycle.swift    stops live sessions when you leave, reset
│   ├── Routes/                      run-view routing, one file per category
│   └── Experiments/                 run views
├── Shared/
│   ├── Models/              experiment model, status system, checks, explanations, tools
│   ├── ExperimentRegistry/  descriptors, one Registry+<Category>.swift per category
│   ├── PermissionSystem/    permission probes that never prompt, live availability
│   ├── CapabilitySystem/    device scanner, capability registry, provisioning inspector
│   └── Services/            the code that talks to Apple's frameworks
├── WatchApp/, WatchWidget/, Widget/, NotificationContent/
scripts/                     icon and README generators
docs/tasks/                  task briefs and reports
```

The whole project uses the Swift 6 language mode with `MainActor` default isolation. Framework callbacks that arrive on background queues are `@Sendable` or `nonisolated` and hop back to the main actor, so the strict concurrency checks hold at runtime too.

Run the tests with ⌘U on the `AppleToolbox iOS` scheme: Swift Testing unit tests in `AppleToolboxTests` and XCUITest smoke tests in `AppleToolboxUITests`.

## Contributing

Ideas for experiments, bug reports from real devices and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for how an experiment is put together and the few rules the project follows.

## License

Apple Toolbox is available under the [MIT License](LICENSE).

Apple, iPhone, iPad, Mac, Apple Watch, Apple TV and the names of Apple frameworks are trademarks of Apple Inc. This is an independent project and is not affiliated with or endorsed by Apple.
